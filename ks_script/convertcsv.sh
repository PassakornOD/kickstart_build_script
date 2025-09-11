#!/bin/bash

read -p "Enter your csv path: " path_csv
CSV_FILE="./my_var.csv"

if [ ! -z ${path_csv} ]; then
    CSV_FILE=${path_csv}
fi

echo $CSV_FILE
tail -n +2 ${CSV_FILE}
cleaned_line=$(tail -n +2 ${CSV_FILE})
echo $clened_line

echo ${cleaned_line} |while IFS=',' read -r os os_version ks_iso_file subnet netmask ip_server gw s_range e_range
do
    # Assign variables from read
    OS="$os"
    OS_VER="$os_version"
    KS_ISO_FILE="$ks_iso_file"
    SUBNET="$subnet"
    NETMASK="$netmask"
    IP_SERVER="$ip_server"
    GW="$gw"
    S_RANGE="$s_range"
    E_RANGE="$e_range"
    CORE_VER=$(echo ${OS_VER}|awk -F"." '{print $1}')


cat << EOF > "./temp.env"
#variable for kickstart_build_script
# Define variables for network boot configuration
# Configurable parameters
# Kickstart parameters
CDROM="/dev/sr0"
OS_VERSION_KS="${OS_VER}"
MAIN_VERSION_KS="${CORE_VER}"
OS_SHORT_KS="${OS}"
ISO_FILE_KS="${KS_ISO_FILE}"
DIR_IOS_KS="/root"
# Host parameters
OS_VERSION_HOST=""
MAIN_VERSION_HOST=""
OS_SHORT_HOST=""
ISO_FILE_HOST=${CDROM}
HTTP_DIR="repos"
ARCH="x86_64"
REPO_CONF_PATH="/etc/yum.repos.d"
DHCP_CONF_FILE="/etc/dhcp/dhcpd.conf"
HTTP_DEFAULT_ROOT="/var/www/html"

#Variables
HTTP_FLAGS=""
TFTP_FLAGS=""
DHCP_FLAGS=""
ENABLE_REPO=0
HTTP_PACKAGE="httpd"
TFTP_PACKAGE="tftp-server"
DHCP_PACKAGE="dhcp-server"
SUBNET=${SUBNET}
NETMASK=${NETMASK}
GATEWAY=${GW}
SERVER_IP=${IP_SERVER}
START_RANGE=${S_RANGE}
END_RANGE=${E_RANGE}
ISO_PATH="${DIR_IOS_KS}/${ISO_FILE_KS}"
DIR_HOST_VERSION="${OS_SHORT_HOST}${OS_VERSION_HOST}"
DIR_KS_VERSION="${OS_SHORT_KS}${OS_VERSION_KS}"
DIR_ISO_ROOT="${OS_SHORT_KS}${MAIN_VERSION_KS}"
# Path
MOUNTPOINT_ISO_HOST="/${DIR_ISO_ROOT}/${DIR_HOST_VERSION}"
MOUNTPOINT_ISO_KS="/${DIR_ISO_ROOT}/${DIR_KS_VERSION}"
MOUNTPOINT_HTTP_ROOT="/${HTTP_DIR}/${DIR_ISO_ROOT}/${DIR_KS_VERSION}"

EOF
done 


