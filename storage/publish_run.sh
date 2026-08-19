#!/bin/bash
#
# Publish an OATS run directory to the Garage (S3) store and regenerate the
# store's index.json. Idempotent per run key. See storage/README.md.
#
# Usage:
#   publish_run.sh <run_dir> <s3_url> --endpoint URL
#   publish_run.sh --reindex <s3_url> --endpoint URL
#
#   <run_dir>   A run directory containing run_manifest.json, e.g.
#               results/runs/<rev>/<img>/<timestamp>
#   <s3_url>    Bucket URL, e.g. s3://oats-runs
#
# Options:
#   --endpoint URL   S3 endpoint, e.g. http://127.0.0.1:3900 (required)
#   --reindex        Rebuild index.json from the manifests already in the
#                    store, without publishing a run
#   --mc PATH        mc binary to use (default: mc on PATH, or $OATS_MC)
#   -h, --help       Show this help
#
# S3 credentials are read from the environment:
#   AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY

set -euo pipefail

usage() {
	sed -n '2,/^set -euo/p' "$0" | sed 's/^#\?//;s/^ //' | head -n -1
	exit "${1:-0}"
}

RUN_DIR=""
TARGET=""
ENDPOINT=""
REINDEX=NO
MC="${OATS_MC:-mc}"

while [ $# -gt 0 ]; do
	case "$1" in
		--endpoint) ENDPOINT="$2"; shift 2;;
		--reindex) REINDEX=YES; shift;;
		--mc) MC="$2"; shift 2;;
		-h|--help) usage 0;;
		-*) echo "Unknown option: $1" >&2; usage 1;;
		*)
			if [ -z "$RUN_DIR" ]; then RUN_DIR="$1"
			elif [ -z "$TARGET" ]; then TARGET="$1"
			else echo "Unexpected argument: $1" >&2; usage 1
			fi
			shift;;
	esac
done

# --reindex takes no run directory, so the sole positional is the target
if [ "$REINDEX" = YES ] && [ -z "$TARGET" ]; then
	TARGET="$RUN_DIR"
	RUN_DIR=""
fi

[ -n "$TARGET" ] || usage 1
[ "$REINDEX" = YES ] || [ -n "$RUN_DIR" ] || usage 1
case "$TARGET" in
	s3://*) ;;
	*) echo "Target must be an s3:// URL (e.g. s3://oats-runs)" >&2; usage 1;;
esac
[ -n "$ENDPOINT" ] || { echo "--endpoint is required" >&2; usage 1; }
[ -n "${AWS_ACCESS_KEY_ID:-}" ] && [ -n "${AWS_SECRET_ACCESS_KEY:-}" ] \
	|| { echo "AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY must be set" >&2; exit 1; }

command -v jq >/dev/null || { echo "jq is required" >&2; exit 1; }
command -v "$MC" >/dev/null || { echo "mc client not found: $MC" >&2; exit 1; }

RUN_KEY=""
if [ "$REINDEX" = NO ]; then
	MANIFEST="$RUN_DIR/run_manifest.json"
	[ -f "$MANIFEST" ] || { echo "No run_manifest.json in $RUN_DIR" >&2; exit 1; }

	# The run key is the run's identity path, written by the harness. Fall back
	# to the run directory's own trailing <rev>/<img>/<timestamp> path if absent.
	RUN_KEY=$(jq -r '.run_key // empty' "$MANIFEST")
	if [ -z "$RUN_KEY" ]; then
		abs=$(cd "$RUN_DIR" && pwd)
		RUN_KEY=$(echo "$abs" | rev | cut -d/ -f1-3 | rev)
	fi
	[ -n "$RUN_KEY" ] || { echo "Could not determine run key" >&2; exit 1; }
fi

# jq program turning a stream of run manifests into the store index. Each run
# contributes its identity plus an aggregate pass/fail count derived from the
# per-dataset bats exit codes.
INDEX_JQ='{
  generated: (now | todateiso8601),
  runs: [ .[] | {
      key: .run_key,
      timestamp: .timestamp,
      image: .image,
      image_digest: .image_digest,
      odm_git_revision: .odm_git_revision,
      group: .group,
      datasets_total: (.datasets | length),
      passed: ([.datasets[] | select(.bats_exit == 0)] | length),
      failed: ([.datasets[] | select(.bats_exit != 0)] | length)
    } ] | sort_by(.timestamp) | reverse
}'

# bucket[/prefix] from s3://bucket[/prefix]
path="${TARGET#s3://}"
alias="oats-publish-$$"
base="$alias/$path"

cfg=$(mktemp -d)
trap 'rm -rf "$cfg"' EXIT
"$MC" --config-dir "$cfg" alias set "$alias" "$ENDPOINT" \
	"$AWS_ACCESS_KEY_ID" "$AWS_SECRET_ACCESS_KEY" >/dev/null

# The manifests in the store are the source of truth and index.json is derived
# from them, so it can be rebuilt at any time. It is assembled locally and
# checked before upload: a failed enumeration must not replace a populated
# index with a short or empty one.
reindex() {
	local required="${1:-}" keys="$cfg/keys" manifests="$cfg/manifests" index="$cfg/index.json"

	"$MC" --config-dir "$cfg" find "$base" --name run_manifest.json > "$keys"
	: > "$manifests"
	while IFS= read -r key; do
		"$MC" --config-dir "$cfg" cat "$key" >> "$manifests"
	done < "$keys"

	jq -s "$INDEX_JQ" < "$manifests" > "$index"
	INDEX_COUNT=$(jq '.runs | length' "$index")

	[ "$INDEX_COUNT" -gt 0 ] || { echo "Enumerated no runs; leaving index.json alone" >&2; exit 1; }
	if [ -n "$required" ]; then
		jq -e --arg k "$required" 'any(.runs[]; .key == $k)' "$index" >/dev/null \
			|| { echo "$required missing from the rebuilt index; leaving index.json alone" >&2; exit 1; }
	fi

	"$MC" --config-dir "$cfg" pipe "$base/index.json" < "$index" >/dev/null
}

if [ "$REINDEX" = YES ]; then
	reindex
	echo "Rebuilt $TARGET/index.json ($INDEX_COUNT runs)"
	exit 0
fi

"$MC" --config-dir "$cfg" mirror --overwrite --remove "$RUN_DIR/" "$base/$RUN_KEY" >/dev/null
reindex "$RUN_KEY"

echo "Published run $RUN_KEY to $TARGET/$RUN_KEY"
echo "Regenerated $TARGET/index.json ($INDEX_COUNT runs)"
