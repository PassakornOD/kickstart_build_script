
# Script build kickstart for RHEL8 (UEFI Network Boot)

## 📌 Introduction
This project provides a **shell script** (`ks_script`) to automate the creation and deployment of a **Kickstart-based installation** for **RHEL8** using **UEFI network boot**.

It is intended for developers, system engineers, and DevOps who need to:
- Customize RHEL8 unattended installations
- Integrate `kickstart.cfg` with UEFI bootloaders
- Deploy installation images via HTTP/PXE servers

---

## 📂 Script Structure
```
ks_script/
   ├── variable.env          # variable for script
   ├── setup-kickstart.sh        # Main automation script
   ├── ks_function.sh            # Function automation script
   ├── rhel-8.10-x86_64-dvd.iso  # ISO for UEFI network boot
   └── pre-setup-kickstart.sh    # Pre-check for setup kickstart
```

---

## ⚡ Quick Start Guide

### 1. Prepare RHEL Repository
If the server does **not** have access to official Red Hat repos, you can:
- Upload the RHEL8 ISO to the server, or
- Mount the ISO via optical drive

This ISO will be used as the local package repo.

**Note**
>For UEFI boot servers, dhcp, httpd/tftp services are required. If they are not already installed, the script will attempt to install them. In this case, a source media (e.g., RHEL ISO) must be available to configure a local repository. If a repository is already available, you can specify it so the script can use it for package installation.

### 2. Copy Files to Server
- Copy the desired **RHEL8 ISO** version to the server  
- Copy the `ks_script/` directory to the Kickstart server

### 3. Configure Script
- Edit `variable.env` to match your environment (e.g. ISO path, web root, server IP)

### 4. Set Permission
```bash
chmod +x ks_script/*.sh
```

### 5. Run the Script
```bash
./setup-kickstart.sh
```

<!-- ---

## ⚙️ How It Works

The script automates the following steps:

1. **Initialize Environment**
   - Define paths for:
     - Source RHEL8 ISO
     - Temporary working directory
     - Kickstart configuration (`kickstart.cfg`)
     - HTTP/TFTP root directory for network boot
   - Validate required tools (`mount`, `rsync`, `dhcpd`, `httpd`, `tftp`).

2. **Extract ISO**
   - Mount the RHEL8 ISO.
   - Copy its contents into a build directory for modification.

3. **Kickstart Integration**
   - Place `kickstart.cfg` into the build structure.
   - Update UEFI bootloader config (`EFI/BOOT/grub.cfg`) to automatically boot with Kickstart:
     ```cfg
     menuentry 'RHEL 8 Auto Install' {
         linuxefi /images/pxeboot/vmlinuz inst.repo=http://<server>/rhel8 inst.ks=http://<server>/kickstart.cfg
         initrdefi /images/pxeboot/initrd.img
     }
     ```

4. **Deploy Boot Files**
   - Copy required kernel and initrd:
     ```
     images/rhel8/vmlinuz
     images/rhel8/initrd.img
     ```
   - Copy UEFI loaders:
     ```
     shim.efi
     grubx64.efi
     ```
   - Ensure they are accessible under the HTTP/TFTP root.

5. **Deploy to Server**
   - Sync the build directory to `/var/www/html/rhel8/` or equivalent.
   - Restart services (`systemctl restart httpd tftp`).

6. **UEFI Network Boot**
   - Clients boot via UEFI PXE/HTTP.
   - The bootloader loads kernel + initrd, with Kickstart attached.
   - The RHEL installation runs automatically with no user input.

---

## 📂 Project Structure

kickstart_build_script/<br>
├── README.md<br> 
├── ks_script   &nbsp;&nbsp;&nbsp;&nbsp;       # directory automation script<br> 
   ├── variable.env   &nbsp;&nbsp;&nbsp;&nbsp;           # variable for script<br> 
   ├── setup-kickstart.sh   &nbsp;&nbsp;&nbsp;&nbsp;     # Main automation script<br> 
   ├── ks_function.sh       &nbsp;&nbsp;&nbsp;&nbsp;     # Function automation script<br> 
   └── pre-setup-kickstart.sh  &nbsp;&nbsp;&nbsp;&nbsp;  # Pre-check for setup kickstart -->
