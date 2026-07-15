# CI

`.github/workflows/oats.yml` runs the suite on a self-hosted runner: on demand,
when OATS master changes, and when ODM publishes a new image. The workflow
itself is the reference for what runs when — this covers the parts that live
outside it, namely the runner, the cross-repo token and the ODM-side trigger.

## The runner

Register a runner against this repository (*Settings → Actions → Runners*). The
default `self-hosted` label is all the workflow asks for.

It needs docker, plus `git`, `wget`, `rsync`, `sed`, `unzip` and `jq` on `PATH`;
`./run` bootstraps bats itself. Give it plenty of RAM — the suite is RAM-bound
and the `all` group sets the ceiling — and tens of GB of disk. The workspace
persists between runs: datasets are cached under `datasets/`, and every run
writes a full set of ODM outputs under `results/runs/`. Nothing prunes those
yet.

Keep a single runner attached. The workflow serialises runs with a `concurrency`
group, but that only helps if there is one machine to serialise onto — a second
runner would happily pick up a queued run alongside the first.

## No GPU

I assume the runner has no GPU, so the suite only exercises ODM's CPU path, and
`opendronemap/odm:gpu` is not tested at all — `publish-docker-gpu.yaml` has no
dispatch step by design. Testing it would need GPU hardware with
`nvidia-container-toolkit`, a `--gpus` flag in the harness's `docker run` (it
passes none today), and the dispatch step added on the ODM side.

## The ODM trigger

ODM's `publish-docker.yaml` dispatches to OATS after pushing a new image. The
payload contract is at the top of `oats.yml`; the ODM-side step is:

```yaml
    - name: Trigger OATS test suite
      run: |
        curl -sSf -X POST \
          -H "Accept: application/vnd.github+json" \
          -H "Authorization: Bearer ${{ secrets.OATS_DISPATCH_TOKEN }}" \
          https://api.github.com/repos/OpenDroneMap/oats/dispatches \
          -d '{"event_type":"odm-image-published","client_payload":{"image":"opendronemap/odm","tag":"latest"}}'
```

`OATS_DISPATCH_TOKEN` is a secret on the **ODM** repository, not this one. The
`GITHUB_TOKEN` Actions provides will not do: it is scoped to the repository
running the workflow, and events raised with it never start a workflow run.

To generate one, from an account with admin on this repo:

1. *Settings → Developer settings → Personal access tokens → Fine-grained
   tokens → Generate new token*.
2. Resource owner **OpenDroneMap**. Org-owned tokens need an org owner to
   approve the request before they work.
3. Repository access: *Only select repositories* → `OpenDroneMap/oats`.
4. Repository permissions: **Contents → Read and write**. Broader than we want,
   but `repository_dispatch` has no permission of its own and GitHub files it
   under Contents.
5. Add it to ODM under *Settings → Secrets and variables → Actions → New
   repository secret*, named `OATS_DISPATCH_TOKEN`.

Fine-grained tokens expire, so note the date. When one lapses the dispatch step
fails and the ODM publish job goes red — the image is already pushed by then, so
it is only the OATS run that is lost. A classic PAT with `repo` scope works too
and can be set never to expire, at the cost of reaching every repo its owner can.

## Results

Runs upload the run directory as a GitHub artifact with a 14-day retention.
That is a placeholder until the storage service lands — see the
`TODO(storage)` in `oats.yml`.
