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
  ];

  services.caddy.virtualHosts."jellyfin.schenkenberger.dev" = {
    listenAddresses = [ "127.0.0.1" ];
    extraConfig = ''
      reverse_proxy localhost:${toString config.mylab.ports.jellyfin}
    '';
  };

  environment.persistence."/persist" = {
    directories = [ "/var/lib/jellyfin" ];
  };
}
