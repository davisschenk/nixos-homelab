{ inputs, ... }:
{
  imports = [
    ./hardware-configuration.nix
    ./disko.nix
  ];

  networking.hostName = "mangrove";

  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.configurationLimit = 5;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.zfs.forceImportRoot = false;

  # AMD Radeon 540/550 (01:00.0) + Baffin HDMI audio (01:00.1) — passed to Windows VM
  boot.extraModprobeConfig = "options vfio-pci ids=1002:699f,1002:aae0";

  system.stateVersion = "25.05";
}
