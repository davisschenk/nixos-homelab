{ config, pkgs, lib, ... }:
let
  p = config.mylab.ports;

  # Extract an *arr API key from its config.xml at service startup.
  # Writes the plain key to /run/exportarr-keys/<name> so that exportarr's
  # LoadCredential mechanism can read it without touching sops secrets.
  mkArrKeyExtractor = name: configPath: {
    "exportarr-${name}-key" = {
      description = "Extract ${name} API key for exportarr";
      before = [ "prometheus-exportarr-${name}-exporter.service" ];
      wantedBy = [ "prometheus-exportarr-${name}-exporter.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "extract-${name}-key" ''
          install -d -m 700 /run/exportarr-keys
          ${pkgs.xmlstarlet}/bin/xmlstarlet sel -t -v "/Config/ApiKey" \
            "${configPath}" > /run/exportarr-keys/${name}
          chmod 600 /run/exportarr-keys/${name}
        '';
      };
    };
  };
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
      listenAddress = "127.0.0.1";
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
        {
          job_name = "sonarr";
          static_configs = [ { targets = [ "localhost:${toString p.exportarrSonarr}" ]; } ];
        }
        {
          job_name = "radarr";
          static_configs = [ { targets = [ "localhost:${toString p.exportarrRadarr}" ]; } ];
        }
        {
          job_name = "prowlarr";
          static_configs = [ { targets = [ "localhost:${toString p.exportarrProwlarr}" ]; } ];
        }
        # Jellyfin does not expose Prometheus metrics without a separate plugin;
        # removed to avoid scrape errors.
      ];

      exporters.node = {
        enable = true;
        listenAddress = "127.0.0.1";
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

      exporters.exportarr-sonarr = {
        enable = true;
        listenAddress = "127.0.0.1";
        port = p.exportarrSonarr;
        url = "http://127.0.0.1:${toString p.sonarr}";
        apiKeyFile = "/run/exportarr-keys/sonarr";
      };

      exporters.exportarr-radarr = {
        enable = true;
        listenAddress = "127.0.0.1";
        port = p.exportarrRadarr;
        url = "http://127.0.0.1:${toString p.radarr}";
        apiKeyFile = "/run/exportarr-keys/radarr";
      };

      exporters.exportarr-prowlarr = {
        enable = true;
        listenAddress = "127.0.0.1";
        port = p.exportarrProwlarr;
        url = "http://127.0.0.1:${toString p.prowlarr}";
        apiKeyFile = "/run/exportarr-keys/prowlarr";
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
        dashboards.settings.providers = [
          {
            name = "default";
            options.path = ./grafana/dashboards;
          }
        ];
      };
    };

  };

  systemd.services = lib.mkMerge [
    (mkArrKeyExtractor "sonarr" "/var/lib/nixarr/sonarr/config.xml")
    (mkArrKeyExtractor "radarr" "/var/lib/nixarr/radarr/config.xml")
    (mkArrKeyExtractor "prowlarr" "/var/lib/nixarr/prowlarr/config.xml")
  ];

  environment.persistence."/persist" = {
    directories = [
      "/var/lib/prometheus2"
      "/var/lib/grafana"
    ];
  };
}
