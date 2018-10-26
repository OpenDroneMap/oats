load functions

DATASET_URL=https://github.com/pierotofy/drone_dataset_brighton_beach/archive/master.zip

@test "default with dsm" {
  $run_test "--dsm"
  [ -e "$output_dir/odm_dem/dsm.tif" ]
  [ -e "$output_dir/odm_orthophoto/odm_orthophoto.tif" ]
}

@test "fast orthophoto" {
  $run_test "--fast-orthophoto"
  [ -e "$output_dir/odm_orthophoto/odm_orthophoto.tif" ]
}
