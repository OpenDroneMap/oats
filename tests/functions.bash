run_test(){
	dataset=$(basename $BATS_TEST_FILENAME .bats)
	options="$2"

	check_download_dataset $dataset

	# Split string using ',' separator
	IFS=',' read -ra DST <<< "$TAGS"
	for tag in "${DST[@]}"; do

		# Sync dataset images to test directory
		IMAGES_DIR="results/$tag/$dataset/$BATS_TEST_NAME/"

		if [ "$CLEAR" == "YES" ]; then
			rm -fr $IMAGES_DIR
		fi

		mkdir -p $IMAGES_DIR
		rsync -a --delete datasets/$dataset/* $IMAGES_DIR

		DOCKER_CMD="docker run -ti --rm \
				-v $(pwd)/$IMAGES_DIR:/datasets/code \
				$DOCKER_IMAGE:$tag \
				--project-path /datasets \
				$options \
				$CMD_OPTIONS"

		if [ "$TESTRUN" == "YES" ]; then
			echo $DOCKER_CMD >> docker.log
			run echo "$IMAGES_DIR output"
		else
			run $DOCKER_CMD
		fi
	done

	# Save command output to log
	echo $output > $IMAGES_DIR/task_output.log
	[ "$status" -eq 0 ]
}

check_download_dataset(){
	dataset="$1"

	if [ ! -e ./datasets/$dataset/images ] && [ ! -z $DATASET_URL ]; then
		mkdir ./datasets/$dataset
		wget $DATASET_URL -q -O ./datasets/$dataset/download.zip
		cd ./datasets/$dataset/
		unzip ./download.zip
		rm ./download.zip
		
		# Remove top level directory if needed
		for dir in $(ls -d */); do 
			if [ "$dir" != "images/" ]; then
				mv "$dir"/* .
				rm -fr "$dir"
			fi
		done

		# Check images path
		if [ ! -e ./images ]; then
			mkdir images
			mv *.* images
		fi
	fi
}
