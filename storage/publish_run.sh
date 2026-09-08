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

die() {
	echo "$*" >&2
	exit 1
}

# mc with the throwaway config dir created below.
s3() {
	"$MC" --config-dir "$CFG" "$@"
}

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

# The run key is the run's identity path, written by the harness. Fall back
# to the run directory's own trailing <rev>/<img>/<timestamp> path if absent.
run_key_of() {
	local run_dir="$1" manifest="$1/run_manifest.json" key
	[ -f "$manifest" ] || die "No run_manifest.json in $run_dir"

	key=$(jq -r '.run_key // empty' "$manifest")
	[ -n "$key" ] || key=$(cd "$run_dir" && pwd | awk -F/ '{ print $(NF-2) "/" $(NF-1) "/" $NF }')
	[ -n "$key" ] || die "Could not determine run key"

	echo "$key"
}

# The manifests in the store are the source of truth and index.json is derived
# from them, so it can be rebuilt at any time. It is assembled locally and
# checked before upload: a failed enumeration must not replace a populated
# index with a short or empty one. Prints the number of runs indexed.
reindex() {
	local required="${1:-}" keys="$CFG/keys" manifests="$CFG/manifests" index="$CFG/index.json" count

	s3 find "$BASE" --name run_manifest.json > "$keys"
	: > "$manifests"
	while IFS= read -r key; do
		s3 cat "$key" >> "$manifests"
	done < "$keys"

	jq -s "$INDEX_JQ" < "$manifests" > "$index"
	count=$(jq '.runs | length' "$index")

	[ "$count" -gt 0 ] || die "Enumerated no runs; leaving index.json alone"
	if [ -n "$required" ]; then
		jq -e --arg k "$required" 'any(.runs[]; .key == $k)' "$index" >/dev/null \
			|| die "$required missing from the rebuilt index; leaving index.json alone"
	fi

	s3 pipe "$BASE/index.json" < "$index" >/dev/null
	echo "$count"
}

# --- Arguments ---------------------------------------------------------------

ENDPOINT=""
REINDEX=false
MC="${OATS_MC:-mc}"
positional=()

while [ $# -gt 0 ]; do
	case "$1" in
		--endpoint) ENDPOINT="$2"; shift 2;;
		--reindex) REINDEX=true; shift;;
		--mc) MC="$2"; shift 2;;
		-h|--help) usage 0;;
		-*) echo "Unknown option: $1" >&2; usage 1;;
		*) positional+=("$1"); shift;;
	esac
done

RUN_DIR=""
if $REINDEX; then
	[ ${#positional[@]} -eq 1 ] || usage 1
	TARGET="${positional[0]}"
else
	[ ${#positional[@]} -eq 2 ] || usage 1
	RUN_DIR="${positional[0]}"
	TARGET="${positional[1]}"
fi

case "$TARGET" in
	s3://*) ;;
	*) echo "Target must be an s3:// URL (e.g. s3://oats-runs)" >&2; usage 1;;
esac
[ -n "$ENDPOINT" ] || { echo "--endpoint is required" >&2; usage 1; }
[ -n "${AWS_ACCESS_KEY_ID:-}" ] && [ -n "${AWS_SECRET_ACCESS_KEY:-}" ] \
	|| die "AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY must be set"

command -v jq >/dev/null || die "jq is required"
command -v "$MC" >/dev/null || die "mc client not found: $MC"

# --- Publish -----------------------------------------------------------------

CFG=$(mktemp -d)
trap 'rm -rf "$CFG"' EXIT

# <alias>/bucket[/prefix] from s3://bucket[/prefix]
ALIAS="oats-publish-$$"
BASE="$ALIAS/${TARGET#s3://}"
s3 alias set "$ALIAS" "$ENDPOINT" "$AWS_ACCESS_KEY_ID" "$AWS_SECRET_ACCESS_KEY" >/dev/null

if $REINDEX; then
	count=$(reindex)
	echo "Rebuilt $TARGET/index.json ($count runs)"
	exit 0
fi

RUN_KEY=$(run_key_of "$RUN_DIR")
s3 mirror --overwrite --remove "$RUN_DIR/" "$BASE/$RUN_KEY" >/dev/null
count=$(reindex "$RUN_KEY")

echo "Published run $RUN_KEY to $TARGET/$RUN_KEY"
echo "Regenerated $TARGET/index.json ($count runs)"
