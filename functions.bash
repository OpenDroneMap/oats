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

	# Sync dataset images to test directory
	# Publish output directory (for people to check files, do extra test logic)
	export output_dir="$OATS_RUN_DIR/tests/$dataset/$BATS_TEST_NAME/"
	mkdir -p $output_dir

	if [ "$TESTRUN" == "NO" ]; then
		check_download_dataset $dataset
		rsync -a --delete datasets/$dataset/* $output_dir
	fi

	DOCKER_CMD="docker run -i --rm \
			-v $(pwd)/$output_dir:/datasets/code \
			$DOCKER_IMAGE:$tag \
			--project-path /datasets \
			$options \
			$CMD_OPTIONS"

	wall_time_s=0
	result_dir_bytes=0

	if [ "$TESTRUN" == "YES" ]; then
		log "About to run: $DOCKER_CMD"
		run echo "$output_dir output"
	else
		log "About to run: $DOCKER_CMD"

		local start
		start=$SECONDS
		run eval $DOCKER_CMD
		wall_time_s=$((SECONDS - start))

		sleep 1

		# Assign permissions to local user
		docker run -i --rm \
			-v $(pwd)/$output_dir:/dataset \
			--entrypoint /bin/chown \
			$DOCKER_IMAGE:$tag \
			-R $(id -u):$(id -u) /dataset

		result_dir_bytes=$(du -sb "$output_dir" 2>/dev/null | cut -f1)
	fi

	# Save command output to log
	echo "$output" > $output_dir/task_output.txt

	# The ODM exit code, used to tell an ODM failure from a failed post-run
	# check. The manifest row is written in teardown, which is the only
	# place that knows whether the post-run checks passed.
	odm_status=$status

	# Basic check
	[ "$status" -eq 0 ]
}

teardown(){
	[ -n "${odm_status:-}" ] || return 0

	if [ -n "${OATS_MANIFEST:-}" ]; then
		printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
			"$tag" "$dataset" "$BATS_TEST_DESCRIPTION" "$output_dir" "$odm_status" \
			"${wall_time_s:-0}" "${result_dir_bytes:-0}" \
			"$([ -n "${BATS_TEST_COMPLETED:-}" ] && echo pass || echo fail)" >> "$OATS_MANIFEST"
	fi
}

check_download_dataset(){
	dataset="$1"

	if [ ! -e ./datasets/$dataset/images ] && [ ! -z $DATASET_URL ]; then
		if [ ! -e ./datasets/$dataset ]; then
			mkdir ./datasets/$dataset
		fi

		wget $DATASET_URL -q -O ./datasets/$dataset/download.zip
		cd ./datasets/$dataset/
		unzip -q ./download.zip 2>/dev/null
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
