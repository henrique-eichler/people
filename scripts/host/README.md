# Host setup: setup-host-virt-manager.sh and virt-manager quick guide

Last updated: 2025-08-18 16:04

Scope
- How to run the host setup script (setup-host-virt-manager.sh) to install and configure KVM/libvirt/virt-manager on Debian/Ubuntu/Pop!_OS hosts.
- How to create an Ubuntu Server virtual machine (VM) with virt-manager after running the host setup.
- For post‑VM steps (copying scripts into the VM and provisioning services), see ../README.md.

1) Prerequisites
- Host OS: Debian/Ubuntu/Pop!_OS with sudo privileges.
- Internet connectivity.
- Ubuntu Server ISO (e.g., ubuntu-24.04-live-server-amd64.iso).
- Helper functions available at $HOME/Projects/tools/functions.sh on the host.

Prepare helper functions (host)
- From the repository root:
  - mkdir -p "$HOME/Projects/tools"
  - cp scripts/functions.sh "$HOME/Projects/tools/functions.sh"

2) Run the host setup script
- From the repository root:
  - bash scripts/host/setup-host-virt-manager.sh [options]
- Or from this directory:
  - ./setup-host-virt-manager.sh [options]

Options
- --vm-name <name>        Optional. Libvirt VM name used for GPU/vfio hooks.
- --enable-hugepages      Optional. Prefer transparent hugepages (best effort).
- --no-reboot-warning     Optional. Do not show reboot prompt at the end.
- -h, --help              Show help.

Example
- bash scripts/host/setup-host-virt-manager.sh --vm-name ubuntu-server --enable-hugepages

Notes
- Do NOT run the script with sudo; it will invoke sudo internally when needed.
- A reboot is recommended after the script completes to apply IOMMU/vfio changes.
- The script targets apt-based hosts (Debian/Ubuntu family).

3) Create an Ubuntu Server VM with virt-manager
Steps
- Launch virt-manager (Virtual Machine Manager).
- Click "Create a new virtual machine".
- Choose "Local install media (ISO)".
- Select the Ubuntu Server ISO and OS type (Ubuntu 22.04/24.04).
- Memory/CPU: choose appropriate values (e.g., 4096 MB RAM, 2–4 vCPUs).
- Storage: create a new disk (e.g., 40–100 GB). Use virtio for disk and network when available.
- Firmware: if available, select UEFI (OVMF).
- Network: default NAT is fine; use a bridge if you need LAN access.
- Name the VM (if you used --vm-name earlier, keep the same name to apply hooks).
- Finish and start the installation.

Ubuntu installation tips
- Create an admin user (with sudo) during install.
- Select "Install OpenSSH server" to enable SSH access.
- After first boot inside the VM:
  - sudo apt-get update -y
  - sudo apt-get install -y qemu-guest-agent
  - sudo systemctl enable --now qemu-guest-agent

Troubleshooting
- "functions.sh not found" when running the host script:
  - Ensure you copied scripts/functions.sh to $HOME/Projects/tools/functions.sh on the host.
- KVM not available:
  - Verify virtualization is enabled in BIOS/UEFI and that your user is in the libvirt/libvirt-qemu groups (log out/in if needed).
- NVIDIA GPU passthrough:
  - If you passed --vm-name, the script installs libvirt hooks. Use the same VM name in virt-manager.

Next steps (inside the VM)
- See ../README.md for how to copy scripts into the VM under $HOME/Projects/tools and run:
  - sudo ~/Projects/tools/setup-docker.sh
  - ~/Projects/tools/setup-server.sh <domain>  (non-root)