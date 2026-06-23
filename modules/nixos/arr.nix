{ config, ... }:
{
  sops.secrets."vpn_wg_conf" = {
    sopsFile = ../../secrets/vpn.yaml;
  };

  nixarr = {
    enable = true;
    mediaDir = "/data/media";
    stateDir = "/var/lib/nixarr";

    vpn = {
      enable = true;
      wgConf = config.sops.secrets."vpn_wg_conf".path;
    };

    sonarr.enable = true;
    radarr.enable = true;
    prowlarr.enable = true;

    qbittorrent = {
      enable = true;
      stateDir = "/data/downloads/.qbittorrent";
      vpn.enable = true;
      qui.enable = false;
      webuiPort = config.mylab.ports.qbittorrent;
    };
  };

  systemd.services = {
    sonarr.unitConfig.RequiresMountsFor = [ "/data/media" "/data/downloads" ];
    radarr.unitConfig.RequiresMountsFor = [ "/data/media" "/data/downloads" ];
    prowlarr.unitConfig.RequiresMountsFor = [ "/data/downloads" ];
    qbittorrent.unitConfig.RequiresMountsFor = [ "/data/downloads" ];
  };

  environment.persistence."/persist" = {
    directories = [ "/var/lib/nixarr" ];
  };
}
