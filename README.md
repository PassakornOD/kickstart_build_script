
# Script build kickstart for RHEL8 (UEFI Network Boot)

## 📌 Introduction
This project provides a **shell script** (`ks_script`) to automate the creation and deployment of a **Kickstart-based installation** for **RHEL8** using **UEFI network boot**.

It is intended for developers, system engineers, and DevOps who need to:
- Customize RHEL8 unattended installations
- Integrate `kickstart.cfg` with UEFI bootloaders
- Deploy installation images via HTTP/PXE servers

---

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
kickstart_build_script/
├── README.md 
├── ks_script             # directory automation script
   ├── ks.cfg                    # Kickstart file (customizable)
   ├── setup-kickstart.sh        # Main automation script
   ├── ks_function.sh            # Function automation script
   └── pre-setup-kickstart.sh    # Pre-check for setup kickstart
   
