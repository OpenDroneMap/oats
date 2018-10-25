run_test(){
	dataset=$(basename $BATS_TEST_FILENAME .bats)
	options="$2"

	check_download_dataset $dataset

	# Split string using ',' separator
	IFS=',' read -ra DST <<< "$TAGS"
	for tag in "${DST[@]}"; do
		echo run docker run -ti --rm opendronemap/opendronemap:$tag --version >> out.log
	done

	# Save command output to log
	#echo $output > $1.log
	run echo 1
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
