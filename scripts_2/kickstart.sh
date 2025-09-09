#!/bin/bash

clear
PRESETUP_FILE="./pre-setup-uefi-boot.sh"
if [ ! -f "$PRESETUP_FILE" ]; then
    echo "$PRESETUP_FILE not found!"
    exit 1
fi

source $PRESETUP_FILE
sleep 5


clear
# Define the path to your configuration file
VAR_FILE="./variable.conf"

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

InstallPackages() {
    local packages="$1"
    echo "--- Checking for httpd package installation ---"
    # Check if the httpd package is installed using dnf
    # yum is the default package manager for RHEL 8
    if yum list --installed $packages &> /dev/null; then
        echo "----------------------------------------------------------------------------"
        echo "$packages package is already installed."
        echo "----------------------------------------------------------------------------"
        yum list installed $packages
        echo "----------------------------------------------------------------------------"
    else
        echo "Attempting to install: $packages"
        if yum install -y $packages; then
            echo "Successfully installed packages."
            return 0
        else
            echo "Failed to install packages. Please check your internet connection and repository configuration."
            return 1
    fi
    fi
}

# Function to safely create a directory
# Arguments:
#   $1 - The full path to the directory to create.
# Returns:
#   0 - Directory created or already exists.
#   1 - An error occurred (e.g., permissions).
create_directory() {
  local dir_path="$1"

  # Check if the path is empty
  if [ -z "$dir_path" ]; then
    echo "Error: No directory path provided."
    return 1
  fi

  # Use mkdir with the -p flag to create the directory
  # The -p flag prevents an error if the directory already exists
  # and creates any necessary parent directories.
  mkdir -p "$dir_path"

  # Check the exit status of the mkdir command
  if [ $? -eq 0 ]; then
    echo "Directory '$dir_path' created or already exists."
    return 0
  else
    echo "Error: Failed to create directory '$dir_path'."
    return 1
  fi
}


# Function to mount an ISO file to a specified directory
# Arguments:
#   $1 - Path to the ISO file.
#   $2 - Path to the mount point directory.
# Returns:
#   0 on success, non-zero on failure.
mount_iso() {
    local iso_path="$1"
    local mount_point="$2"
    if findmnt --target "$mount_point" --types iso9660 >/dev/null; then
        echo "ISO is already mounted at $mount_point."
        if [ ! -f "$mount_point/.treeinfo" ]; then
            echo "Error: The mount point $mount_point does not contain a valid ISO structure."
            exit 1
        else
            echo "The mount point $mount_point contains a valid ISO structure."
            RHEL_VERSION=$(awk -F'=' '/^\[release\]/{flag=1; next} flag && /^version =/{print $2; exit}' "$mount_point/.treeinfo")
            if [ -z "$RHEL_VERSION" ]; then
                echo "Error: RHEL version could not be found in $mount_point/.treeinfo"
                exit 1
            fi
            TIMEOUT=20 # seconds
            echo "The ISO appears to be for RHEL version $RHEL_VERSION."
            echo "Please confirm if this is the version you expect. It will execute automatically in $TIMEOUT seconds if you don't respond."
            echo "Press 'y' to confirm or 'n' to cancel."

            read -t $TIMEOUT -p "Proceed? (y/n): " -n 1 -r

            echo

            if [[ $REPLY =~ ^[Yy]$ ]]; then
                echo "Confirmed. Proceeding with the operation."
            elif [[ $REPLY =~ ^[Nn]$ ]]; then
                echo "Operation cancelled."
                exit 1
            else
                # If read times out or user presses a different key
                echo "Timeout reached or invalid input. Operation cancelled."
                exit 1
            fi
            
        fi
    else
        # If not mounted, attempt to mount it
        echo "ISO is not mounted. Attempting to mount..."
        mount -o loop "$iso_path" "$mount_point"
        
        # Check if the mount was successful
        if [ $? -eq 0 ]; then
            echo "Successfully mounted $iso_path to $mount_point"
        else
            echo "Mount failed. Please check your permissions and paths."
            exit 1
        fi
    fi
}

