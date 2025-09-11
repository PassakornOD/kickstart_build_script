#!/bin/bash

clear
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# @                                                                   @
# @                     INCLUDE SCRIPT FOR PRE-CHECK                  @
# @                                                                   @
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
PRESETUP_FILE="./pre-setup-uefi-boot.sh"
if [ ! -f "$PRESETUP_FILE" ]; then
    echo "$PRESETUP_FILE not found!"
    exit 1
fi

source $PRESETUP_FILE
sleep 5
clear
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# @                                                                   @
# @                         INCLUDE VARIABLE FILE                     @
# @                                                                   @
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Define the path to your configuration file
VAR_FILE="./variable.env"

call_env() {
    local file_path="$1"
    if [ -f "$file_path" ]; then
    # Use 'source' to load the variables
    source "$file_path"
    echo "@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@"
    echo "${file_path} Configuration loaded successfully."
    echo "@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@"
    echo
    awk -F'=' '/^#Variables/{flag=1; next} flag' "$file_path" |grep -E '^[[:space:]]*[a-zA-Z_][a-zA-Z0-9_]*=' | awk -F'=' '{print $1}' | while read var_name; do
        # Use 'declare -p' to get the variable's value and type, handling cases with spaces correctly.
        eval "var_value=\$$var_name"
        printf "    %s => %s\n" "$var_name" "$var_value"

    done
    echo
    echo "###########################################################################################"
    echo
    else
        echo "Error: File '$file_path' does not exist."
        exit 1
    fi
}

call_env "$VAR_FILE"

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# @                                                                   @
# @                         INCLUDE FUNCTION FILE                     @
# @                                                                   @
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
FUNC_SCRIPT="./ks_function.sh"
if [ ! -f ${FUNC_SCRIPT} ]; then
    echo "$FUNC_SCRIPT not found!"
    exit 1
fi

source $FUNC_SCRIPT


# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# @                                                                   @
# @                             MAIN LOGIC                            @
# @                                                                   @
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@


cat << EOF
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@                                                                   @
@            Install package for UEFI boot(Kickstart)               @
@                                                                   @
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
EOF

if [[ ${HTTP_FLAGS} -ne 0 || ${DHCP_FLAGS} -ne 0 || ${TFTP_FLAGS} -ne 0 ]]; then

    # prompt for choose existing repo and mount iso
    echo "Choose repository setup method:"
    echo "1. Use existing repository"
    echo "2. Mount ISO and create new repository"
    read -p "Enter your choice (1 or 2): " REPO_CHOICE

    case "$REPO_CHOICE" in
        1)
            read -p "Enter your repository path: " EXIST_PATH
            if [ -z "$(ls -A ${EXIST_PATH})" ]; then
                echo "Please check your repository path. directory are empty"
                exit 1 
            fi
            MOUNTPOINT_ISO_HOST=${EXIST_PATH}
            repo_id=$(yum repolist -v 2> /dev/null|grep -E "Repo-baseurl" |grep -E "${MOUNTPOINT_ISO_HOST}/" |wc -l)
            if [[ ${ENABLE_REPO} -ge 2 && ${repo_id} -ge 2 ]]; then
                echo "Create local repo"
                CreateLocalRepo "${REPO_CONF_PATH}" "${DIR_HOST_VERSION}" "${MOUNTPOINT_ISO_HOST}"
            fi
            ;;
        2)
            read -p "mount optical drive is ${CDROM}: " OPICAL_DRIVE
            read -p  "mount point for mount ${CDROM} is ${MOUNTPOINT_ISO_HOST}: " INPUT_MOUNT
            if [ ! -z ${OPICAL_DRIVE} ]; then
                CDROM=${OPICAL_DRIVE}
                echo $CDROM
            fi
            if [ ! -z ${INPUT_MOUNT} ]; then
                MOUNTPOINT_ISO_HOST=${INPUT_MOUNT}
                echo $MOUNTPOINT_ISO_HOST
            fi
            # Create mount point directory for ISO
            echo "Attempting to create a new directory..."
            create_directory ${MOUNTPOINT_ISO_HOST}
            echo "Exit code: $?"
            echo "-------------------"

            # The mount command requires root privileges.
            # The 'loop' option is essential for mounting an ISO file.
            mount_iso "${ISO_FILE_HOST}" "${MOUNTPOINT_ISO_HOST}"
            CreateLocalRepo "${REPO_CONF_PATH}" "${DIR_HOST_VERSION}" "${MOUNTPOINT_ISO_HOST}"
            ;;
        *)
            echo "Invalid choice. Please enter 1 or 2."
            exit 1
            ;;
    esac


    # Call function to install packages
    InstallPackages "$HTTP_PACKAGE"
    InstallPackages "$TFTP_PACKAGE"
    InstallPackages "$DHCP_PACKAGE"

