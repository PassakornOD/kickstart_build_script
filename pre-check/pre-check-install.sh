#!/bin/bash

HTTP_PACKAGE="httpd"
HTTP_FLAGS=""
TFTP_PACKAGE="tftp-server"
TFTP_FLAGS=""
DHCP_PACKAGE="dhcp-server"
DHCP_FLAGS=""

# Function to check if a package is installed
is_package_installed() {
    local package_name="$1"
    if yum list --installed $package_name &> /dev/null; then
        return 0  # Package is installed
    else
        return 1  # Package is not installed
    fi
}


HTTP_FLAGS=$(is_package_installed $HTTP_PACKAGE; echo $?)
TFTP_FLAGS=$(is_package_installed $TFTP_PACKAGE; echo $?)
DHCP_FLAGS=$(is_package_installed $DHCP_PACKAGE; echo $?)
echo "HTTP_FLAGS: $HTTP_FLAGS"
echo "TFTP_FLAGS: $TFTP_FLAGS"
echo "DHCP_FLAGS: $DHCP_FLAGS"

# if [ $HTTP_FLAGS -ne 0 || $TFTP_FLAGS -ne 0 || $DHCP_FLAGS -ne 0 ]; then


if $(yum repolist -v |grep -E "^Repo-id" |wc -l &> /dev/null) > 0; then
    echo "repo is available."
    echo "########################################################################"
    yum repolist -v |awk -F"=" '/^cachedir:/{flag=1; next} flag'
    echo "########################################################################"
else
    echo "repo is not available."
    echo "Please configure the repository first."
    exit 1
fi

OS_NAME=$(awk -F= '/^ID=/{gsub(/"/,"",$2); print $2}' /etc/os-release)
OS_VERSION=$(awk -F= '/^VERSION_ID/{gsub(/"/,"",$2); print $2}' /etc/os-release)
echo "OS_NAME: $OS_NAME"
echo "OS_VERSION: $OS_VERSION"

