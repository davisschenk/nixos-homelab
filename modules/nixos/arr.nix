{ config, pkgs, ... }:
let
  setAuthExternal = stateDir: pkgs.writeShellScript "set-auth-external" ''
    config="${stateDir}/config.xml"
    if [ -f "$config" ]; then
      # Idempotent: delete and recreate node to handle first boot and subsequent boots.
      ${pkgs.xmlstarlet}/bin/xmlstarlet ed --inplace \
        -d "/Config/AuthenticationMethod" \
        -s "/Config" -t elem -n "AuthenticationMethod" -v "External" \
        "$config"
    fi
  '';
in
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
    sonarr = {
      unitConfig.RequiresMountsFor = [ "/data/media" "/data/downloads" ];
      serviceConfig.ExecStartPre = [ (setAuthExternal config.nixarr.sonarr.stateDir) ];
    };
    radarr = {
      unitConfig.RequiresMountsFor = [ "/data/media" "/data/downloads" ];
      serviceConfig.ExecStartPre = [ (setAuthExternal config.nixarr.radarr.stateDir) ];
    };
    prowlarr = {
      unitConfig.RequiresMountsFor = [ "/data/downloads" ];
      serviceConfig.ExecStartPre = [ (setAuthExternal config.nixarr.prowlarr.stateDir) ];
    };
    qbittorrent.unitConfig.RequiresMountsFor = [ "/data/downloads" ];
  };

  # Workaround: nixarr omits webuiPort mapping when qui.enable=false.
  vpnNamespaces.wg.portMappings = [
    {
      from = config.mylab.ports.qbittorrent;
      to = config.mylab.ports.qbittorrent;
    }
  ];

  environment.persistence."/persist" = {
    directories = [ "/var/lib/nixarr" ];
  };
}