# Function to create a local repository configuration file
CreateLocalRepo() {
    local repo_path="$1"
    local repo_version="$2"
    local repo_mount="$3"
    # Check if the repository file already exists
    if [ -f "$repo_path/$repo_version.repo" ]; then
        echo "Warning: Repository file $repo_version.repo already exists."
        echo "Backing up the existing file with a timestamp."
        TIME_FORMAT="%Y%m%d%H%M%S"

        # --- MAIN SCRIPT ---
        # Get the current date and time in the specified format.
        TIMESTAMP=$(date +"$TIME_FORMAT")

        # Create the full file name.
        cp "${repo_path}/${repo_version}.repo" "${repo_path}/${repo_version}.repo_${TIMESTAMP}"
    fi

    # Create the repository file 
    echo "Creating repository file: $repo_path/$repo_version.repo"
    cat << EOF | tee "$repo_path/$repo_version.repo" > /dev/null
[BaseOS]
name=${repo_version}-BaseOS
baseurl=file:///${repo_mount}/${repo_version}/BaseOS
enabled=1
gpgcheck=0
[AppStream]
name=${repo_version}-AppStream
baseurl=file:///${repo_mount}/${repo_version}/AppStream
enabled=1
gpgcheck=0
EOF

    echo "--------------------------------"
    echo "Repository file created at $repo_path/$repo_version.repo"
    cat "$repo_path/$repo_version.repo"
    echo "--------------------------------"

    # Verify the file was created
    if [ $? -eq 0 ]; then
        echo "Repository configuration created successfully."
        echo "Cleaning yum cache..."
        yum clean all
        echo "--------------------------------"
        echo "Refreshing yum repository list..."
        yum repolist
        echo "Script finished."
    else
        echo "Failed to create the repository file. Check permissions."
        exit 1
    fi
    echo "--------------------------------"
}

# Function Configure DHCP Server
DhcpServer() {
    local dhcp_conf_file="$1"
    local subnet="$2"
    local netmask="$3"
    local gateway="$4"
    local server_ip="$5"
    local start_range="$6"
    local end_range="$7"
    local os_base="$8"


    echo "Configuring DHCP server..."
    cat << EOF |tee ${dhcp_conf_file} > /dev/null
# DHCP Server Configuration file.
option architecture-type code 93 = unsigned integer 16;

subnet ${subnet} netmask ${netmask} {
  option routers ${gateway};
  option domain-name-servers ${server_ip};
  range ${start_range} ${end_range};
  class "pxeclients" {
    match if substring (option vendor-class-identifier, 0, 9) = "PXEClient";
    next-server ${server_ip};
          if option architecture-type = 00:07 {
            filename "${os_base}/EFI/BOOT/BOOTX64.EFI";
          }
          else {
            filename "pxelinux/pxelinux.0";
          }
  }
  class "httpclients" {
    match if substring (option vendor-class-identifier, 0, 10) = "HTTPClient";
    option vendor-class-identifier "HTTPClient";
    filename "http://${server_ip}/${os_base}/EFI/BOOT/BOOTX64.EFI";
  }
}
EOF
    echo "DHCP server configured."
    echo "Configure file created at ${dhcp_conf_file}"
    echo "--------------------------------"
    cat "${dhcp_conf_file}"
    echo "--------------------------------"
}

CopyISOFiles() {
    local source_dir="$1"
    local dest_dir="$2"
    # Copy files from the source directory to the destination directory
    echo "Copying files from ${source_dir} to ${dest_dir} ..."
    rsync -a --info=progress2,stats2 "${source_dir}/" "/${dest_dir}/"
    echo "--------------------------------"
}

