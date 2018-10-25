#!/bin/bash

# Parse args
POSITIONAL=()
while [[ $# -gt 0 ]]
do
key="$1"

export TAGS="latest"
case $key in
    --tags)
    export TAGS="$2"
    shift # past argument
    shift # past value
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
  exit
}

# $1 = command | $2 = help_text | $3 = install_command (optional)
check_command(){
	hash $1 2>/dev/null || not_found=true 
	if [[ $not_found ]]; then
		# Can we attempt to install it?
		if [[ ! -z "$3" ]]; then
			echo -e "$check_msg_prefix \033[93mnot found, we'll attempt to install\033[39m"
			run "$3 || sudo $3"

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
	check_command "wget" "Run \033[1msudo apt install -y wget\033[0m" "sudo apt install -y wget"
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

if [ "$POSITIONAL" == "all" ]; then
	for dataset in tests/*.bats; do
		[ -e "$dataset" ] || continue
		$BATS $dataset
	done
elif [ ! -z "$POSITIONAL" ]; then
	# Split string using ',' separator
	IFS=',' read -ra DST <<< "$POSITIONAL"
	for dataset in "${DST[@]}"; do
		if [ -e tests/$dataset.bats ]; then
			$BATS tests/brighton.bats
		else
			echo "WARNING: tests/$dataset.bats does not exist. Ignoring." 
		fi
	done
else
	usage
fi

