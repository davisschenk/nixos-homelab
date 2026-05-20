{ pkgs, ... }:
{
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      intel-media-driver # iHD driver for Gen8+ (UHD 770)
      intel-compute-runtime # OpenCL support
    ];
  };

  services.jellyfin = {
    enable = true;
    openFirewall = false; # Caddy handles access
  };

  users.users.jellyfin.extraGroups = [
    "render"
    "video"
  ];
}