# Setup UEFI Network Boot
CreateGrubCfg() {
    local grub_cfg_path="$1"
    local grub_cfg_file="$2"
    local short_name="$3"
    local os_version="$4"
    local server_ip="$5"
    local version_ks="$6"
    local os_base="$7"
    local boot_path="$8"
    # Create grub.cfg for network boot
echo "Setting up UEFI Network Boot..."
# Create grub.cfg for network boot
echo "Creating grub.cfg for network boot..."
cat << EOF | tee ${grub_cfg_path}/${grub_cfg_file} > /dev/null
set default="0"

function load_video {
  insmod efi_gop
  insmod efi_uga
  insmod video_bochs
  insmod video_cirrus
  insmod all_video
}

load_video
set gfxpayload=keep
insmod gzio
insmod part_gpt
insmod ext2

set timeout=5
### END /etc/grub.d/00_header ###

search --no-floppy --set=root -l '${short_name}-${os_version}_Server.x86_64'

### BEGIN /etc/grub.d/10_linux ###
menuentry 'Install Red Hat Enterprise Linux ${os_version} kickstart' --class fedora --class gnu-linux --class gnu --class os {
	linuxefi ${boot_path}/${os_base}/vmlinuz inst.repo=http://${server_ip}/${version_ks} inst.ks=http://${server_ip}/${version_ks}/${version_ks}_ks.cfg quiet
	initrdefi ${boot_path}/${os_base}/initrd.img
}
menuentry 'Test this media & install Red Hat Enterprise Linux 8' --class fedora --class gnu-linux --class gnu --class os {
	linuxefi ${boot_path}/${os_base}/vmlinuz inst.repo=http://${server_ip}/${version_ks}  rd.live.check quiet
	initrdefi ${boot_path}/${os_base}/initrd.img
}
menuentry 'install Red Hat Enterprise Linux ${os_version} manaul' --class fedora --class gnu-linux --class gnu --class os {
	linuxefi ${boot_path}/${os_base}/vmlinuz rd.live.check quiet
	initrdefi ${boot_path}/${os_base}/initrd.img
}
submenu 'Troubleshooting -->' {
	menuentry 'Install Red Hat Enterprise Linux ${os_version} in basic graphics mode' --class fedora --class gnu-linux --class gnu --class os {
		linuxefi ${boot_path}/${os_base}/vmlinuz inst.repo=http://${server_ip}/${version_ks}  xdriver=vesa nomodeset quiet
		initrdefi ${boot_path}/${os_base}/initrd.img
	}
	menuentry 'Rescue a Red Hat Enterprise Linux system' --class fedora --class gnu-linux --class gnu --class os {
		linuxefi ${boot_path}/${os_base}/vmlinuz inst.repo=http://${server_ip}/${version_ks} rescue quiet
		initrdefi ${boot_path}/${os_base}/initrd.img
	}
}
EOF
echo "grub.cfg for network boot created."
echo "--------------------------------"
}
# Main logic

# This script prompts the user to choose whether to mount an ISO file.
# It requires the path to the ISO file and a mount point directory.

# --- Function to prompt for Yes/No confirmation ---
# This is a reusable function for clean code.
# Check condition for confgiure local repo for install packate

cat << EOF
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@                                                                   @
@            Install package for UEFI boot(Kickstart)               @
@                                                                   @
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
EOF
if [[ ${HTTP_FLAGS} -ne 0 || ${DHCP_FLAGS} -ne 0 || ${TFTP_FLAGS} -ne 0 ]]; then
    if [[ ${ENABLE_REPO} -eq 0 ]]; then
        echo "Repo is not already"
        echo "Please Configure repo"
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
        CreateLocalRepo "${REPO_CONF_PATH}" "${DIR_HOST_VERSION}" "${DIR_ISO_ROOT}"
    fi

    # Call function to install packages
    InstallPackages "$HTTP_PACKAGE"
    InstallPackages "$TFTP_PACKAGE"
    InstallPackages "$DHCP_PACKAGE"

else

cat << EOF
Result:

${HTTP_PACKAGE} Package ard installed
Skip install......

${TFTP_PACKAGE} Package ard installed
Skip install......

${DHCP_PACKAGE} Package ard installed
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

# Create symbolic link for HTTP Repo
echo "Creating symbolic link for HTTP Repo..."
current_path=$(pwd)
http_root="/var/www/html"
cd $http_root
if [ -L ${DIR_KS_VERSION} ]; then
    echo "Symbolic link ${DIR_KS_VERSION} already exists. Removing it first."
    rm -f ${DIR_KS_VERSION}
fi
ln -s ${MOUNTPOINT_HTTP_ROOT} ${DIR_KS_VERSION}
echo "Symbolic link created."
echo "--------------------------------" 
cd $current_path
pwd

