__dirname=$(cd $(dirname "$0"); pwd -P)
cd "${__dirname}"

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
		exit 1
	fi
}

# https://stackoverflow.com/questions/3685970/check-if-a-bash-array-contains-a-value
contains_element () {
  local e match="$1"
  shift
  for e; do [[ "$e" == "$match" ]] && return 0; done
  return 1
}

get_datasets_for_group(){
	local group="$1"
	local filter_datasets=("${@:2}")
	datasets=()

	source groups/$group.bash
	for dataset in "${DATASETS[@]}"; do
		if [ "$filter_datasets" != "" ]; then
			contains_element "$dataset" "${filter_datasets[@]}"
			if [ "1" == "$?" ]; then
				continue
			fi
		fi

		datasets+=("$dataset")
	done
}
