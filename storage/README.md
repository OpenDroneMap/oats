# OATS run artifact storage

Durable storage for OATS run directories, served read-only over HTTP(S).

**Backend: [Garage](https://garagehq.deuxfleurs.fr/)** — S3-compatible API which
means we keep the storage contract separate from the instance and can swap out
the backend later if we need more storage etc.

## Store contract

Each run sits at its identity path, exactly as the harness writes it:

```
oats-runs (bucket root)
  index.json                                    # every run, newest first
  <odm_git_short>/<image_key12>/<timestamp>/    # one self-contained run
    run_manifest.json
    reports/*.xml
    tests/<dataset>/<test>/...                  # the ODM outputs
```

The key is the manifest's `run_key`. `index.json` is all the viewer reads to
find runs; it never lists the bucket:

```json
{
  "generated": "...",
  "runs": [ {
    "key": "...",
    "timestamp": "...",
    "image": "...",
    "image_digest": "...",
    "odm_git_revision": "...",
    "group": "...",
    "datasets_total": 2,
    "passed": 0,
    "failed": 2
  } ]
}
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
cp inventory.example.yml inventory.yml     # update host, disk, hostname
ansible-playbook storage.yml
```

Garage holds the writer key and shows it on demand, so the deploy caches it in
root-only `/etc/oats/writer.env` and rewrites it if it goes missing.
`-e oats_fetch_writer_env=true` copies it back for CI.

Manual, on the Proxmox host — it needs hypervisor root, and the VM's lifecycle
belongs to the runner setup rather than the store:

```sh
qm set <vmid> -scsi1 /dev/disk/by-id/<drive-id>   # pass the data disk through
qm set <vmid> -onboot 1
```

Snapshot before a Garage upgrade: `qm snapshot <vmid> pre-upgrade`.

## Local development

To run the storage role locally, into `~/.local/share/oats-store`:

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

`index.json` is derived from the run manifests, so `--reindex` rebuilds it from
whatever is already in the store.

## Credentials

- `GARAGE_RPC_SECRET` / `GARAGE_ADMIN_TOKEN`: generated on first deploy into `.env`.
- Writer key: `/etc/oats/writer.env` and the CI secret store.
- The viewer needs none.

The writer key uses the standard S3 variable names, so any S3 tool reads it
without translation. Name the CI secrets for OATS and map them to those names in
the workflow.

`.env`, `compose.override.yaml`, `deploy/inventory.yml` and `deploy/writer.env`
are git-ignored.

## Durability

Single node, single disk. Runs are re-derivable by re-running CI; sync offsite
with `rclone sync`. Back up the guest with `vzdump`.
