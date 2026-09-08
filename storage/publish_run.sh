#!/bin/bash
#
# Publish an OATS run directory to the Garage (S3) store and regenerate the
# store's index.json. Idempotent per run key. See storage/README.md.
#
# Only the primary outputs are published: the run manifests and reports, each
# test's logs and options, and per test the orthophoto, DEMs, georeferenced
# point cloud and report. Input images, OpenSfM/OpenMVS intermediates, meshes
# and textures stay on the runner.
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
#   -h, --help       Show this help
#
# S3 credentials are read from the environment:
#   AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY
#
# Needs rclone and jq.

set -euo pipefail

usage() {
	sed -n '2,/^set -euo/p' "$0" | sed 's/^#\?//;s/^ //' | head -n -1
	exit "${1:-0}"
}

die() {
	echo "$*" >&2
	exit 1
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

# rclone filter selecting what is published. First match wins; the final rule
# drops everything not listed, and rclone does not descend into directories
# nothing could match, so opensfm/, images/ and submodels/ are never walked.
PUBLISH_FILTER='
+ /run_manifest.json
+ /oats_manifest.tsv
+ /reports/**
+ /tests/*/*/*.json
+ /tests/*/*/*.txt
+ /tests/*/*/odm_orthophoto/odm_orthophoto.tif
+ /tests/*/*/odm_dem/*.tif
+ /tests/*/*/odm_georeferencing/odm_georeferenced_model.laz
+ /tests/*/*/odm_report/**
- *
'

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
	local required="${1:-}" manifests="$CFG/manifests" index="$CFG/index.json" count

	rclone cat "$STORE" --include 'run_manifest.json' > "$manifests"
	jq -s "$INDEX_JQ" < "$manifests" > "$index"
	count=$(jq '.runs | length' "$index")

	[ "$count" -gt 0 ] || die "Enumerated no runs; leaving index.json alone"
	if [ -n "$required" ]; then
		jq -e --arg k "$required" 'any(.runs[]; .key == $k)' "$index" >/dev/null \
			|| die "$required missing from the rebuilt index; leaving index.json alone"
	fi

	rclone rcat "$STORE/index.json" < "$index"
	echo "$count"
}

# --- Arguments ---------------------------------------------------------------

ENDPOINT=""
REINDEX=false
positional=()

while [ $# -gt 0 ]; do
	case "$1" in
		--endpoint) ENDPOINT="$2"; shift 2;;
		--reindex) REINDEX=true; shift;;
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
command -v rclone >/dev/null || die "rclone is required"

# --- Publish -----------------------------------------------------------------

CFG=$(mktemp -d)
trap 'rm -rf "$CFG"' EXIT

# An on-the-fly S3 remote against the Garage endpoint, credentials from the
# AWS_* variables. The empty config file stops rclone announcing that it has
# none; the key never appears on a command line.
: > "$CFG/rclone.conf"
export RCLONE_CONFIG="$CFG/rclone.conf"
export RCLONE_S3_PROVIDER=Other
export RCLONE_S3_ENDPOINT="$ENDPOINT"
export RCLONE_S3_REGION=garage
export RCLONE_S3_ENV_AUTH=true
export RCLONE_S3_NO_CHECK_BUCKET=true

# :s3:bucket[/prefix] from s3://bucket[/prefix]
STORE=":s3:${TARGET#s3://}"

if $REINDEX; then
	count=$(reindex)
	echo "Rebuilt $TARGET/index.json ($count runs)"
	exit 0
fi

RUN_KEY=$(run_key_of "$RUN_DIR")
printf '%s' "$PUBLISH_FILTER" > "$CFG/filter"
# --delete-excluded also trims anything a fuller earlier publish left behind.
rclone sync "$RUN_DIR" "$STORE/$RUN_KEY" --filter-from "$CFG/filter" --delete-excluded
count=$(reindex "$RUN_KEY")

echo "Published run $RUN_KEY to $TARGET/$RUN_KEY"
echo "Regenerated $TARGET/index.json ($count runs)"
