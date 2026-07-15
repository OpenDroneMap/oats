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

`index.json` is the only file the viewer lists; it never enumerates the bucket:

```json
{ "generated": "...", "runs": [ {
  "key": "...", "timestamp": "...", "image": "...", "image_digest": "...",
  "odm_git_revision": "...", "group": "...",
  "datasets_total": 2, "passed": 0, "failed": 2 } ] }
```

`passed`/`failed` aggregate the per-dataset bats exit codes.

## Local setup (development)

Needs Docker. Secrets come from `storage/.env` (git-ignored — never commit).

```sh
cd storage
cp .env.example .env          # fill GARAGE_RPC_SECRET, GARAGE_ADMIN_TOKEN
docker compose up -d
./init.sh                      # idempotent: layout, bucket, website, writer key
                               # prints the writer key/secret once — save them
```

Then apply CORS so browsers can read cross-origin (needs an S3 client, e.g.
[`mc`](https://min.io/docs/minio/linux/reference/minio-mc.html)):

```sh
mc alias set oats http://127.0.0.1:3900 <KEY_ID> <SECRET>
mc cors set oats/oats-runs cors.xml
```

Anonymous read is served by Garage's web endpoint (`127.0.0.1:3902`), which
resolves the bucket by virtual host: it matches the request `Host` (port
stripped) against a bucket global alias. `init.sh` creates the alias `oats-runs`;
add one per public hostname the store is served under (see deployment). To reach
it from a local browser, point that hostname at `127.0.0.1` (a `/etc/hosts`
entry) or go through the reverse proxy.

## Publishing — `publish_run.sh`

Publishes a run directory to the Garage bucket and regenerates `index.json`.
Idempotent per run key (`mc mirror --remove`); needs `mc` and `jq`.

```sh
export AWS_ACCESS_KEY_ID=<key> AWS_SECRET_ACCESS_KEY=<secret>
./publish_run.sh ../results/runs/<rev>/<img>/<ts> s3://oats-runs \
    --endpoint http://127.0.0.1:3900
```

`mc` is found on `PATH` or via `OATS_MC=/path/to/mc`.

## Credentials

- `GARAGE_RPC_SECRET` / `GARAGE_ADMIN_TOKEN`: `storage/.env`, read by `compose.yaml`.
- Writer key/secret (from `init.sh`): the runner's CI secret store as
  `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`, plus the endpoint as a variable.
- The viewer needs no credentials.

Nothing secret is committed; `.env` and `compose.override.yaml` are git-ignored.

## Deployment on the Proxmox server

One always-on VM on the Proxmox host runs the CI job, Garage, and the viewer's
webserver. Garage stays bound to `127.0.0.1` (see `garage.toml`); the VM's
reverse proxy — the same one serving the viewer — fronts it publicly. VM
creation and GPU passthrough are the runner's concern, not the store's.

### 1. Proxmox host — attach the data disk, start on boot

Pass the spare drive through to the VM and make the VM come up after a host
reboot (so the store is always available):

```sh
qm set <vmid> -scsi1 /dev/disk/by-id/<drive-id>   # raw disk passthrough
qm set <vmid> -onboot 1
```

Snapshot before Garage upgrades for an instant rollback:
`qm snapshot <vmid> pre-upgrade`.

### 2. In the VM — mount the disk

The passed-through drive shows up as a new block device (check `lsblk` — likely
`/dev/sdb`). Format it once and mount it where Garage's data will live:

```sh
lsblk                                              # confirm the device first!
sudo mkfs.ext4 /dev/sdb
sudo mkdir -p /data
echo '/dev/sdb /data ext4 defaults,nofail 0 2' | sudo tee -a /etc/fstab
sudo mount -a
```

### 3. In the VM — deploy Garage

```sh
cd storage
printf 'GARAGE_RPC_SECRET=%s\nGARAGE_ADMIN_TOKEN=%s\n' \
  "$(openssl rand -hex 32)" "$(openssl rand -base64 32)" > .env

# Put Garage's data on the mounted disk (git-ignored override):
cat > compose.override.yaml <<YAML
services:
  garage:
    volumes:
      - /data/oats-garage/meta:/var/lib/garage/meta
      - /data/oats-garage/data:/var/lib/garage/data
YAML

docker compose up -d
./init.sh                                          # save the writer key/secret

curl -sSL https://dl.min.io/client/mc/release/linux-amd64/mc -o mc && chmod +x mc
./mc alias set oats http://127.0.0.1:3900 <KEY_ID> <SECRET>
./mc cors set oats/oats-runs cors.xml
```

### 4. Front it with the VM's reverse proxy

The web endpoint is on `127.0.0.1:3902`. Route the store's public hostname to it
through the same proxy that serves the viewer. Garage matches the request `Host`
against a bucket global alias, so alias the bucket to that hostname:

```sh
docker compose exec garage /garage bucket alias oats-runs oats-store.example.com
```

Example nginx server block (store on its own subdomain):

```nginx
server {
    server_name oats-store.example.com;
    location / {
        proxy_pass http://127.0.0.1:3902;
        proxy_set_header Host oats-store.example.com;
    }
}
```

If the viewer instead serves the store under its own origin (same-origin path),
CORS isn't needed; on a separate hostname the committed `cors.xml` covers it.
TLS is terminated by the proxy (or by however the VM is exposed publicly),
alongside the viewer.

### Durability

Single node, single disk. Runs are re-derivable (re-run CI), or sync the bucket
offsite with `rclone sync`. Back up the guest's config with `vzdump`; don't
bother capturing the bulk data disk.
