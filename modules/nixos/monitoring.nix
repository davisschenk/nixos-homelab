{ config, ... }:
let
  p = config.mylab.ports;
in
{
  # Grafana secret key managed via SOPS. The file contains just the raw key
  # string (no YAML structure). Use Grafana's file provider so the key never
  # lands in the world-readable Nix store.
  sops.secrets."grafana_secret_key" = {
    sopsFile = ../../secrets/grafana.yaml;
    owner = "grafana";
  };

  services.prometheus = {
    enable = true;
    port = p.prometheus;
    retentionTime = "30d";

    scrapeConfigs = [
      {
        job_name = "prometheus";
        static_configs = [ { targets = [ "localhost:${toString p.prometheus}" ]; } ];
      }
      {
        job_name = "node";
        static_configs = [ { targets = [ "localhost:${toString p.nodeExporter}" ]; } ];
      }
      {
        # authentik-nix worker exposes metrics on IPv6 loopback port 9301
        job_name = "authentik";
        static_configs = [ { targets = [ "[::1]:9301" ]; } ];
      }
      # Jellyfin does not expose Prometheus metrics without a separate plugin;
      # removed to avoid scrape errors.
    ];

    exporters.node = {
      enable = true;
      enabledCollectors = [
        "systemd"
        "processes"
        "filesystem"
        "diskstats"
        "meminfo"
        "cpu"
        "loadavg"
        "netdev"
      ];
    };
  };

  services.grafana = {
    enable = true;
    settings = {
      server = {
        http_addr = "127.0.0.1";
        http_port = p.grafana;
        root_url = "https://grafana.schenkenberger.dev/";
      };
      analytics.reporting_enabled = false;
      security.secret_key = "$__file{${config.sops.secrets."grafana_secret_key".path}}";
    };

    provision = {
      enable = true;
      datasources.settings.datasources = [
        {
          name = "Prometheus";
          type = "prometheus";
          url = "http://localhost:${toString p.prometheus}";
          isDefault = true;
        }
      ];
    };
  };

  services.caddy.virtualHosts."grafana.schenkenberger.dev" = {
    listenAddresses = [ "127.0.0.1" ];
    extraConfig = ''
      import authentik_forward_auth
      reverse_proxy localhost:${toString p.grafana}
    '';
  };

  environment.persistence."/persist" = {
    directories = [
      "/var/lib/prometheus2"
      "/var/lib/grafana"
    ];
  };
}
