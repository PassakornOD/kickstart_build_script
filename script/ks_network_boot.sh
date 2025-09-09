#!/bin/bash

clear
# Define the path to your configuration file
CONFIG_FILE="./config.env"
FUNC_SCRIPT="./function_script.sh"

call_env() {
    local file_path="$1"
    if [ -f "$file_path" ]; then
    # Use 'source' to load the variables
    source "$file_path"
    echo "@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@"
    echo "${file_path} Configuration loaded successfully."
    echo "@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@"
    else
        echo "Error: File '$file_path' does not exist."
        exit 1
    fi
}

call_env $CONFIG_FILE
call_env $FUNC_SCRIPT

#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# Main script execution starts here

#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# Create a new directory for mounting ISO files(Local Repo)

echo "Attempting to create a new directory..."
create_directory /${REPOS_MOUNT}/${LOCAL_REPOS}
echo "Exit code: $?"
echo "-------------------"

# Mount a valid ISO file(Local Repo)
echo "Mounting ISO  Local files..."
mount_iso $LOCAL_ISO "/${REPOS_MOUNT}/${LOCAL_REPOS}"
echo "--------------------------------"


# Create a new directory for mounting ISO files(Kickstart Repo)
echo "Attempting to create a new directory..."
create_directory /${REPOS_MOUNT}/${LASTEST_REPOS}
echo "Exit code: $?"
echo "-------------------"

# Mount a valid ISO file(Kickstart Repo)
echo "Mounting ISO  Kickstart files..."
mount_iso $LASTEST_ISO /${REPOS_MOUNT}/${LASTEST_REPOS}
echo "--------------------------------"

# Check if the repository file already exists
if [ -f "$REPO_PATH/$REPO_NAME.repo" ]; then
    echo "Warning: Repository file $REPO_NAME.repo already exists. Overwriting."
fi

# Create the repository file
echo "Creating repository file: $REPO_PATH/$LOCAL_REPOS.repo"
cat << EOF | tee "$REPO_PATH/$LOCAL_REPOS.repo" > /dev/null
[BaseOS]
name=${LOCAL_REPOS}-BaseOS
baseurl=file:///${REPOS_MOUNT}/${LOCAL_REPOS}/BaseOS
enabled=1
gpgcheck=0
[AppStream]
name=${LOCAL_REPOS}-AppStream
baseurl=file:///${REPOS_MOUNT}/${LOCAL_REPOS}/AppStream
enabled=1
gpgcheck=0
EOF

echo "--------------------------------"
echo "Repository file created at $REPO_PATH/$LOCAL_REPOS.repo"
cat "$REPO_PATH/$LOCAL_REPOS.repo"
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


# Check for root privileges
if [ "$(id -u)" -ne 0 ]; then
   echo "This script must be run as root. Exiting." >&2
   exit 1
fi

# Main logic
install_packages


echo "Configuring DHCP server..."
cat << EOF |tee ${DHCP_CONF} > /dev/null
# DHCP Server Configuration file.
option architecture-type code 93 = unsigned integer 16;

subnet ${SUBNET} netmask ${NETMASK} {
  option routers ${GATEWAY};
  option domain-name-servers ${SERVER};
  range ${S_RANGE} ${E_RANGE};
  class "pxeclients" {
    match if substring (option vendor-class-identifier, 0, 9) = "PXEClient";
    next-server ${SERVER};
          if option architecture-type = 00:07 {
            filename "${LASTEST_REPOS}/EFI/BOOT/BOOTX64.EFI";
          }
          else {
            filename "pxelinux/pxelinux.0";
          }
  }
  class "httpclients" {
    match if substring (option vendor-class-identifier, 0, 10) = "HTTPClient";
    option vendor-class-identifier "HTTPClient";
    filename "http://${SERVER}/${LASTEST_REPOS}/EFI/BOOT/BOOTX64.EFI";
  }
}
EOF
echo "DHCP server configured."
echo "--------------------------------"
echo "Repository file created at ${DHCP_CONF}"
cat "${DHCP_CONF}"
echo "--------------------------------"

# Configure TFTP Server for UEFI-boot
echo "creating TFTP root directory..."
create_directory /var/lib/tftpboot/${REPOS_MOUNT}
echo "Copying EFI files to TFTP root directory..."
rsync -a --info=progress2,stats2 "/${REPOS_MOUNT}/${LASTEST_REPOS}/EFI" /var/lib/tftpboot/${REPOS_MOUNT}/
echo "EFI files copied to TFTP root directory."
echo "--------------------------------"

