{ config, ... }:
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
    port = 9090;
    retentionTime = "30d";

    scrapeConfigs = [
      {
        job_name = "node";
        static_configs = [{ targets = [ "localhost:9100" ]; }];
      }
      {
        job_name = "jellyfin";
        static_configs = [{ targets = [ "localhost:8096" ]; }];
        metrics_path = "/metrics";
      }
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
        http_port = 3000;
        root_url = "https://grafana.schenkenberger.dev";
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
          url = "http://localhost:9090";
          isDefault = true;
        }
      ];
    };
  };
}