CreateKickstartFile() {
    local kickstart_path="$1"
    local kickstart_file="$2"
    local server_ip="$3"
    local dir_root="$4"
# Create kickstart file for HTTP Repo
echo "Creating kickstart file for HTTP Repo..."
cat << EOF | tee ${kickstart_path}/${kickstart_file} > /dev/null
#version=RHEL8
# Use graphical install
graphical

repo --name="AppStream" --baseurl=http://${server_ip}/${dir_root}/AppStream


%packages
@^graphical-server-environment
kexec-tools

%end

# Keyboard layouts
keyboard --xlayouts='us'
# System language
lang en_US.UTF-8

# Network information
network  --hostname=localhost.localdomain

# Use CDROM installation media
# cdrom
url --url="http://${server_ip}/${dir_root}/BaseOS"

# Run the Setup Agent on first boot
firstboot --enable

ignoredisk --only-use=sda
# Partition clearing information
clearpart --drives=sda --initlabel
# Disk partitioning information
part /boot/efi --fstype="efi" --ondisk=sda --size=600 --fsoptions="umask=0077,shortname=winnt"
part pv.270 --fstype="lvmpv" --ondisk=sda --size=100774
part /boot --fstype="xfs" --ondisk=sda --size=1024
volgroup rhel --pesize=4096 pv.270
logvol swap --fstype="swap" --size=8074 --name=swap --vgname=rhel
logvol /home --fstype="xfs" --grow --size=500 --name=home --vgname=rhel
logvol / --fstype="xfs" --grow --size=1024 --name=root --vgname=rhel

# System timezone
timezone America/New_York --isUtc

# Root password
rootpw --iscrypted $6$ZQ1hkl1S5G8o9W5f$P11Q6IiPV78RSuPSJxQOStsPCdXEPt0GOqwfMbMD2DQKI8YUWNm4Zq9vdN7j58S60U6Fk1AiHTclyZg.RMSEF/
user --name=sysreport --password=$6$.aTwnuxLb4hmTpAI$.1nuh3m66o8U6Fyt/JCr77/UXty76XR1F0C.9nXwi5TetE/w2c6SXm4QMGMfQGXdi48qMe51hXJEglEtH71/n0 --iscrypted --gecos="sysreport"

%addon com_redhat_kdump --enable --reserve-mb='auto'

%end

%anaconda
pwpolicy root --minlen=6 --minquality=1 --notstrict --nochanges --notempty
pwpolicy user --minlen=6 --minquality=1 --notstrict --nochanges --emptyok
pwpolicy luks --minlen=6 --minquality=1 --notstrict --nochanges --notempty
%end
EOF
echo "Kickstart file for HTTP Repo created."
echo "--------------------------------"
}

CreateKickstartFile "/var/www/html/${DIR_KS_VERSION}" "${DIR_KS_VERSION}_ks.cfg" ${SERVER_IP} ${DIR_KS_VERSION}

# if prompt_yn "Creating repositories for kickstart?"; then
#     echo "Mounting..."
#     # The mount command requires root privileges.
#     # The 'loop' option is essential for mounting an ISO file.
#     create_directory ${MOUNTPOINT_ISO_KS}
#     create_directory "${MOUNTPOINT_HTTP_ROOT}"
#     mount_iso "${ISO_PATH}" "${MOUNTPOINT_ISO_KS}"
#     CopyISOFiles "${MOUNTPOINT_ISO_KS}/" "${MOUNTPOINT_HTTP_ROOT}/"
# else
#     echo "--------------------------------------------------------------------"
#     mount |grep "${ISO_PATH}"
#     if mount |grep "${ISO_PATH}"; then
#         echo "The ISO is already mounted."
#         MOUNTPOINT_ISO_KS=$(mount |grep "${ISO_PATH}" | awk '{print $3}')
#         echo "Mount path: ${mount_iso_path}"
#         create_directory "${MOUNTPOINT_HTTP_ROOT}"
#         CopyISOFiles "${MOUNTPOINT_ISO_KS}/" "${MOUNTPOINT_HTTP_ROOT}/"
#     fi
#     echo "--------------------------------------------------------------------"
# fi

# Function configure http boot
ConfigureHttpBoot() {
    local dir_root="$1"
    local source_dir="$2"
    
    echo "Create directory root for http boot"
    echo "Directory: /var/www/html/${DIR_ISO_ROOT}"
    create_directory "/var/www/html/${DIR_ISO_ROOT}"

    echo "Copying EFI files to http root directory..."
    echo "Source Directory: ${MOUNTPOINT_ISO_KS}/EFI ===> Destination Directory: /var/www/html/${DIR_ISO_ROOT}"
    rsync -a --info=progress2,stats2 "${MOUNTPOINT_ISO_KS}/EFI" /var/www/html/${DIR_ISO_ROOT}/
    echo "EFI files copied to http root directory."
    echo "--------------------------------------------------------------"
    echo

    echo "Creating boot image for httppboot..."
    echo "Directory : /var/www/html/${DIR_ISO_ROOT}/images/${DIR_ISO_ROOT}"
    create_directory "/var/www/html/${DIR_ISO_ROOT}/images/${DIR_ISO_ROOT}"
    echo "--------------------------------------------------------------"
    echo

    echo "Copying images boot to httpboot"
    echo "Source Directory: ${MOUNTPOINT_ISO_KS}/images/pxeboot/{vmlinuz,initrd.img} ===> Destination Directory: /var/www/html/${DIR_ISO_ROOT}/images/${DIR_ISO_ROOT}"
    cp -p ${MOUNTPOINT_ISO_KS}/images/pxeboot/{vmlinuz,initrd.img} /var/www/html/${DIR_ISO_ROOT}/images/${DIR_ISO_ROOT}/
    echo "http boot image created."
    echo "--------------------------------"
    echo
}



