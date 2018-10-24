#!/bin/bash

if [ ! -e ./bats ]; then
	./install.sh
fi

# Path to bats executable
BATS=./bats/bin/bats

if [ ! -e "$BATS" ]; then
	echo "Bats not found: $BATS"
	exit 1
fi

# Parse args
POSITIONAL=()
while [[ $# -gt 0 ]]
do
key="$1"

TAGS="latest"
case $key in
    --tags)
    export TAGS="$2"
    shift # past argument
    shift # past value
    ;;    
    # --verbose)
    # export VERBOSE=YES
    # shift # past argument
    # ;;
    *)    # unknown option
    POSITIONAL+=("$1") # save it in an array for later
    shift # past argument
    ;;
esac
done
set -- "${POSITIONAL[@]}" # restore positional parameter

usage(){
  echo "Usage: $0 <command>"
  echo
  echo "OpenDroneMap Automated Testing Suite."
  echo 
  echo "Command list:"
  echo "	start [options]		Start WebODM"
  echo "	stop			Stop WebODM"
  echo "	down			Stop and remove WebODM's docker containers"
  echo "	update			Update WebODM to the latest release"
  echo "	rebuild			Rebuild all docker containers and perform cleanups"
  echo "	checkenv		Do an environment check and install missing components"
  echo "	test			Run the unit test suite (developers only)"
  echo "	resetadminpassword <new password>	Reset the administrator's password to a new one. WebODM must be running when executing this command."
  if [[ $plugins_volume = true ]]; then
    echo ""
    echo "	plugin enable <plugin name>	Enable a plugin"
    echo "	plugin disable <plugin name>	Disable a plugin"
    echo "	plugin list		List all available plugins"
    echo "	plugin cleanup		Cleanup plugins build directories"
  fi
  echo ""
  echo "Options:"
  echo "	--port	<port>	Set the port that WebODM should bind to (default: $DEFAULT_PORT)"
  echo "	--hostname	<hostname>	Set the hostname that WebODM will be accessible from (default: $DEFAULT_HOST)"
  echo "	--media-dir	<path>	Path where processing results will be stored to (default: $DEFAULT_MEDIA_DIR (docker named volume))"
  echo "	--ssl	Enable SSL and automatically request and install a certificate from letsencrypt.org. (default: $DEFAULT_SSL)"
  echo "	--ssl-key	<path>	Manually specify a path to the private key file (.pem) to use with nginx to enable SSL (default: None)"
  echo "	--ssl-cert	<path>	Manually specify a path to the certificate file (.pem) to use with nginx to enable SSL (default: None)"
  echo "	--ssl-insecure-port-redirect	<port>	Insecure port number to redirect from when SSL is enabled (default: $DEFAULT_SSL_INSECURE_PORT_REDIRECT)"
  echo "	--debug	Enable debug for development environments (default: disabled)"
  echo "	--broker	Set the URL used to connect to the celery broker (default: $DEFAULT_BROKER)"
  if [[ $plugins_volume = false ]]; then
    echo "	--mount-plugins-volume	Always mount the ./plugins volume, even on unsupported platforms (developers only) (default: disabled)"
  fi
  exit
}


$BATS tests/brighton.bat
