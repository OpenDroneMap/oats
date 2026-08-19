# OATS run artifact storage

Durable, addressable storage for OATS run directories, served read-only over
HTTP(S) so the comparison viewer can enumerate and load runs.

**Backend: [Garage](https://garagehq.deuxfleurs.fr/)** — an S3-compatible object
store that ships as a single Rust binary (`dxflrs/garage`), run single-node with
`replication_factor = 1`. Chosen over the archived MinIO CE and a plain
nginx-over-a-directory: the S3 API lets the backend be swapped or grown
(multi-node / offsite) with only an endpoint change. CI and the viewer depend
only on the contract below, never on Garage itself.

## Store contract

The store mirrors the harness layout — no re-keying at publish time. Each run
sits at its identity path with a top-level `index.json` next to it:

```
oats-runs (bucket root)
  index.json                                   # every run, newest first
  <odm_git_short>/<image_key12>/<timestamp>/    # one self-contained run
    run_manifest.json
    reports/*.xml
    <tag>/<dataset>/<test>/...                  # the ODM outputs
```

The key is the run directory's own relative path under `results/runs/` — read
straight from `run_manifest.json`'s `run_key`.

`index.json` is the only file the viewer reads to discover runs; it never
enumerates the bucket:

```json
{ "generated": "...", "runs": [ {
  "key": "...", "timestamp": "...", "image": "...", "image_digest": "...",
  "odm_git_revision": "...", "group": "...",
  "datasets_total": 2, "passed": 0, "failed": 2 } ] }
```

`passed`/`failed` aggregate the per-dataset bats exit codes.

## Deployment

`deploy/` holds an Ansible role that does the whole host setup: mounts the data
disk, deploys this directory, generates Garage's secrets, starts the container,
runs `init.sh`, applies CORS, and aliases the bucket to the public hostname
(optionally writing the nginx vhost). It is idempotent — re-run it to roll out a
config change.

```sh
cd deploy
ansible-galaxy collection install -r requirements.yml
cp inventory.example.yml inventory.yml     # set the host, disk and hostname
ansible-playbook storage.yml
```

The writer credentials are generated on first run and left in
`/etc/oats/writer.env` on the host (root-only); pass `-e oats_fetch_writer_env=true`
to copy them back for pasting into the CI secret store. Garage only reveals a
secret at creation, so if that file is lost the key has to be reissued.

Two things stay manual, on the Proxmox host — they are one-shot and outside the
VM:

```sh
qm set <vmid> -scsi1 /dev/disk/by-id/<drive-id>   # pass the data disk through
qm set <vmid> -onboot 1                           # store is always-on
```

Snapshot before a Garage upgrade (`qm snapshot <vmid> pre-upgrade`) for instant
rollback.

> Status: the role is verified end-to-end against a local Garage (fresh deploy,
> idempotent re-run, publish, cross-origin read). Running it against the
> Proxmox VM is the one remaining step, pending access to that host.

## Local development

Docker only — no Ansible needed:

```sh
cp .env.example .env          # fill GARAGE_RPC_SECRET, GARAGE_ADMIN_TOKEN
docker compose up -d
./init.sh                      # idempotent; prints the writer key once
mc alias set oats http://127.0.0.1:3900 <KEY_ID> <SECRET>
mc cors set oats/oats-runs cors.xml
```

Garage resolves a bucket from the request `Host`, matched against a bucket
global alias. `init.sh` creates the alias `oats-runs`; to reach the web endpoint
(`127.0.0.1:3902`) from a browser, point that name at `127.0.0.1` in
`/etc/hosts`, or add an alias for whatever hostname you use.

## Publishing

`./publish_run.sh <run_dir> s3://oats-runs --endpoint http://127.0.0.1:3900`
writes a run and regenerates `index.json`. Idempotent per run key; needs `mc`
and `jq`. Credentials come from `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`.
See `--help`.

## Credentials

- `GARAGE_RPC_SECRET` / `GARAGE_ADMIN_TOKEN`: `storage/.env`, read by `compose.yaml`.
- Writer key/secret: `/etc/oats/writer.env` on the host, and the CI secret store.
- The viewer needs none — it reads the public endpoint only.

Nothing secret is committed; `.env`, `compose.override.yaml`, `deploy/inventory.yml`
and `deploy/writer.env` are git-ignored.

## Durability

Single node, single disk. Runs are re-derivable (re-run CI), or sync the bucket
offsite with `rclone sync`. Back up the guest's config with `vzdump`; don't
bother capturing the bulk data disk.
