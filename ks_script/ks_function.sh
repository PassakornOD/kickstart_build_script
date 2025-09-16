#!/bin/bash

#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
#@ Function install package
#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

InstallPackages() {
    local packages="$1"
    # Check if the httpd package is installed using dnf
    # yum is the default package manager for RHEL 8
    if yum list --installed $packages &> /dev/null; then
        echo
        echo "Package: $packages "
        echo "Details of installed package:"
        echo "----------------------------------------------------------------------------"
        yum list installed $packages
        echo "============================================================================"
    else
        echo "Attempting to install: $packages"
        if yum install -y $packages; then
            echo "Successfully installed packages."
            echo "============================================================================"
            return 0
        else
            echo "Failed to install packages. Please check your internet connection and repository configuration."
            echo "============================================================================"
            return 1
        fi
    fi
}

#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
#@ Function create directory
#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
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

#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
#@ Function mount iso to mount point
#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
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

#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
#@ Function create and configure repository(rhel8 and above version)
#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Function to create a local repository configuration file
CreateLocalRepo() {
    local repo_conf_path="$1"
    local repo_version="$2"
    local repo_path="$3"
    TIME_FORMAT="%Y%m%d%H%M%S"
    TIMESTAMP=$(date +"$TIME_FORMAT")
    # Check if the repository file already exists
    if [ -f "$repo_conf_path/$repo_version.repo" ]; then
        echo "Warning: Repository file $repo_version.repo already exists."
        echo "Backing up the existing file with a timestamp."

        # Create the full file name.
        cp "${repo_conf_path}/${repo_version}.repo" "${repo_conf_path}/${repo_version}.repo_${TIMESTAMP}"
    fi

    # Create the repository file 
    echo "Creating repository file: $repo_conf_path/$repo_version.repo"
    cat << EOF | tee "$repo_conf_path/$repo_version.repo" > /dev/null
[BaseOS]
name=${repo_version}-BaseOS
baseurl=file://${repo_path}/BaseOS
enabled=1
gpgcheck=0
[AppStream]
name=${repo_version}-AppStream
baseurl=file://${repo_path}/AppStream
enabled=1
gpgcheck=0
EOF

    # Use 'diff --brief' to quickly check for differences without printing them.
    # We redirect the output to /dev/null because we only care about the exit status.
    if diff --brief "${repo_conf_path}/${repo_version}.repo" "${repo_conf_path}/${repo_version}.repo_${TIMESTAMP}" >/dev/null; then
        echo "${repo_conf_path}/${repo_version}.repo and ${repo_conf_path}/${repo_version}.repo_${TIMESTAMP} have same content"
        rm -rf ${repo_conf_path}/${repo_version}.repo_${TIMESTAMP}
    fi

    echo "--------------------------------"
    echo "Repository file created at $repo_conf_path/$repo_version.repo"
    cat "$repo_conf_path/$repo_version.repo"
    echo "--------------------------------"

    # Verify the file was created
    if [ $? -eq 0 ]; then
        echo "Repository configuration created successfully."
        echo "Cleaning yum cache..."
        yum clean all
        echo "--------------------------------"
        echo "Refreshing yum repository list..."
        yum repolist
    else
        echo "Failed to create the repository file. Check permissions."
        exit 1
    fi
    echo "--------------------------------"
}

#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
#@ Function configure dhcp config file
#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
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

#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
#@ Function copy file with rsync
#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
CopyISOFiles() {
    local source_dir="$1"
    local dest_dir="$2"
    # Copy files from the source directory to the destination directory
    echo "Copying files from ${source_dir} to ${dest_dir} ..."
    rsync -a --info=progress2,stats2 "${source_dir}/" "/${dest_dir}/"
    echo "--------------------------------"
}

#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
#@ Function configure grub.cfg for UEFI boot 
#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
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

set timeout=15
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

#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
#@ Function Create Kickstart cfg file 
#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
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
clearpart --all --initlabel --drives=sda
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

