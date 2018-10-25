load functions

DATASET_URL=https://github.com/pierotofy/drone_dataset_brighton_beach/archive/master.zip

@test "default with dsm" {
  run_test "--dsm"

  # !run_test template substitution via tags
}

@test "fast orthophoto" {
  run_test "--fast-orthophoto"
  echo "$status $output" >> out.log
}
