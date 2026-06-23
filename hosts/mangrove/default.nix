{ ... }:
{
  imports = [
    ./hardware-configuration.nix
    ./disko.nix
  ];

  networking.hostName = "mangrove";

  boot = {
    loader = {
      systemd-boot = {
        enable = true;
        configurationLimit = 5;
      };
      efi.canTouchEfiVariables = true;
    };
    zfs.forceImportRoot = false;
    initrd.systemd.emergencyAccess = true;
    # AMD Radeon 540/550 (01:00.0) + Baffin HDMI audio (01:00.1) — passed to Windows VM
    extraModprobeConfig = "options vfio-pci ids=1002:699f,1002:aae0";
  };

  system.stateVersion = "25.05";
}