else

cat << EOF
Result:

${HTTP_PACKAGE} Package are installed
Skip install......

${TFTP_PACKAGE} Package are installed
Skip install......

${DHCP_PACKAGE} Package are installed
Skip install......

EOF
fi

cat << EOF
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@                                                                   @
@       Configure dhcp UEFI boot for httpclient and pxeboot         @
@                                                                   @
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
EOF
# Call configure DHCP server
DhcpServer "$DHCP_CONF_FILE" "$SUBNET" "$NETMASK" "$GATEWAY" "$SERVER_IP" "$START_RANGE" "$END_RANGE" "$DIR_ISO_ROOT"


cat << EOF
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@                                                                   @
@               Copy media for ISO to http repository               @
@                                                                   @
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
EOF
# Call the prompt function for create repository
read -p "Please enter ISO file for kickstart repo(Default: ${ISO_PATH}): " INPUT_ISO_PATH
read -p "Please enter mount point name for kickstart repo(Default: ${MOUNTPOINT_ISO_KS})" INPUT_MOUNT_KS
echo

if [ ! -z ${INPUT_ISO_PATH} ]; then
    ISO_PATH=${INPUT_ISO_PATH}
fi
if [ ! -z ${INPUT_MOUNT_KS} ]; then
    MOUNTPOINT_ISO_KS=${INPUT_MOUNT_KS}
fi
if mount |grep ${ISO_PATH} &> /dev/null; then
    MOUNTPOINT_ISO_KS=$(mount |grep "${ISO_PATH}" | awk '{print $3}')
    create_directory "${MOUNTPOINT_HTTP_ROOT}"
    CopyISOFiles "${MOUNTPOINT_ISO_KS}" "${MOUNTPOINT_HTTP_ROOT}"
else
    create_directory ${MOUNTPOINT_ISO_KS}
    create_directory "${MOUNTPOINT_HTTP_ROOT}"
    mount_iso "${ISO_PATH}" "${MOUNTPOINT_ISO_KS}"
    CopyISOFiles "${MOUNTPOINT_ISO_KS}" "${MOUNTPOINT_HTTP_ROOT}"
fi

# Configure permission for HTTP Repo
echo "Configuring permission for HTTP Repo..."
chown -R apache:apache ${MOUNTPOINT_HTTP_ROOT}
# chmod -R 755 ${MOUNTPOINT_HTTP_ROOT}
semanage fcontext -a -t httpd_sys_content_t "${MOUNTPOINT_HTTP_ROOT}(/.*)?"
restorecon -Rv ${MOUNTPOINT_HTTP_ROOT}
echo "Permission configured."
echo "--------------------------------"

# Create symbolic link for HTTP Repo
echo "Creating symbolic link for HTTP Repo..."
current_path=$(pwd)
cd $HTTP_DEFAULT_ROOT
if [ -L ${DIR_KS_VERSION} ]; then
    echo "Symbolic link ${DIR_KS_VERSION} already exists. Removing it first."
    rm -f ${DIR_KS_VERSION}
