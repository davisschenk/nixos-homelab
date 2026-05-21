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

  services.caddy.virtualHosts."sonarr.schenkenberger.dev" = {
    listenAddresses = [ "127.0.0.1" ];
    extraConfig = ''
      import authentik_forward_auth
      reverse_proxy localhost:${toString config.mylab.ports.sonarr}
    '';
  };

  services.caddy.virtualHosts."radarr.schenkenberger.dev" = {
    listenAddresses = [ "127.0.0.1" ];
    extraConfig = ''
      import authentik_forward_auth
      reverse_proxy localhost:${toString config.mylab.ports.radarr}
    '';
  };

  services.caddy.virtualHosts."prowlarr.schenkenberger.dev" = {
    listenAddresses = [ "127.0.0.1" ];
    extraConfig = ''
      import authentik_forward_auth
      reverse_proxy localhost:${toString config.mylab.ports.prowlarr}
    '';
  };

  services.caddy.virtualHosts."qbit.schenkenberger.dev" = {
    listenAddresses = [ "127.0.0.1" ];
    extraConfig = ''
      import authentik_forward_auth
      reverse_proxy localhost:${toString config.mylab.ports.qbittorrent}
    '';
  };

  systemd.services.sonarr.unitConfig.RequiresMountsFor = [ "/data/media" "/data/downloads" ];
  systemd.services.radarr.unitConfig.RequiresMountsFor = [ "/data/media" "/data/downloads" ];
  systemd.services.prowlarr.unitConfig.RequiresMountsFor = [ "/data/downloads" ];
  systemd.services.qbittorrent.unitConfig.RequiresMountsFor = [ "/data/downloads" ];

  environment.persistence."/persist" = {
    directories = [ "/var/lib/nixarr" ];
  };
}
