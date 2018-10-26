#!/bin/bash

# Parse args
export TAGS="latest"
export DOCKER_IMAGE="opendronemap/opendronemap"
export CMD_OPTIONS=""
export CLEAR=NO
export TESTRUN=NO

POSITIONAL=()
while [[ $# -gt 0 ]]
do
key="$1"
case $key in
    --tags)
    export TAGS="$2"
    shift # past argument
    shift # past value
    ;;
	--image_name)
    export DOCKER_IMAGE="$2"
    shift # past argument
    shift # past value
    ;;	
    --options)
    export CMD_OPTIONS="$2"
    shift # past argument
    shift # past value
    ;;
    --clear)
    export CLEAR=YES
    shift # past argument
    ;;
    --test)
    export TESTRUN=YES
    shift # past argument
    ;;
    --help)
    export HELP=YES
    shift # past argument
    ;;
    *)    # unknown option
    POSITIONAL+=("$1") # save it in an array for later
    shift # past argument
    ;;
esac
done
set -- "${POSITIONAL[@]}" # restore positional parameter

usage(){
  echo "Usage: $0 [options] <command>"
  echo
  echo "OpenDroneMap Automated Testing Suite."
  echo
  echo "Commands:"
  echo "	all	Test all datasets"
  echo "	<dataset1,dataset2,...>	Test only the specified datasets"
  echo 
  echo "Options:"
  echo "	--tags	<tag1,tag2,...>	docker tag images to test. Each tag is tested against each dataset. (default: latest)"
  echo "	--options	\"--odm-option 1 --rerun-from odm_meshing ...\"	Options to append to each OpenDroneMap invocation (for example to rerun from a certain step of the pipeline). Make sure to add these in quotes. (default: \"\")"
  echo "	--docker_image	<docker image>	Docker image to use. (default: opendronemap/opendronemap)"
  echo "	--clear	Delete previous test results. (default: no)"
  echo "	--test	Do not execute docker commands, but simply write them in oats.log. (default: no)"
  exit
}

# $1 = command | $2 = help_text | $3 = install_command (optional)
check_command(){
	hash $1 2>/dev/null || not_found=true 
	if [[ $not_found ]]; then
		# Can we attempt to install it?
		if [[ ! -z "$3" ]]; then
			echo -e "$check_msg_prefix \033[93mnot found, we'll attempt to install\033[39m"
			eval "$3 || sudo $3"

			# Recurse, but don't pass the install command
			check_command "$1" "$2"	
		else
			check_msg_result="\033[91m can't find $1! Check that the program is installed and that you have added the proper path to the program to your PATH environment variable before launching WebODM. If you change your PATH environment variable, remember to close and reopen your terminal. $2\033[39m"
		fi
		echo -e "$check_msg_prefix $check_msg_result"
	fi

	if [[ $not_found ]]; then
		return 1
	fi
}

environment_check(){
	check_command "docker" "https://www.docker.com/"
	check_command "wget" "Run \033[1msudo apt install -y wget\033[0m" "sudo apt install -y wget"
	check_command "rsync" "Run \033[1msudo apt install -y rsync\033[0m" "sudo apt install -y rsync"
	check_command "sed" "Run \033[1msudo apt install -y sed\033[0m" "sudo apt install -y sed"
	check_command "unzip" "Run \033[1msudo apt install -y unzip\033[0m" "sudo apt install -y unzip"
}

build_tests(){
	rm -f tests/build/*.bats

	# Create test files for each tag
	# Split string using ',' separator
	IFS=',' read -ra DST <<< "$TAGS"
	for tag in "${DST[@]}"; do
		for test_file in tests/*.bats; do
			[ -e "$test_file" ] || continue
			test_basename=$(basename $test_file .bats)
			out_file="tests/build/$test_basename""_$tag.bats"

			# Replace calls to $run_test with run_test appended by a tag parameter
			sed "s/\$run_test\(.*\)/run_test\1 \"$tag\"/g" $test_file > $out_file

			# Add BATS_TEST_BASENAME to each test case description
			#sed -i.bak "s/@test \"\(.*\)\"/@test \"\1 (\$BATS_BASENAME\)\"/g" $out_file
		done
	done

	#rm tests/build/*.bak
	cp tests/*.bash tests/build/
}

if [ "$HELP" == "YES" ]; then
	usage
fi

environment_check

if [ ! -e ./bats ]; then
	./install.sh
fi

# Path to bats executable
BATS=./bats/bin/bats

if [ ! -e "$BATS" ]; then
	echo "Bats not found: $BATS"
	exit 1
fi

# Clean previous logs
rm -f *.log

build_tests

if [ "$POSITIONAL" == "all" ]; then
	for test_file in tests/build/*.bats; do
		[ -e "$test_file" ] || continue
		$BATS $test_file
	done
elif [ ! -z "$POSITIONAL" ]; then
	# Split string using ',' separator
	IFS=',' read -ra DST <<< "$POSITIONAL"
	for dataset in "${DST[@]}"; do
		if [ -e tests/$dataset.bats ]; then
			# For each tag
			for test_file in $(echo "tests/build/$dataset""_*.bats"); do
				[ -e "$test_file" ] || continue
				$BATS $test_file
			done
		else
			echo "WARNING: tests/$dataset.bats does not exist. Ignoring." 
		fi
	done
else
	usage
fi