fi
ln -s ${MOUNTPOINT_HTTP_ROOT} ${DIR_KS_VERSION}
echo "Symbolic link created."
echo "--------------------------------" 
cd $current_path


# Create kickstart file
#syntax command
# 
# CreateKickstartFile <repository_path> <ks_name_file> <ip_server> <repository_name_directory>
CreateKickstartFile "${HTTP_DEFAULT_ROOT}/${DIR_KS_VERSION}" "${DIR_KS_VERSION}_ks.cfg" ${SERVER_IP} ${DIR_KS_VERSION}

cat << EOF
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@                                                                   @
@                   Select method for UEFI boot                     @
@                                                                   @
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
EOF
echo "Please choose your boot configuration method:"
echo "1. TFTP"
echo "2. HTTP"
echo -n "Enter your choice (1 or 2): "

read -r choice

case $choice in
    1)
        cat << EOF
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@                                                                   @
@                   Configure PXEboot with tftp                     @
@                                                                   @
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
EOF
        ConfigureTftp ${DIR_ISO_ROOT} ${MOUNTPOINT_ISO_KS}
        GetVersion "${MOUNTPOINT_ISO_KS}/.treeinfo"
        cat << EOF
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@                                                                   @
@                   Create grub.cfg for pxeboot                     @
@                                                                   @
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
EOF
        CreateGrubCfg "/var/lib/tftpboot/${DIR_ISO_ROOT}/EFI/BOOT" "grub.cfg" "${RHEL_SHORT}" "${RHEL_VERSION}" "${SERVER_IP}" "${DIR_KS_VERSION}" "${DIR_ISO_ROOT}" "images"
        # show configure grub.cfg
        chmod 644 /var/lib/tftpboot/${DIR_ISO_ROOT}/EFI/BOOT/grub.cfg
        cat "/var/lib/tftpboot/${DIR_ISO_ROOT}/EFI/BOOT/grub.cfg"
        ;;

    2)
        cat << EOF
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@                                                                   @
@                       Configure http boot.                        @
@                                                                   @
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
EOF
        ConfigureHttpBoot ${DIR_ISO_ROOT} ${MOUNTPOINT_ISO_KS}
        GetVersion "${MOUNTPOINT_ISO_KS}/.treeinfo"
        cat << EOF
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@                                                                   @
@                   Create grub.cfg for http boot                   @
@                                                                   @
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
EOF
        CreateGrubCfg "${HTTP_DEFAULT_ROOT}/${DIR_ISO_ROOT}/EFI/BOOT" "grub.cfg" "${RHEL_SHORT}" "${RHEL_VERSION}" "${SERVER_IP}" "${DIR_KS_VERSION}" "${DIR_ISO_ROOT}" "../../images"
        # show configure grub.cfg
        chmod 644 ${HTTP_DEFAULT_ROOT}/${DIR_ISO_ROOT}/EFI/BOOT/grub.cfg
        cat "${HTTP_DEFAULT_ROOT}/${DIR_ISO_ROOT}/EFI/BOOT/grub.cfg"
        ;;

    *)
        echo "Invalid choice. Please enter 1 or 2."
        exit 1
        ;;
esac

cat << EOF
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@                                                                   @
@                Allow firewall for http, tftp and dhcp             @
@                                                                   @
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
EOF
# Allow firewall for http, tftp and dhcp service
for service in "http" "tftp" "dhcp"; do
    EnableServiceOnFW "$service"
done
echo "Firewall reloading..."
firewall-cmd --reload
echo

cat << EOF
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@                                                                   @
@          enable and start service for http, tftp and dhcp         @
@                                                                   @
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
EOF
# Enable and start httpd, tftp and dhcpd
for service in "httpd" "tftp.socket" "dhcpd"; do
    StartService "${service}"
done

echo "Script finished."
