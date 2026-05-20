{ lib, ... }:
{
  options.mylab.ports = {
    actual = lib.mkOption {
      type = lib.types.port;
      default = 5006;
    };
    grafana = lib.mkOption {
      type = lib.types.port;
      default = 3000;
    };
    prometheus = lib.mkOption {
      type = lib.types.port;
      default = 9090;
    };
    nodeExporter = lib.mkOption {
      type = lib.types.port;
      default = 9100;
    };
    jellyfin = lib.mkOption {
      type = lib.types.port;
      default = 8096;
    };
    copyparty = lib.mkOption {
      type = lib.types.port;
      default = 3923;
    };
    romm = lib.mkOption {
      type = lib.types.port;
      default = 8888;
    };
    mealie = lib.mkOption {
      type = lib.types.port;
      default = 9925;
    };
    authentik = lib.mkOption {
      type = lib.types.port;
      default = 9000;
    };
    pelican = lib.mkOption {
      type = lib.types.port;
      default = 8000;
    };
    sonarr = lib.mkOption {
      type = lib.types.port;
      default = 8989;
    };
    radarr = lib.mkOption {
      type = lib.types.port;
      default = 7878;
    };
    prowlarr = lib.mkOption {
      type = lib.types.port;
      default = 9696;
    };
    qbittorrent = lib.mkOption {
      type = lib.types.port;
      default = 8080;
    };
    wings = lib.mkOption {
      type = lib.types.port;
      default = 8083;
    };
  };
}