# Change permissions for TFTP root directory
echo "Changing permissions for TFTP root directory..."
chmod -R 755 /var/lib/tftpboot/${REPOS_MOUNT}/
echo "Permissions changed."
echo "--------------------------------"
RHEL_VERSION=$(awk -F'=' '/^\[release\]/{flag=1; next} flag && /^version =/{print $2; exit}' "/${REPOS_MOUNT}/${LASTEST_REPOS}/.treeinfo")
RHEL_SHORT=$(awk -F'=' '/^\[release\]/{flag=1; next} flag && /^short =/{print $2; exit}' "/${REPOS_MOUNT}/${LASTEST_REPOS}/.treeinfo")
RHEL_VERSION=${RHEL_VERSION//[[:space:]]/}
RHEL_SHORT=${RHEL_SHORT//[[:space:]]/}
echo "RHEL version detected: ${RHEL_SHORT}-${RHEL_VERSION}"
echo "--------------------------------"
# Create grub.cfg for network boot
echo "Creating grub.cfg for network boot..."
cat << EOF | tee /var/lib/tftpboot/${REPOS_MOUNT}/EFI/BOOT/grub.cfg > /dev/null
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

search --no-floppy --set=root -l '${RHEL_SHORT}-${RHEL_VERSION}_Server.x86_64'

### BEGIN /etc/grub.d/10_linux ###
menuentry 'Install Red Hat Enterprise Linux ${RHEL_VERSION} kickstart' --class fedora --class gnu-linux --class gnu --class os {
	linuxefi images/${REPOS_MOUNT}/vmlinuz inst.repo=http://${SERVER}/${LASTEST_REPOS} inst.ks=http://${SERVER}/${LASTEST_REPOS}/rhel8_10_ks.cfg quiet
	initrdefi images/${REPOS_MOUNT}/initrd.img
}
menuentry 'Test this media & install Red Hat Enterprise Linux 8' --class fedora --class gnu-linux --class gnu --class os {
	linuxefi images/${REPOS_MOUNT}/vmlinuz inst.repo=http://${SERVER}/${LASTEST_REPOS}  rd.live.check quiet
	initrdefi images/${REPOS_MOUNT}/initrd.img
}
menuentry 'install Red Hat Enterprise Linux ${RHEL_VERSION} manaul' --class fedora --class gnu-linux --class gnu --class os {
	linuxefi images/${REPOS_MOUNT}/vmlinuz rd.live.check quiet
	initrdefi images/${REPOS_MOUNT}/initrd.img
}
submenu 'Troubleshooting -->' {
	menuentry 'Install Red Hat Enterprise Linux ${RHEL_VERSION} in basic graphics mode' --class fedora --class gnu-linux --class gnu --class os {
		linuxefi images/${REPOS_MOUNT}/vmlinuz inst.repo=http://${SERVER}/${LASTEST_REPOS}  xdriver=vesa nomodeset quiet
		initrdefi images/${REPOS_MOUNT}/initrd.img
	}
	menuentry 'Rescue a Red Hat Enterprise Linux system' --class fedora --class gnu-linux --class gnu --class os {
		linuxefi images/${REPOS_MOUNT}/vmlinuz inst.repo=http://${SERVER}/${LASTEST_REPOS} rescue quiet
		initrdefi images/${REPOS_MOUNT}/initrd.img
	}
}
EOF
echo "grub.cfg for network boot created."
echo "--------------------------------"

echo "Creating boot image for tftpboot..."
create_directory /var/lib/tftpboot/images/${REPOS_MOUNT}/
cp -p /${REPOS_MOUNT}/${LASTEST_REPOS}/images/pxeboot/{vmlinuz,initrd.img} /var/lib/tftpboot/images/${REPOS_MOUNT}/
echo "Boot image created."
echo "--------------------------------"


# Create a new directory for mounting ISO files(Kickstart Repo)
echo "Attempting to create a new directory..."
create_directory /${HTTP_REPO}/${REPOS_MOUNT}/${LASTEST_REPOS}
echo "Exit code: $?"
echo "-------------------"

# Configure permission for HTTP Repo
echo "Configuring permission for HTTP Repo..."
chown -R apache:apache /${HTTP_REPO}/${REPOS_MOUNT}/${LASTEST_REPOS}
chmod -R 755 /${HTTP_REPO}/${REPOS_MOUNT}/${LASTEST_REPOS}
semanage fcontext -a -t httpd_sys_content_t "/${HTTP_REPO}/${REPOS_MOUNT}/${LASTEST_REPOS}(/.*)?"
restorecon -Rv /${HTTP_REPO}/${REPOS_MOUNT}/${LASTEST_REPOS}
echo "Permission configured."
echo "--------------------------------"

# Create symbolic link for HTTP Repo
echo "Creating symbolic link for HTTP Repo..."
if [ -L /var/www/html/${LASTEST_REPOS} ]; then
    echo "Symbolic link /var/www/html/${LASTEST_REPOS} already exists. Removing it first."
    rm -f /var/www/html/${LASTEST_REPOS}
fi
ln -s /${HTTP_REPO}/${REPOS_MOUNT}/${LASTEST_REPOS} /var/www/html/${LASTEST_REPOS}
echo "Symbolic link created."
echo "--------------------------------" 
 
# Copy files from the source directory to the destination directory
echo "Copying files from /${REPOS_MOUNT}/${LASTEST_REPOS}/ to /${HTTP_REPO}/${REPOS_MOUNT}/${LASTEST_REPOS}/ ..."
rsync -a --info=progress2,stats2 "/${REPOS_MOUNT}/${LASTEST_REPOS}/" "/${HTTP_REPO}/${REPOS_MOUNT}/${LASTEST_REPOS}/"
echo "--------------------------------"

# Create kickstart file for HTTP Repo
echo "Creating kickstart file for HTTP Repo..."
cat << EOF | tee /${HTTP_REPO}/${REPOS_MOUNT}/${LASTEST_REPOS}/${LASTEST_REPOS}_ks.cfg > /dev/null
#version=RHEL8
# Use graphical install
graphical

repo --name="AppStream" --baseurl=http://${SERVER}/${LASTEST_REPOS}/AppStream


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
url --url="http://${SERVER}/${LASTEST_REPOS}/BaseOS"

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

# allow firewall for HTTP, DHCP, and TFTP services
echo "Configuring firewall rules..."
firewall-cmd --permanent --add-service=http
firewall-cmd --permanent --add-service=dhcp
firewall-cmd --permanent --add-service=tftp
firewall-cmd --reload
echo "Firewall rules configured."
echo "--------------------------------"

# enable and start services
enable_start_services