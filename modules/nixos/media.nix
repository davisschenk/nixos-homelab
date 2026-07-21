{ config, pkgs, ... }:
{
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      intel-media-driver
      intel-compute-runtime
    ];
  };

  services.jellyfin = {
    enable = true;
    openFirewall = false;
    hardwareAcceleration = {
      enable = true;
      device = "/dev/dri/renderD128";
    };
    forceEncodingConfig = true;
  };

  users.users.jellyfin.extraGroups = [
    "render"
    "video"
    "media"
  ];

  # Impermanence creates dirs as root:root; enforce jellyfin ownership.
  systemd.tmpfiles.rules = [
    "d /persist/var/cache/jellyfin 0700 jellyfin jellyfin -"
  ];

  environment.persistence."/persist" = {
    directories = [
      "/var/lib/jellyfin"
      { directory = "/var/cache/jellyfin"; user = "jellyfin"; group = "jellyfin"; mode = "0700"; }
    ];
  };
}
