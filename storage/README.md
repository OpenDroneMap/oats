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

Each run is stored under its `run_key` from `run_manifest.json`. `index.json` is
all the viewer reads to find runs:

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

`deploy/` holds an idempotent Ansible role; re-run it for any change. The
target needs systemd and ssh; the role installs the rest:

- `service.yml` — `garage` binary, secrets, config, systemd unit
- `bucket.yml` — anonymous read, CORS
- `proxy.yml` — hostname alias, nginx vhost

Step one is to set up a separate VM in proxmox that will host our data. It needs
Debian or Ubuntu (apt), an ssh user with sudo, and the disk mounted at
`/var/lib/garage` (you can change the path in the inventory if preferred).

Add a vhost to the `nginx` proxy:

```nginx
server {
    server_name oats-store.opendronemap.org;   # eg.
    location / {
        proxy_pass http://<vm>:3902;
        proxy_set_header Host $host;   # Garage picks the bucket by Host
        proxy_buffering off;           # ODM outputs are large
        ...
    }
}
```

The S3 API listens on port 3900 and the web endpoint on 3902, on every
interface; RPC and the admin API stay on loopback.

Set `oats_public_hostname` in the inventory to the `server_name` in nginx: the
role aliases the bucket to it, which is how Garage maps the domain to the
bucket. Set `oats_nginx_manage` only when nginx runs on the store VM itself.

```sh
cd deploy
cp inventory.example.yml inventory.yml     # update host, user, hostname
ansible-playbook storage.yml
```

The role generates the writer key on the first run and prints it at the end, for
the CI secret store. Afterwards, `sudo cat /etc/oats/writer.env` on the host.

Garage runs as the `garage` user under systemd, configured by
`/etc/garage.toml`. `garage status` on the host shows the node.

To update versions, set `oats_garage_version` and `oats_garage_sha256` to the
new release and re-run the playbook.

## Testing

The role has a [Molecule](https://ansible.readthedocs.io/projects/molecule/)
scenario that applies it to a systemd container, applies it again to check
nothing changes, then checks the bucket is served anonymously with CORS:

```sh
uv tool install molecule --with 'molecule-plugins[docker]' --with ansible-core
uv tool install ansible-core
ansible-galaxy collection install community.docker
cd deploy/roles/oats_storage
molecule test
```

`molecule converge` leaves the container running for inspection;
`molecule destroy` removes it.

## Publishing

```sh
./publish_run.sh <run_dir> s3://oats-runs --endpoint http://<vm>:3900
```

Idempotent per run key. Needs `mc`, `jq`, and `AWS_ACCESS_KEY_ID` /
`AWS_SECRET_ACCESS_KEY`. See `--help`.

`index.json` is derived from the run manifests, so `--reindex` rebuilds it from
whatever is already in the store.

## Credentials

- `rpc_secret`, `admin_token`: generated on first deploy into `/etc/oats`,
  readable only by the `garage` user. The admin API listens on loopback
  port 3903.
- Writer key: `/etc/oats/writer.env`, root-only, and the CI secret store.
- The viewer needs none.

The writer key uses the standard S3 variable names, so any S3 tool reads it
without translation. Name the CI secrets for OATS and map them to those names in
the workflow.

`deploy/inventory.yml` is git-ignored.

## Durability

Single node, single disk. Runs are re-derivable by re-running CI; sync offsite
with `rclone sync`. Back up the guest with `vzdump`.
