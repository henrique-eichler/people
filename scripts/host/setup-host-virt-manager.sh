#!/usr/bin/env bash
set -euo pipefail
source "$(getent passwd ${SUDO_USER:-$USER} | cut -d: -f6)/Projects/tools/functions.sh"

# ===================================================================
setup_host_virt_manager() {
  set -euo pipefail

  local VM_NAME=""
  local ENABLE_HUGEPAGES=0
  local NO_REBOOT_WARNING=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --vm-name) VM_NAME="${2:-}"; shift 2;;
      --enable-hugepages) ENABLE_HUGEPAGES=1; shift;;
      --no-reboot-warning) NO_REBOOT_WARNING=1; shift;;
      -h|--help)
        info "Usage: setup_host_virt_manager [options]
              --vm-name <name>        Name of the libvirt VM (used for hooks, optional)
              --enable-hugepages      Enable transparent 2M hugepages tuning (best effort)
              --no-reboot-warning     Do not prompt about reboot at the end
              -h, --help              Show this help"
        return 0;;
      *) warn "Unknown option: $1"; shift;;
    esac
  done

  if command -v apt >/dev/null 2>&1; then
    info "Installing virtualization stack (KVM, libvirt, virt-manager)..."
    sudo apt-get update -y
    sudo apt-get install -y qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils virt-manager ovmf cpu-checker dmidecode
    sudo systemctl enable --now libvirtd || sudo systemctl enable --now libvirt-daemon || true
  else
    error "This function currently supports Debian/Ubuntu/Pop!_OS style hosts (apt)."
  fi

  if command -v kvm-ok >/dev/null 2>&1; then
    kvm-ok || warn "kvm-ok reports an issue—KVM might not be enabled in BIOS/UEFI."
  fi

  info "Configuring IOMMU kernel parameters (intel_iommu/amd_iommu + iommu=pt)..."
  local GRUB=/etc/default/grub
  if [[ -f "$GRUB" ]]; then
    sudo cp -a "$GRUB" "$GRUB.bak.$(date +%Y%m%d%H%M%S)"

    local CPU_VENDOR
    CPU_VENDOR="$(lscpu | awk -F: '/Vendor ID/{gsub(/^[ \t]+/,"",$2); print $2}')" || CPU_VENDOR=""

    local IOMMU_FLAG="intel_iommu=on"
    [[ "$CPU_VENDOR" == *AuthenticAMD* ]] && IOMMU_FLAG="amd_iommu=on"
    if ! grep -qE "(intel_iommu=on|amd_iommu=on)" "$GRUB"; then
      sudo sed -i "s/GRUB_CMDLINE_LINUX_DEFAULT=\"\(.*\)\"/GRUB_CMDLINE_LINUX_DEFAULT=\"\1 $IOMMU_FLAG iommu=pt kvm.ignore_msrs=1\"/" "$GRUB"
    else
      if ! grep -q "iommu=pt" "$GRUB"; then
        sudo sed -i "s/GRUB_CMDLINE_LINUX_DEFAULT=\"\(.*\)\"/GRUB_CMDLINE_LINUX_DEFAULT=\"\1 iommu=pt\"/" "$GRUB"
      fi
      if ! grep -q "kvm.ignore_msrs=1" "$GRUB"; then
        sudo sed -i "s/GRUB_CMDLINE_LINUX_DEFAULT=\"\(.*\)\"/GRUB_CMDLINE_LINUX_DEFAULT=\"\1 kvm.ignore_msrs=1\"/" "$GRUB"
      fi
    fi
    sudo update-grub || sudo grub-mkconfig -o /boot/grub/grub.cfg || true
  else
    warn "GRUB default config not found at $GRUB. Skipping kernel parameter configuration."
  fi

  # Detect NVIDIA hardware
  local HAS_NVIDIA=1
  if lspci | grep -qi 'NVIDIA'; then HAS_NVIDIA=0; fi
  if [[ $HAS_NVIDIA -eq 0 ]]; then
    info "NVIDIA hardware detected. Preparing vfio-pci for GPU passthrough..."

    local IDS
    IDS="$(lspci -nn | awk '/NVIDIA/{print $NF}' | tr -d '[]' | tr '\n' ',' | sed 's/,$//')" || IDS=""
    if [[ -z "$IDS" ]]; then
      warn "Could not extract NVIDIA PCI IDs; skipping vfio-pci IDs configuration."
    else
      info "NVIDIA PCI IDs: $IDS"
      sudo_append "/etc/modprobe.d/vfio.conf" "options vfio-pci ids=$IDS"
    fi

    sudo_append "/etc/modules-load.d/vfio.conf" "
      vfio
      vfio_iommu_type1
      vfio_pci"

    sudo_append "/etc/modprobe.d/blacklist-nouveau.conf" "
      blacklist nouveau
      options nouveau modeset=0"

    if command -v update-initramfs >/dev/null 2>&1; then
      sudo update-initramfs -u
    elif command -v dracut >/dev/null 2>&1; then
      sudo dracut -f
    fi

    if [[ -n "$VM_NAME" ]]; then
      info "Installing libvirt qemu hooks for VM: $VM_NAME"
      local HOOK_BASE="/etc/libvirt/hooks/qemu.d/$VM_NAME"
      sudo mkdir -p "$HOOK_BASE/prepare/begin" "$HOOK_BASE/release/end"

      sudo_append "$HOOK_BASE/prepare/begin/10-detach-nvidia.sh" "
        #!/usr/bin/env bash
        set -euo pipefail
        for dev in \$(lspci -Dnni | awk '/10de:/{print \$1}'); do
          devpath=\"/sys/bus/pci/devices/\$dev/driver\"
          if [[ -L \"\$devpath\" ]]; then
            echo \"\$dev\" > \"\$devpath/unbind\" || true
          fi
          echo vfio-pci > \"/sys/bus/pci/devices/\$dev/driver_override\" || true
          echo \"\$dev\" > /sys/bus/pci/drivers/vfio-pci/bind || true
        done"

      sudo_append "$HOOK_BASE/release/end/90-attach-nvidia.sh" "
        #!/usr/bin/env bash
        set -euo pipefail
        for dev in \$(lspci -Dnni | awk '/10de:/{print \$1}'); do
          echo \"\" > \"/sys/bus/pci/devices/\$dev/driver_override\" || true
          for drv in nvidia nouveau; do
            if [[ -d \"/sys/bus/pci/drivers/\$drv\" ]]; then
              echo \"\$dev\" > \"/sys/bus/pci/drivers/\$drv/bind\" || true
              break
            fi
          done
        done"

      sudo chmod +x "$HOOK_BASE/prepare/begin/10-detach-nvidia.sh" "$HOOK_BASE/release/end/90-attach-nvidia.sh"
      sudo systemctl restart libvirtd || true
    fi
  else
    info "No NVIDIA GPU detected. Skipping GPU passthrough prep; base virtualization stack is installed."
  fi

  if [[ $ENABLE_HUGEPAGES -eq 1 ]]; then
    info "Enabling transparent hugepages preference..."
    sudo_append "/etc/sysctl.d/99-hugepages.conf" "vm.nr_hugepages = 0"
    sudo_append "/sys/kernel/mm/transparent_hugepage/enabled" "always"
    sudo sysctl --system || true
  fi

  if [[ $NO_REBOOT_WARNING -eq 0 ]]; then
    echo
    warn "A reboot is recommended to apply IOMMU/vfio changes."
  fi

  info "Host ready for virt-manager."
}

# If executed directly, run the function
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  setup_host_virt_manager "$@"
fi
