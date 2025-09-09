#!/bin/bash

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

# Function to install packages
install_packages() {
    local package="$1"
    echo "Attempting to install: $packages"
    if yum install -y $packages; then
        echo "Successfully installed packages."
        return 0
    else
        echo "Failed to install packages. Please check your internet connection and repository configuration."
        return 1
    fi
}
