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
./run.sh --help
```

Upon startup `run.sh` will attempt to download and install any missing dependency, including [bats](https://github.com/sstephenson/bats), `wget`, `rsync`, `sed` and `unzip` if they are missing.

To test the `latest` tag release of OpenDroneMap on all defined datasets, simply run:

```bash
./run.sh all
```

This command will download the datasets, run the `opendronemap/opendronemap:latest` docker image against each dataset and check that the processing succeeded.

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
./run.sh my_dataset
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

Don't forget to open a [pull request](compare) to share your dataset with the community when you are ready! :pray: :+1:

## Test Multiple Versions of OpenDroneMap

You can test multiple OpenDroneMap versions against one or more datasets. First build docker images for each OpenDroneMap version you want to test.

```bash
docker build -t opendronemap/opendronemap:myversion
```

Then pass the `--tags` parameter to `run.sh`:

```bash
./run.sh all --tags latest,myversion
```

## Rerunning Tests

By default OATS chooses the least destructive approach possible. Previous test results are never cleared between runs unless explicitely instructed by the user.

```bash
./run.sh all --clear
```

## Examine Test Results

All results are placed in `results/`. Each dataset directory will contain a `task_output.txt` file with the console output result. Most errors can be traced with this file.

The output of `run.sh` follows the [TAP Protocol](http://testanything.org/) so you can parse it with one of the many [TAP Consumers](http://testanything.org/consumers.html) available.

## Roadmap

We have great plans for OATS. Some of them include:

- [ ] Graphic interfaces to compare datasets and versions results
- [ ] Ability to leverage the cloud to process tasks
- [ ] Ability to process tasks in parallel
- [ ] Test groups for defining subset of tasks (small memory footprint, large memory footprint, insane memory footprint, trees, farmland, etc.)
- [ ] Your own ideas, [let us know](issues)!