#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
#@ Function configure http boot for UEFI-boot
#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
ConfigureHttpBoot() {
    local dir_root="$1"
    local source_dir="$2"
    
    echo "Create directory root for http boot"
    echo "Directory: ${HTTP_DEFAULT_ROOT}/${DIR_ISO_ROOT}"
    create_directory "${HTTP_DEFAULT_ROOT}/${DIR_ISO_ROOT}"

    echo "Copying EFI files to http root directory..."
    echo "Source Directory: ${MOUNTPOINT_ISO_KS}/EFI ===> Destination Directory: ${HTTP_DEFAULT_ROOT}/${DIR_ISO_ROOT}"
    rsync -a --info=progress2,stats2 "${MOUNTPOINT_ISO_KS}/EFI" ${HTTP_DEFAULT_ROOT}/${DIR_ISO_ROOT}/
    echo "EFI files copied to http root directory."
    echo "--------------------------------------------------------------"
    echo

    echo "Creating boot image for httppboot..."
    echo "Directory : ${HTTP_DEFAULT_ROOT}/${DIR_ISO_ROOT}/images/${DIR_ISO_ROOT}"
    create_directory "${HTTP_DEFAULT_ROOT}/${DIR_ISO_ROOT}/images/${DIR_ISO_ROOT}"
    echo "--------------------------------------------------------------"
    echo

    echo "Copying images boot to httpboot"
    echo "Source Directory: ${MOUNTPOINT_ISO_KS}/images/pxeboot/{vmlinuz,initrd.img} ===> Destination Directory: ${HTTP_DEFAULT_ROOT}/${DIR_ISO_ROOT}/images/${DIR_ISO_ROOT}"
    cp -p ${MOUNTPOINT_ISO_KS}/images/pxeboot/{vmlinuz,initrd.img} ${HTTP_DEFAULT_ROOT}/${DIR_ISO_ROOT}/images/${DIR_ISO_ROOT}/
    echo "http boot image created."
    echo "--------------------------------"
    echo
}

#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
#@ Function configure pxeboot for UEFI-boot(tftp)
#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
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

#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
#@ Function get version from .treeinfo
#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
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

#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
#@ Function allow firewall 
#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
EnableServiceOnFW() {
    local service="$1"
    if firewall-cmd --query-service="${service}" &> /dev/null; then
        echo "Service ${service} are allowed..."
        echo
    else
        echo "firewall-cmd --add-service="${service}" --permanent"
        firewall-cmd --add-service="${service}" --permanent
        echo
    fi
}


#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
#@ Function enable and start service
#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Enable and Start Service
StartService() {
    local service="$1"
    if systemctl is-enabled --quiet "${service}"; then
        echo "Enable ${service} service..."
        echo "Service ${service} is already enabled."
        echo

    else
        echo "Enable ${service} service..."
        echo "Attempting to enable ${service} service..."
        systemctl enable "${service}"
        echo

    fi

    if systemctl is-active --quiet "${service}"; then
        echo "Start ${service} service..."
        echo "Service ${service} is already running."
        TIMEOUT=20 # seconds
        echo "Service ${service} is running. Are you restart ${service}?"
        echo "Please confirm if this is the version you expect. It will execute automatically in $TIMEOUT seconds if you don't respond."
        echo "Press 'y' to confirm or 'n' to cancel."

        read -t $TIMEOUT -p "Proceed? (y/n): " -n 1 -r

        echo

        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo "Service ${service} restarting..."
            systemctl restart ${service}
            echo
        elif [[ $REPLY =~ ^[Nn]$ ]]; then
            echo "Skip for restart service ${service}"
            echo
        else
            # If read times out or user presses a different key
            echo "Timeout reached or invalid input. Operation cancelled."
            exit 1
        fi
    else
        echo "Start ${service} service..."
        echo "Attempting to start ${service} service..."
        systemctl start "${service}"
        echo
    fi
    echo "============================================================="
}
