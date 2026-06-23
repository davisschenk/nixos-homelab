{ config, pkgs, ... }:
let
  setAuthExternal = stateDir: pkgs.writeShellScript "set-auth-external" ''
    config="${stateDir}/config.xml"
    if [ -f "$config" ]; then
      ${pkgs.xmlstarlet}/bin/xmlstarlet ed --inplace \
        -u "/Config/AuthenticationMethod" -v "External" \
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
      serviceConfig.ExecStartPre = [ (setAuthExternal "/var/lib/nixarr/sonarr") ];
    };
    radarr = {
      unitConfig.RequiresMountsFor = [ "/data/media" "/data/downloads" ];
      serviceConfig.ExecStartPre = [ (setAuthExternal "/var/lib/nixarr/radarr") ];
    };
    prowlarr = {
      unitConfig.RequiresMountsFor = [ "/data/downloads" ];
      serviceConfig.ExecStartPre = [ (setAuthExternal "/var/lib/nixarr/prowlarr") ];
    };
    qbittorrent.unitConfig.RequiresMountsFor = [ "/data/downloads" ];
  };

  environment.persistence."/persist" = {
    directories = [ "/var/lib/nixarr" ];
  };
}
