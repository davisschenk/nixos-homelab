{ pkgs, ... }:
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

  networking.firewall.trustedInterfaces = [ "virbr0" ];

  systemd.services.libvirtd.unitConfig.RequiresMountsFor = [ "/data/vm" ];

  environment.etc."libvirt/qemu/windows.xml".source = ../../hosts/mangrove/vm/windows.xml;

  systemd.services.windows-vm-define = {
    description = "Define the Windows gaming VM";
    after = [ "libvirtd.service" ];
    requires = [ "libvirtd.service" ];
    wantedBy = [ "multi-user.target" ];
    restartTriggers = [ ../../hosts/mangrove/vm/windows.xml ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      ${pkgs.libvirt}/bin/virsh define /etc/libvirt/qemu/windows.xml
    '';
  };

  systemd.tmpfiles.rules = [
    "d /data/vm 0755 root root -"
  ];

  environment.persistence."/persist" = {
    directories = [ "/var/lib/libvirt" ];
    # libvirtd encrypts its secrets store with this systemd credential key;
    # without persisting it, the key is unreachable after every root wipe
    # and libvirtd fails to start (243/CREDENTIALS).
    files = [ "/var/lib/systemd/credential.secret" ];
  };
}
