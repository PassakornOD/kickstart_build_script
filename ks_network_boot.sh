#!/bin/bash

LOCAL_ISO="/dev/sr0"
LASTEST_ISO="/root/rhel-8.10-x86_64-dvd.iso"
LOCAL_REPOS="rhel8_4"
REPOS_MOUNT="rhel8"
LASTEST_REPOS="rhel8_10"
REPO_PATH="/etc/yum.repos.d"
REPO_NAME="rhel8_10"
HTTP_REPO="repos"

# Define the packages to be installed
PACKAGES="httpd dhcp-server tftp-server"

# Check mount point for local Repos
if [ ! -d "/${REPOS_MOUNT}/${LOCAL_REPOS}" ]; then
    mkdir -p /${REPOS_MOUNT}/${LOCAL_REPOS}
fi

# Check mount point for Repos
if [ ! -d "/${REPOS_MOUNT}/${LASTEST_REPOS}" ]; then
    mkdir -p /${REPOS_MOUNT}/${LASTEST_REPOS}
fi

# Check if the local ISO is already mounted
if findmnt --source "$LOCAL_ISO" --target "/${REPOS_MOUNT}/${LOCAL_REPOS}" >/dev/null; then
    echo "ISO is already mounted at /${REPOS_MOUNT}/${LOCAL_REPOS}."
else
    # If not mounted, attempt to mount it
    echo "ISO is not mounted. Attempting to mount..."
    sudo mount -o loop "$LOCAL_ISO" "/${REPOS_MOUNT}/${LOCAL_REPOS}"
    
    # Check if the mount was successful
    if [ $? -eq 0 ]; then
        echo "Successfully mounted $LOCAL_ISO to /${REPOS_MOUNT}/${LOCAL_REPOS}"
    else
        echo "Mount failed. Please check your permissions and paths."
        exit 1
    fi
fi


# Check if the local lastest ISO is already mounted
if findmnt --source "$LASTEST_ISO" --target "/${REPOS_MOUNT}/${LASTEST_REPOS}" >/dev/null; then
    echo "ISO is already mounted at /${REPOS_MOUNT}/${LASTEST_REPOS}."
else
    # If not mounted, attempt to mount it
    echo "ISO is not mounted. Attempting to mount..."
    sudo mount -o loop "$LASTEST_ISO" "/${REPOS_MOUNT}/${LASTEST_REPOS}"
    
    # Check if the mount was successful
    if [ $? -eq 0 ]; then
        echo "Successfully mounted $LASTEST_ISO to /${REPOS_MOUNT}/${LASTEST_REPOS}"
    else
        echo "Mount failed. Please check your permissions and paths."
        exit 1
    fi
fi

if [ ! -d "/${HTTP_REPO}/${REPOS_MOUNT}/${LASTEST_REPOS}" ]; then
    mkdir -p /${HTTP_REPO}/${REPOS_MOUNT}/${LASTEST_REPOS}
fi

# Check if the destination directory is empty
# The 'ls -A' command lists all files, including hidden ones, but not '.' or '..'.
# The '-z' test checks if the output string is empty.
if [ -z "$(ls -A "/${HTTP_REPO}/${REPOS_MOUNT}/${LASTEST_REPOS}")" ]; then
    echo "Destination directory is empty. Proceeding with copy..."
    
    # Copy files and directories preserving attributes
    # The -a flag is for "archive" mode. It's equivalent to -dR --preserve=all
    # which preserves permissions, ownership, timestamps, and symbolic links.
    sudo cp -av "/${REPOS_MOUNT}/${LASTEST_REPOS}/." "/${HTTP_REPO}/${REPOS_MOUNT}/${LASTEST_REPOS}"
    
    if [ $? -eq 0 ]; then
        echo "Files copied successfully with permissions preserved."
        echo "Contents of /${HTTP_REPO}/${REPOS_MOUNT}/${LASTEST_REPOS}:"
        ls -l "/${HTTP_REPO}/${REPOS_MOUNT}/${LASTEST_REPOS}"
    else
        echo "Error: Failed to copy files."
        exit 1
    fi
else
    echo "Error: Destination directory is not empty. Aborting copy."
    exit 1
fi

# Check if the repository file already exists
if [ -f "$REPO_PATH/$REPO_NAME.repo" ]; then
    echo "Warning: Repository file $REPO_NAME.repo already exists. Overwriting."
fi

# Create the repository file
echo "Creating repository file: $REPO_PATH/$REPO_NAME.repo"
cat << EOF | sudo tee "$REPO_PATH/$REPO_NAME.repo" > /dev/null
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

# Verify the file was created
if [ $? -eq 0 ]; then
    echo "Repository configuration created successfully."
    echo "Cleaning dnf cache..."
    sudo dnf clean all
    echo "Refreshing dnf repository list..."
    sudo dnf repolist
    echo "Script finished."
else
    echo "Failed to create the repository file. Check permissions."
    exit 1
fi



# Check for root privileges
if [ "$(id -u)" -ne 0 ]; then
   echo "This script must be run as root. Exiting." >&2
   exit 1
fi

# Function to install packages
install_packages() {
    echo "Attempting to install: $PACKAGES"
    if dnf install -y $PACKAGES; then
        echo "Successfully installed packages."
        return 0
    else
        echo "Failed to install packages. Please check your internet connection and repository configuration."
        return 1
    fi
}

# Function to enable and start services
enable_start_services() {
    local services="httpd dhcpd tftp.socket"
    for service in $services; do
        echo "Enabling and starting $service..."
        systemctl enable --now $service
        if [ $? -eq 0 ]; then
            echo "$service enabled and started successfully."
        else
            echo "Failed to enable and start $service. Please check the service name and status."
        fi
    done
}

# Main logic
install_packages
if [ $? -eq 0 ]; then
    enable_start_services
    echo "Installation and service configuration complete."
else
    echo "Script aborted due to package installation failure."
fi