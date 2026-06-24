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

  sops.secrets."grafana_oauth_client_secret" = {
    sopsFile = ../../secrets/grafana.yaml;
    owner = "grafana";
  };

  services = {
    prometheus = {
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
          job_name = "authentik";
          static_configs = [ { targets = [ "localhost:9300" "localhost:9301" ]; } ];
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
          "hwmon"
          "time"
          "pressure"
        ];
      };
    };

    grafana = {
      enable = true;
      settings = {
        server = {
          http_addr = "127.0.0.1";
          http_port = p.grafana;
          root_url = "https://grafana.schenkenberger.dev/";
        };
        analytics.reporting_enabled = false;
        security.secret_key = "$__file{${config.sops.secrets."grafana_secret_key".path}}";

        "auth" = {
          signout_redirect_url = "https://auth.schenkenberger.dev/application/o/grafana/end-session/";
          oauth_auto_login = true;
        };

        "auth.generic_oauth" = {
          enabled = true;
          name = "authentik";
          allow_sign_up = true;
          client_id = "grafana";
          client_secret = "$__file{${config.sops.secrets."grafana_oauth_client_secret".path}}";
          scopes = "openid profile email groups";
          auth_url = "https://auth.schenkenberger.dev/application/o/authorize/";
          token_url = "https://auth.schenkenberger.dev/application/o/token/";
          api_url = "https://auth.schenkenberger.dev/application/o/userinfo/";
          role_attribute_path = "contains(groups, 'grafana-admin') && 'Admin' || contains(groups, 'grafana-viewer') && 'Viewer' || 'Viewer'";
          allow_assign_grafana_admin = true;
        };
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

  };

  environment.persistence."/persist" = {
    directories = [
      "/var/lib/prometheus2"
      "/var/lib/grafana"
    ];
  };
}
