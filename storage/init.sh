#!/bin/bash
#
# One-time initialisation of the Garage cluster used to store OATS runs.
# Idempotent: safe to re-run. Performs the Garage-CLI setup (single-node
# layout, bucket, website hosting, writer key). The CORS step needs an S3
# client and is documented separately in README.md.
#
# Run from the storage/ directory after `docker compose up -d`:
#   ./init.sh
#
# Prints the writer key credentials at the end. Store them in an env file /
# CI secret (see README) -- never commit them.

set -euo pipefail

BUCKET="${OATS_BUCKET:-oats-runs}"
KEY_NAME="${OATS_KEY_NAME:-oats-writer}"
CAPACITY="${OATS_CAPACITY:-100G}"
ZONE="${OATS_ZONE:-dc1}"

g() { docker compose exec -T -e RUST_LOG=error garage /garage "$@"; }

echo "Waiting for Garage to be reachable..."
for _ in $(seq 1 30); do
	if g status >/dev/null 2>&1; then break; fi
	sleep 1
done

# Assign a layout to the single node if it has no role yet.
node=$(g status 2>/dev/null | awk '/NO ROLE ASSIGNED/{print $1}')
if [ -n "$node" ]; then
	echo "Assigning layout to node $node ($CAPACITY, zone $ZONE)..."
	g layout assign -z "$ZONE" -c "$CAPACITY" "$node" >/dev/null
	ver=$(g layout show 2>/dev/null | awk '/Current cluster layout version/{print $NF}')
	g layout apply --version "$((ver + 1))" >/dev/null
	echo "Layout applied."
else
	echo "Node already has a role; skipping layout assignment."
fi

# Create the bucket and enable public website (anonymous read) hosting.
if ! g bucket info "$BUCKET" >/dev/null 2>&1; then
	echo "Creating bucket $BUCKET..."
	g bucket create "$BUCKET" >/dev/null
fi
g bucket website --allow "$BUCKET" >/dev/null
echo "Bucket $BUCKET ready with website (anonymous read) enabled."

# Create the writer key if it does not exist and grant it access.
if g key info "$KEY_NAME" >/dev/null 2>&1; then
	echo "Key $KEY_NAME already exists; not recreating (its secret is only shown at creation)."
	g bucket allow --read --write --owner "$BUCKET" --key "$KEY_NAME" >/dev/null
else
	echo "Creating writer key $KEY_NAME..."
	created=$(g key create "$KEY_NAME" 2>/dev/null)
	g bucket allow --read --write --owner "$BUCKET" --key "$KEY_NAME" >/dev/null
	kid=$(echo "$created" | awk -F': ' '/Key ID/{print $2}')
	ksec=$(echo "$created" | awk -F': ' '/Secret key/{print $2}')
	echo
	echo "=========================================================="
	echo "Writer key created -- store these, they are shown ONCE:"
	echo "  AWS_ACCESS_KEY_ID=$kid"
	echo "  AWS_SECRET_ACCESS_KEY=$ksec"
	echo "=========================================================="
fi

echo
echo "Next: apply CORS so browsers can read runs (see README):"
echo "  mc alias set oats http://localhost:3900 <KEY_ID> <SECRET>"
echo "  mc cors set oats/$BUCKET cors.xml"
