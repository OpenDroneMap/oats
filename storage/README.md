# OATS run artifact storage

Durable storage for OATS run directories, served read-only over HTTP(S) for the
comparison viewer.

**Backend: [Garage](https://garagehq.deuxfleurs.fr/)** — S3-compatible, a single
Rust binary, single-node with `replication_factor = 1`. Chosen over the archived
MinIO CE and nginx-over-a-directory for its S3 API, so it can be swapped or
grown later. CI and the viewer depend on the contract below, not on Garage.

## Store contract

Each run sits at its identity path, exactly as the harness writes it:

```
oats-runs (bucket root)
  index.json                                   # every run, newest first
  <odm_git_short>/<image_key12>/<timestamp>/    # one self-contained run
    run_manifest.json
    reports/*.xml
    tests/<dataset>/<test>/...                  # the ODM outputs
```

The key is the manifest's `run_key`. `index.json` is all the viewer reads to
find runs; it never lists the bucket:

```json
{ "generated": "...", "runs": [ {
  "key": "...", "timestamp": "...", "image": "...", "image_digest": "...",
  "odm_git_revision": "...", "group": "...",
  "datasets_total": 2, "passed": 0, "failed": 2 } ] }
```

`passed`/`failed` aggregate per-dataset bats exit codes.

## Deployment

`deploy/` holds an idempotent Ansible role; re-run it for any change:

- `disk.yml` — data disk
- `service.yml` — config, secrets, container
- `cluster.yml` — layout, bucket, anonymous read
- `credentials.yml` — writer key
- `access.yml` — `mc`, CORS
- `proxy.yml` — hostname alias, nginx vhost

```sh
cd deploy
ansible-galaxy collection install -r requirements.yml
cp inventory.example.yml inventory.yml     # host, disk, hostname
ansible-playbook storage.yml
```

Writer credentials land in root-only `/etc/oats/writer.env`;
`-e oats_fetch_writer_env=true` copies them back for CI. Garage reveals a secret
only at creation.

Manual, one-shot, on the Proxmox host:

```sh
qm set <vmid> -scsi1 /dev/disk/by-id/<drive-id>   # pass the data disk through
qm set <vmid> -onboot 1
```

Snapshot before a Garage upgrade: `qm snapshot <vmid> pre-upgrade`.

> Not yet run against the Proxmox VM; that is the remaining deployment step.

## Local development

The same role against this machine, into `~/.local/share/oats-store`:

```sh
cd deploy
ansible-playbook -i inventory.local.yml storage.yml
```

Garage resolves the bucket from the request `Host`. To browse
`127.0.0.1:3902`, point `oats-runs` at `127.0.0.1` in `/etc/hosts`.

## Publishing

```sh
./publish_run.sh <run_dir> s3://oats-runs --endpoint http://127.0.0.1:3900
```

Idempotent per run key. Needs `mc`, `jq`, and `AWS_ACCESS_KEY_ID` /
`AWS_SECRET_ACCESS_KEY`. See `--help`.

## Credentials

- `GARAGE_RPC_SECRET` / `GARAGE_ADMIN_TOKEN`: generated on first deploy into `.env`.
- Writer key: `/etc/oats/writer.env` and the CI secret store.
- The viewer needs none.

`.env`, `compose.override.yaml`, `deploy/inventory.yml` and `deploy/writer.env`
are git-ignored.

## Durability

Single node, single disk. Runs are re-derivable by re-running CI; sync offsite
with `rclone sync`. Back up the guest with `vzdump`.
