{ lib, ... }:
{
  options.mylab.ports = {
    actual = lib.mkOption {
      type = lib.types.port;
      default = 5006;
      description = "Actual Budget server listen port.";
    };
    grafana = lib.mkOption {
      type = lib.types.port;
      default = 3000;
      description = "Grafana dashboard listen port.";
    };
    prometheus = lib.mkOption {
      type = lib.types.port;
      default = 9090;
      description = "Prometheus metrics server listen port.";
    };
    nodeExporter = lib.mkOption {
      type = lib.types.port;
      default = 9100;
      description = "Prometheus node exporter listen port.";
    };
    jellyfin = lib.mkOption {
      type = lib.types.port;
      default = 8096;
      description = "Jellyfin media server HTTP listen port.";
    };
    copyparty = lib.mkOption {
      type = lib.types.port;
      default = 3923;
      description = "Copyparty file server listen port.";
    };
    romm = lib.mkOption {
      type = lib.types.port;
      default = 8888;
      description = "RomM ROM manager container host port.";
    };
    mealie = lib.mkOption {
      type = lib.types.port;
      default = 9925;
      description = "Mealie recipe manager listen port.";
    };
    authentik = lib.mkOption {
      type = lib.types.port;
      default = 9000;
      description = "Authentik SSO server listen port (HTTP).";
    };
    pelican = lib.mkOption {
      type = lib.types.port;
      default = 8000;
      description = "Pelican Panel nginx listen port (proxied from Caddy).";
    };
    sonarr = lib.mkOption {
      type = lib.types.port;
      default = 8989;
      description = "Sonarr TV series manager listen port.";
    };
    radarr = lib.mkOption {
      type = lib.types.port;
      default = 7878;
      description = "Radarr movie manager listen port.";
    };
    prowlarr = lib.mkOption {
      type = lib.types.port;
      default = 9696;
      description = "Prowlarr indexer manager listen port.";
    };
    qbittorrent = lib.mkOption {
      type = lib.types.port;
      default = 8080;
      description = "qBittorrent web UI listen port.";
    };
    wings = lib.mkOption {
      type = lib.types.port;
      default = 8083;
      description = "Pelican Wings daemon API listen port.";
    };
    jellyseerr = lib.mkOption {
      type = lib.types.port;
      default = 5055;
      description = "Jellyseerr request management container host port.";
    };
    frigate = lib.mkOption {
      type = lib.types.port;
      default = 5000;
      description = "Frigate NVR HTTP listen port.";
    };
    homeassistant = lib.mkOption {
      type = lib.types.port;
      default = 8123;
      description = "Home Assistant HTTP listen port.";
    };
  };
}
