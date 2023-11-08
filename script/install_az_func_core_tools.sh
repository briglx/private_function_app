#!/usr/bin/env bash
#########################################################################
# Install Azure Function Core Tools
#########################################################################
set -e

setup() {

    export DEBIAN_FRONTEND=noninteractive
   
    # Use env var DEBIAN_VERSION for the package dist name if provided
    if [[ -z $DEBIAN_VERSION ]]; then
        DEBIAN_VERSION=$(lsb_release -rs)        
    fi

    set -v
    packages=$(curl -sL https://packages.microsoft.com/config/debian/ | grep -oP '(?<=href=")[^"]+(?=")')
    if [[ ! "$packages" =~ $DEBIAN_VERSION ]]; then
        echo "Unable to find a function core tools package with DEBIAN_VERSION=$DEBIAN_VERSION in https://packages.microsoft.com/config/debian/."
        exit 1
    fi
    # Download prod.list
    curl -sLS https://packages.microsoft.com/config/debian/$DEBIAN_VERSION/prod.list | tee /etc/apt/sources.list.d/microsoft-prod.list > /dev/null
    apt-get update
    set +v

    apt-get install -y azure-functions-core-tools-4

}

setup
