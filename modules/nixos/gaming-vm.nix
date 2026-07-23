{ config, pkgs, lib, ... }:
{
  boot.kernelParams = [
    "intel_iommu=on"
    "iommu=pt"
  ];
  # vfio_virqfd was merged into the vfio module in Linux 6.2; omit it here
  boot.kernelModules = [
    "vfio"
    "vfio_iommu_type1"
    "vfio_pci"
  ];

  virtualisation.libvirtd = {
    enable = true;
    qemu = {
      # qemu_kvm saves disk space; KVM-only is fine on native x86_64
      package = pkgs.qemu_kvm;
      runAsRoot = false;
      # swtpm provides emulated TPM 2.0 (required by Windows 11)
      swtpm.enable = true;
      # OVMF is now bundled with QEMU — no separate ovmf option needed
    };
  };

  programs.virt-manager.enable = true;

  systemd.services.libvirtd.unitConfig.RequiresMountsFor = [ "/data/vm" ];

  # Set NODATACOW on /data/vm so VM disk images bypass btrfs CoW and checksums.
  systemd.tmpfiles.rules = [
    "v /data/vm 0755 root root - --nocow"
  ];

  environment.persistence."/persist" = {
    directories = [ "/var/lib/libvirt" ];
    # libvirtd encrypts its secrets store with this systemd credential key;
    # without persisting it, the key is unreachable after every root wipe
    # and libvirtd fails to start (243/CREDENTIALS).
    files = [ "/var/lib/systemd/credential.secret" ];
  };
}
