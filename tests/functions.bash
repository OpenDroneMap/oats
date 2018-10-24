run_test(){
	dataset="$1"
	options="$2"
	tag=${3:-latest}

	check_download_dataset $dataset
	
	#run docker run --rm opendronemap/opendronemap --version
	run echo 1

	# # Save command output to log
	echo $output > $1.log
	[ "$status" -eq 0 ]
}

check_download_dataset(){
	dataset="$1"

	if [ ! -e ./datasets/$dataset/images ] && [ -e ./datasets/$dataset.cfg ]; then
		source ./datasets/$dataset.cfg
		mkdir ./datasets/$dataset
		wget $URL -q -O ./datasets/$dataset/download.zip
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
