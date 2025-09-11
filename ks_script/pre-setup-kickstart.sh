#!/bin/bash

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# @                                                                 @
# @                 STRAT CALL VERIABLE FROM FILE                   @
# @                                                                 @
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
VAR_FILE="variable.env"
if [ ! -f "$VAR_FILE" ]; then
    echo "$VAR_FILE not found!"
    exit 1
fi
source "$VAR_FILE"

# Start check for setup environment
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root" >&2
    exit 1
fi  
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# @                                                                 @
# @                 END CALL VERIABLE FROM FILE                     @
# @                                                                 @
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@


# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# @                                                                 @
# @                 STRAT FUNCTION PRE-CHECK                        @
# @                                                                 @
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Function to check if a package is installed
is_package_installed() {
    local package_name="$1"
    if yum list --installed $package_name &> /dev/null; then
        return 0  # Package is installed
    else
        return 1  # Package is not installed
    fi
}

check_install_status() {
    local flag="$1"
    if [ "$flag" -ne 0 ]; then
        echo "Please install the missing package(s) and try again."
    else
        echo "All required packages are installed."
    fi
}

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# @                                                                 @
# @                 END FUNCTION PRE-CHECK                          @
# @                                                                 @
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# Pre-check for required tools
# Packages install check
# repo is available check
# check prerequisite packages
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# @                                                                 @
# @                 STRAT MAIN PROGRAM                              @
# @                                                                 @
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
cat << EOF
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@                                                                                           @
@   Pre-check for required tools and prerequisite packages before kickstart build script    @
@                                                                                           @
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
EOF


echo
echo "Check package: $HTTP_PACKAGE"
HTTP_FLAGS=$(is_package_installed $HTTP_PACKAGE; echo $?)
sed -i "s/^HTTP_FLAGS=.*/HTTP_FLAGS=${HTTP_FLAGS}/" "$VAR_FILE"
check_install_status $HTTP_FLAGS
echo "--------------------------------------------------------------------"
echo

echo "Check package: $TFTP_PACKAGE"
TFTP_FLAGS=$(is_package_installed $TFTP_PACKAGE; echo $?)
sed -i "s/^TFTP_FLAGS=.*/TFTP_FLAGS=${TFTP_FLAGS}/" "$VAR_FILE"
check_install_status $TFTP_FLAGS
echo "--------------------------------------------------------------------"
echo

echo "Check package: $DHCP_PACKAGE"
DHCP_FLAGS=$(is_package_installed $DHCP_PACKAGE; echo $?)
sed -i "s/^DHCP_FLAGS=.*/DHCP_FLAGS=${DHCP_FLAGS}/" "$VAR_FILE"
check_install_status $DHCP_FLAGS
echo "--------------------------------------------------------------------"
echo

# write log file
LOG_FILE="pre-check-install.log"
cat << EOF > "$LOG_FILE"
prerequisite packages before kickstart build script
Check package result:
    Service: $HTTP_PACKAGE 
    Install status: $(if [ $HTTP_FLAGS -eq 0 ]; then echo "installed"; else echo "not installed"; fi)
    Service: $TFTP_PACKAGE 
    Install status: $(if [ $TFTP_FLAGS -eq 0 ]; then echo "installed"; else echo "not installed"; fi)
    Service: $DHCP_PACKAGE 
    Install status: $(if [ $DHCP_FLAGS -eq 0 ]; then echo "installed"; else echo "not installed"; fi)

Repository result:
EOF

#clean status repo
yum clean all &> /dev/null
if [[ $(yum repolist -v 2> /dev/null |grep -E "^Repo-id" |wc -l) -gt 0 ]]; then
    ENABLE_REPO=$(yum repolist -v 2> /dev/null|grep -E "^Repo-id" |wc -l)
    echo "There are $ENABLE_REPO repo(s) available." | tee -a "$LOG_FILE"
    sed -i "s/^ENABLE_REPO=.*/ENABLE_REPO=${ENABLE_REPO}/" ${VAR_FILE}
    echo  | tee -a "$LOG_FILE"
    echo "########################################################################" | tee -a "$LOG_FILE"
    yum repolist -v 2> /dev/null|awk -F"=" '/^cachedir:/{flag=1; next} flag' | tee -a "$LOG_FILE"
    echo "########################################################################" | tee -a "$LOG_FILE"
    echo | tee -a "$LOG_FILE"
else
    echo "There are 0 repo(s) available." | tee -a "$LOG_FILE"
    sed -i 's/^ENABLE_REPO=.*/ENABLE_REPO=0/' ${VAR_FILE}
    echo | tee -a "$LOG_FILE"
    echo "repo is not available."
fi

OS_NAME=$(awk -F= '/^ID=/{gsub(/"/,"",$2); print $2}' /etc/os-release)
OS_VERSION=$(awk -F= '/^VERSION_ID/{gsub(/"/,"",$2); print $2}' /etc/os-release)
OS_MAIN_VERSION=$(echo $OS_VERSION |cut -d. -f1)
echo "--------------------------------------------------------------------"
echo "Detected OS information:"  | tee -a "$LOG_FILE"
grep -E "^ID=|^VERSION_ID|^NAME" /etc/os-release | tee -a "$LOG_FILE"
echo "--------------------------------------------------------------------"
OS_SHORT_HOST=$OS_NAME
OS_VERSION_HOST=$OS_VERSION
MAIN_VERSION_HOST=$OS_MAIN_VERSION
# Update variable.conf file
sed -i "s/^OS_SHORT_HOST=.*/OS_SHORT_HOST=\"${OS_NAME}\"/" "$VAR_FILE"
sed -i "s/^OS_VERSION_HOST=.*/OS_VERSION_HOST=\"${OS_VERSION}\"/" "$VAR_FILE" 
sed -i "s/^MAIN_VERSION_HOST=.*/MAIN_VERSION_HOST=\"${OS_MAIN_VERSION}\"/" "$VAR_FILE"

echo  >> "$LOG_FILE"
echo "time: $(date)" | tee -a "$LOG_FILE"
echo "Pre-check script finished. Please check the log file $LOG_FILE for more information."
echo "--------------------------------------------------------------------"
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# @                                                                 @
# @                 STRAT MAIN PROGRAM                              @
# @                                                                 @
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@