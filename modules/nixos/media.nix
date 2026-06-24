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
  };

  users.users.jellyfin.extraGroups = [
    "render"
    "video"
    "media"
  ];

  environment.persistence."/persist" = {
    directories = [ "/var/lib/jellyfin" ];
  };
}
