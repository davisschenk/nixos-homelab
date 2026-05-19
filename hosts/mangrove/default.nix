{ inputs, ... }:
{
  imports = [
    ./hardware-configuration.nix
  ];

  networking.hostName = "mangrove";

  # dGPU PCI IDs — fill in after running `lspci -nn | grep -i nvidia` (or AMD equivalent)
  # on first boot. Format: "XXXX:XXXX"
  # boot.extraModprobeConfig = "options vfio-pci ids=<GPU-ID>,<AUDIO-ID>";

  system.stateVersion = "25.05";
}
