#!/bin/bash

# Define the path to your configuration file
CONFIG_FILE="./config.env"

# Check if the config file exists
if [ -f "$CONFIG_FILE" ]; then
    # Use 'source' to load the variables
    source "$CONFIG_FILE"
    echo "@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@"
    echo "Configuration loaded successfully."
    echo "@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@"
else
    echo "Error: Configuration file not found at $CONFIG_FILE"
    exit 1
fi

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
        sudo mount -o loop "$iso_path" "$mount_point"
        
        # Check if the mount was successful
        if [ $? -eq 0 ]; then
            echo "Successfully mounted $iso_path to $mount_point"
        else
            echo "Mount failed. Please check your permissions and paths."
            exit 1
        fi
    fi
}

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


# # Check mount point for local Repos
# if [ ! -d "/${REPOS_MOUNT}/${LOCAL_REPOS}" ]; then
#     mkdir -p /${REPOS_MOUNT}/${LOCAL_REPOS}
# fi

# # Check mount point for Repos
# if [ ! -d "/${REPOS_MOUNT}/${LASTEST_REPOS}" ]; then
#     mkdir -p /${REPOS_MOUNT}/${LASTEST_REPOS}
# fi



# # Check if the local ISO is already mounted
# if findmnt --source "$LOCAL_ISO" --target "/${REPOS_MOUNT}/${LOCAL_REPOS}" >/dev/null; then
#     echo "ISO is already mounted at /${REPOS_MOUNT}/${LOCAL_REPOS}."
# else
#     # If not mounted, attempt to mount it
#     echo "ISO is not mounted. Attempting to mount..."
#     sudo mount -o loop "$LOCAL_ISO" "/${REPOS_MOUNT}/${LOCAL_REPOS}"
    
#     # Check if the mount was successful
#     if [ $? -eq 0 ]; then
#         echo "Successfully mounted $LOCAL_ISO to /${REPOS_MOUNT}/${LOCAL_REPOS}"
#     else
#         echo "Mount failed. Please check your permissions and paths."
#         exit 1
#     fi
# fi


# # Check if the local lastest ISO is already mounted
# if findmnt --source "$LASTEST_ISO" --target "/${REPOS_MOUNT}/${LASTEST_REPOS}" >/dev/null; then
#     echo "ISO is already mounted at /${REPOS_MOUNT}/${LASTEST_REPOS}."
# else
#     # If not mounted, attempt to mount it
#     echo "ISO is not mounted. Attempting to mount..."
#     sudo mount -o loop "$LASTEST_ISO" "/${REPOS_MOUNT}/${LASTEST_REPOS}"
    
#     # Check if the mount was successful
#     if [ $? -eq 0 ]; then
#         echo "Successfully mounted $LASTEST_ISO to /${REPOS_MOUNT}/${LASTEST_REPOS}"
#     else
#         echo "Mount failed. Please check your permissions and paths."
#         exit 1
#     fi
# fi

# Create a new directory for mounting ISO files(Kickstart Repo)
echo "Attempting to create a new directory..."
create_directory /${HTTP_REPO}/${REPOS_MOUNT}/${LASTEST_REPOS}
echo "Exit code: $?"
echo "-------------------"
# if [ ! -d "/${HTTP_REPO}/${REPOS_MOUNT}/${LASTEST_REPOS}" ]; then
#     mkdir -p /${HTTP_REPO}/${REPOS_MOUNT}/${LASTEST_REPOS}
# fi

# Check if the destination directory is empty
# The 'ls -A' command lists all files, including hidden ones, but not '.' or '..'.
# The '-z' test checks if the output string is empty.
if [ -z "$(ls -A "/${HTTP_REPO}/${REPOS_MOUNT}/${LASTEST_REPOS}")" ]; then
    echo "Destination directory is empty. Proceeding with copy..."
    
    # Copy files and directories preserving attributes
    # The -a flag is for "archive" mode. It's equivalent to -dR --preserve=all
    # which preserves permissions, ownership, timestamps, and symbolic links.
    cp -av "/${REPOS_MOUNT}/${LASTEST_REPOS}/." "/${HTTP_REPO}/${REPOS_MOUNT}/${LASTEST_REPOS}"
    
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
# if [ $? -eq 0 ]; then
#     enable_start_services
#     echo "Installation and service configuration complete."
# else
#     echo "Script aborted due to package installation failure."
# fi