# function configure TFTP server
ConfigureTftp() {
    local dir_root="$1"
    local source_dir="$2"
    # Configure TFTP Server for UEFI-boot
    echo "creating TFTP root directory..."
    echo "Directory : /var/lib/tftpboot/${DIR_ISO_ROOT}"
    echo "--------------------------------------------------------------"
    create_directory /var/lib/tftpboot/${DIR_ISO_ROOT}
    echo

    echo "Copying EFI files to TFTP root directory..."
    echo "Source Directory: ${MOUNTPOINT_ISO_KS}/EFI ===> Destination Directory: /var/lib/tftpboot/${DIR_ISO_ROOT}"
    rsync -a --info=progress2,stats2 "${MOUNTPOINT_ISO_KS}/EFI" /var/lib/tftpboot/${DIR_ISO_ROOT}/
    echo "EFI files copied to TFTP root directory."
    echo "--------------------------------------------------------------"
    echo

    echo "Creating boot image for tftpboot..."
    echo "Directory : /var/lib/tftpboot/images/${DIR_ISO_ROOT}"
    create_directory /var/lib/tftpboot/images/${DIR_ISO_ROOT}
    echo "--------------------------------------------------------------"
    echo

    echo "Copying images boot to pxeboot"
    echo "Source Directory: ${MOUNTPOINT_ISO_KS}/images/pxeboot/{vmlinuz,initrd.img} ===> Destination Directory: /var/lib/tftpboot/images/${DIR_ISO_ROOT}"
    cp -p ${MOUNTPOINT_ISO_KS}/images/pxeboot/{vmlinuz,initrd.img} /var/lib/tftpboot/images/${DIR_ISO_ROOT}/
    echo "Boot image created."
    echo "--------------------------------"
    echo

    # echo "Changing permissions for TFTP root directory..."
    # chmod -R 755 /var/lib/tftpboot/${DIR_ISO_ROOT}/
    # echo "Permissions changed."
    # echo "--------------------------------"
    # echo

}

# Function get version from .treeinfo
GetVersion() {
    local treeinfo_path="$1"
    if [ -f "$treeinfo_path" ]; then
        RHEL_VERSION=$(awk -F'=' '/^\[release\]/{flag=1; next} flag && /^version =/{print $2; exit}' "$treeinfo_path")
        RHEL_SHORT=$(awk -F'=' '/^\[release\]/{flag=1; next} flag && /^short =/{print $2; exit}' "$treeinfo_path")
        RHEL_VERSION=${RHEL_VERSION//[[:space:]]/}
        RHEL_SHORT=${RHEL_SHORT//[[:space:]]/}
        echo "RHEL version detected: ${RHEL_SHORT}-${RHEL_VERSION}"
        return 0
    else
        echo "Error: .treeinfo file not found at $treeinfo_path"
        return 1
    fi
}

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
        CreateGrubCfg "/var/www/html/${DIR_ISO_ROOT}/EFI/BOOT" "grub.cfg" "${RHEL_SHORT}" "${RHEL_VERSION}" "${SERVER_IP}" "${DIR_KS_VERSION}" "${DIR_ISO_ROOT}" "../../images"
        # show configure grub.cfg
        chmod 644 /var/www/html/${DIR_ISO_ROOT}/EFI/BOOT/grub.cfg
        cat "/var/www/html/${DIR_ISO_ROOT}/EFI/BOOT/grub.cfg"
        ;;
    *)
        echo "Invalid choice. Please enter 1 or 2."
        exit 1
        ;;
esac

#


echo "Script finished."
