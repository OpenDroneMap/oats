BATS_BASENAME=$(basename $BATS_TEST_FILENAME .bats)

run_test(){
	options="$1"
	tag="$2"

	# Remove tag from dataset name
	dataset=$(sed "s/_$tag\$//" <<< $BATS_BASENAME)

	# Param check...
	if [ -z $tag ]; then
		log 'run_test called without tag parameter. Did you forget to add $ in front of $run_test?' 'error'
		return 1
	fi

	check_download_dataset $dataset

	# Sync dataset images to test directory
	IMAGES_DIR="results/$tag/$dataset/$BATS_TEST_NAME/"

	if [ "$CLEAR" == "YES" ]; then
		rm -fr $IMAGES_DIR
	fi

	mkdir -p $IMAGES_DIR
	rsync -a --delete datasets/$dataset/* $IMAGES_DIR

	DOCKER_CMD="docker run -i --rm \
			-v $(pwd)/$IMAGES_DIR:/datasets/code \
			$DOCKER_IMAGE:$tag \
			--project-path /datasets \
			$options \
			$CMD_OPTIONS"

	# Docker for Windows bind volumes do not keep up when lots of I/O
	# is being performed. By copying all files to a local directory
	# and then copying the files back to the volume we avoid problems of missing
	# files, corrupted files and all hell unleashing loose
	if [ "$USE_LOCAL_VOLUME" == "YES" ]; then
		DOCKER_CMD="docker run -i --rm \
			-v $(pwd)/$IMAGES_DIR:/staging \
			--entrypoint bash \
			$DOCKER_IMAGE:$tag \
			-c \"mkdir -p /datasets/code && cp -R /staging/* /datasets/code && ./run.sh --project-path /datasets $options $CMD_OPTIONS code; cp -R /datasets/code/* /staging\" "
	fi

	if [ "$TESTRUN" == "YES" ]; then
		log "About to run: $DOCKER_CMD"
		run echo "$IMAGES_DIR output"
	else
		log "About to run: $DOCKER_CMD"
		run eval $DOCKER_CMD

		# Assign permissions to local user
		docker run -i --rm \
			-v $(pwd)/$IMAGES_DIR:/dataset \
			--entrypoint /bin/chown \
			$DOCKER_IMAGE:$tag \
			-R $(id -u):$(id -u) /dataset
	fi

	# Save command output to log
	echo $lines > $IMAGES_DIR/task_output.log

	# Publish output directory (for people to check files, do extra test logic)
	export output_dir=$IMAGES_DIR
	
	# Basic check
	[ "$status" -eq 0 ]
}

check_download_dataset(){
	dataset="$1"

	if [ ! -e ./datasets/$dataset/images ] && [ ! -z $DATASET_URL ]; then
		if [ ! -e ./datasets/$dataset ]; then
			mkdir ./datasets/$dataset
		fi 

		wget $DATASET_URL -q -O ./datasets/$dataset/download.zip
		cd ./datasets/$dataset/
		unzip ./download.zip 2>/dev/null
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

		cd ../../
	fi
}

log(){
	message="$1"
	type="${2:-info}"
	echo "$type: $message" >> oats.log
}
