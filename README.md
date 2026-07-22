![oats-icon](https://user-images.githubusercontent.com/1951843/47456353-42314880-d7a2-11e8-8fb1-81815ba78353.png)

# OpenDroneMap Automated Testing Suite

An intuitive set of tools and scripts to test and analyze datasets processed with OpenDroneMap favoring convention over configuration.

## Requirements

OATS is mostly a set of Bash scripts and as such runs best on POSIX environments (Linux, Mac). But you can run OATS on Windows 10 using WSL too.

You will need a working installation of `docker` for your environment. Please visit https://www.docker.com/ for resources on how to install docker for your platform.

## Getting Started

```bash
git clone https://github.com/OpenDroneMap/oats --depth 1
cd oats
./run --help
```

Upon startup `run` will attempt to download and install any missing dependency, including [bats](https://github.com/sstephenson/bats), `wget`, `rsync`, `sed` and `unzip` if they are missing.

To test the `latest` tag release of OpenDroneMap on all defined datasets, simply run:

```bash
./run all
```

This command will download the datasets, run the `opendronemap/odm:latest` docker image against each dataset and check that the processing succeeded.

## Test Your Datasets

To test a new dataset, create a new `tests/my_dataset.oat` file and copy paste the following:

```bash
@test "Default options" {
  $run_test "--orthophoto-resolution 5"
}
```

`.oat` files are just `.bats` files with a few special commands of their own.

Then place your images in `datasets/my_dataset/images` and run:

```bash
./run all --datasets my_dataset
```

You can also specify a `DATASET_URL` variable at the top of your `my_dataset.oat` file with a link to your dataset. OATS will automatically download it for you if it's not present in the `datasets/` directory.

```bash
DATASET_URL=https://github.com/myuser/myrepo/archive/master.zip

@test "Default options" {
  $run_test "--orthophoto-resolution 5"
}
```

After the call to `$run_test` is completed you can perform further checks such as verifying that a file exists or that an output matches a certain rule using Bash expressions.

```bash
@test "Default options" {
  $run_test "--orthophoto-resolution 5"

  # Check that an orthophoto was indeed created successfully
  [ -e "$output_dir/odm_orthophoto/odm_orthophoto.tif" ]
}
```

Checks that fail will be flagged by the testing suite.

Don't forget to open a [pull request](https://github.com/OpenDroneMap/oats/compare) to share your dataset with the community when you are ready! :pray: :+1:

## Create Groups

You can group together various datasets, for example by number of images, by manually specifying which datasets belong to the group or any other logic. Groups are placed in the `groups` folder. By default the `all` group includes all datasets.

You can select a subset of datasets within a group by using the `--datasets` option. For example:

```bash
./run all --datasets brighton,sheffield_park_1
```

First selects all datasets defined in `groups/all.bash` and then filters out only those matching the name `brighton` and `sheffield_park_1`. The end result in this case is to run two test cases (`brighton` and `sheffield_park_1`).

## Test Multiple Versions of OpenDroneMap

You can test multiple OpenDroneMap versions against one or more datasets. First build docker images for each OpenDroneMap version you want to test.

```bash
cd OpenDroneMap/
docker build -t opendronemap/odm:myversion .
```

Then run the suite once per version with the `--tag` parameter:

```bash
./run all --tag latest
./run all --tag myversion
```

Each run writes its results to a separate directory (see below), so you can compare them afterwards.

## Rerunning Tests

Every run starts from a fresh directory and processes each dataset from scratch. Old runs pile up under `results/runs/` and can be deleted whenever you want.

If you need to resume a pipeline from a previous run, invoke ODM directly against that run's output directory:

```bash
docker run -v <old_output>:/datasets/code opendronemap/odm --project-path /datasets --rerun-from odm_meshing
```

## Examine Test Results

At the end of a run, `run` prints a PASS/FAIL summary for each dataset with its wall time, and lists the failures with the ODM exit status (and signal name if it was killed, e.g. SIGSEGV) and the path to the full log. An ODM exit status of 0 on a failed test means ODM finished but a post-run check in the `.oat` file failed.

`run` exits with a non-zero status if any test failed, so it can be used as a CI gate.

### Run artifacts

Each run writes to its own directory (ignored by git):

```
results/runs/<odm revision>/<image key>/<timestamp>/
```

The ODM revision is read from the image's `org.opencontainers.image.revision` label and the image key from the image digest (or the image id for local builds); either falls back to `unknown`, and `--test` runs use `unknown/unknown`. Runs of the same ODM version end up next to each other, which makes them easy to compare. The directory contains:

- `run_manifest.json`: the run key, docker image name/id/digest, the ODM source revision, the OATS git hash, host info (kernel, total RAM, GPU model), the `run` argument line, and an entry per test with the ODM exit status, whether the test passed, wall time (seconds) and output size.
- `<tag>/<dataset>/<test>/`: the ODM output for each test, including a `task_output.txt` file with the console output of the OpenDroneMap run. Most errors can be traced with this file.
- `reports/<dataset>_<tag>.xml`: a [JUnit XML](https://github.com/testmoapp/junitxml) report per dataset for CI.
- `oats_manifest.tsv`: the per-test records in tab-separated form.

If you want to aggregate all files into a single directory for ease of view, you can use `harvest`:

```bash
./harvest all odm_orthophoto.tif /my/path
```

This command will copy all odm_orthophoto.tif files from all test cases into `/my/path`. See `./harvest --help` for more options.

## Roadmap

We have great plans for OATS. Some of them include:

- [ ] Graphic interfaces to compare datasets and versions results
- [ ] Ability to leverage the cloud to process tasks
- [ ] Ability to process tasks in parallel
- [X] Test groups for defining subset of tasks (small memory footprint, large memory footprint, insane memory footprint, trees, farmland, etc.)
- [ ] Your own ideas, [let us know](https://github.com/OpenDroneMap/oats/issues)!

## Windows (WSL2)

Run OATS from inside a WSL2 distribution, and keep the checkout and the `datasets/` and `results/` directories on the distribution's own filesystem:

```bash
cd ~
git clone https://github.com/OpenDroneMap/oats --depth 1
cd oats
./run --help
```

Enable Docker Desktop's WSL2 integration for that distribution first (Settings -> Resources -> WSL Integration).

Paths under `/mnt/c` live on the Windows filesystem and are reached over a translation layer. Bind mounts there are slow and only loosely consistent, which OpenDroneMap's heavy I/O reliably provokes: a stage reads a file the previous stage has not finished making visible, and the run ends with missing or corrupted results. Working inside the distribution avoids the boundary entirely, since Docker bind mounts the distribution's filesystem natively.
