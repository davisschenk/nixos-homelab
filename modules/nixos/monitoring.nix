{
  config,
  pkgs,
  lib,
  ...
}:
let
  p = config.mylab.ports;

  # Extract key to /run so LoadCredential can access it without sops secrets.
  mkArrKeyExtractor = name: configPath: {
    "exportarr-${name}-key" = {
      description = "Extract ${name} API key for exportarr";
      after = [ "${name}.service" ];
      requires = [ "${name}.service" ];
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
  # File provider ensures secret never enters world-readable Nix store.
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
      ruleFiles = [
        (pkgs.writeText "estuary-alerts.yml" ''
          groups:
            - name: estuary
              rules:
                - alert: EstuaryDown
                  expr: up{job="estuary"} == 0
                  for: 5m
                  labels:
                    severity: critical
                  annotations:
                    summary: estuary node exporter is unreachable
                - alert: EstuaryIngressDown
                  expr: probe_success{job="estuary-ingress"} == 0
                  for: 5m
                  labels:
                    severity: critical
                  annotations:
                    summary: public estuary ingress is unreachable
                - alert: EstuaryWireGuardHandshakeStale
                  expr: time() - wireguard_latest_handshake_seconds{peer="estuary"} > 180
                  for: 5m
                  labels:
                    severity: warning
                  annotations:
                    summary: mangrove has no recent estuary WireGuard handshake
                - alert: EstuaryFail2banExporterDown
                  expr: up{job="estuary-fail2ban"} == 0
                  for: 5m
                  labels:
                    severity: warning
                  annotations:
                    summary: estuary fail2ban exporter is unreachable
                - alert: EstuaryLogShippingDown
                  expr: node_systemd_unit_state{job="estuary",name="vector.service",state="active"} == 0
                  for: 5m
                  labels:
                    severity: warning
                  annotations:
                    summary: estuary SSH probe log shipping is down
                - alert: CloudflareTunnelDown
                  expr: node_systemd_unit_state{name="cloudflared.service",state="active"} == 0
                  for: 5m
                  labels:
                    severity: critical
                  annotations:
                    summary: cloudflared is not active
        '')
      ];

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
          job_name = "estuary";
          static_configs = [ { targets = [ "10.88.0.1:${toString p.nodeExporter}" ]; } ];
        }
        {
          job_name = "estuary-fail2ban";
          static_configs = [ { targets = [ "10.88.0.1:${toString p.fail2banExporter}" ]; } ];
        }
        {
          job_name = "estuary-ingress";
          metrics_path = "/probe";
          params.module = [ "tcp_connect" ];
          static_configs = [ { targets = [ "play.schenkenberger.dev:2022" ]; } ];
          relabel_configs = [
            {
              source_labels = [ "__address__" ];
              target_label = "__param_target";
            }
            {
              source_labels = [ "__param_target" ];
              target_label = "instance";
            }
            {
              target_label = "__address__";
              replacement = "127.0.0.1:9115";
            }
          ];
        }
        {
          job_name = "authentik";
          static_configs = [
            {
              targets = [
                "localhost:${toString p.authentikMetrics}"
                "localhost:${toString p.authentikOutpostMetrics}"
              ];
            }
          ];
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
        {
          job_name = "fail2ban";
          static_configs = [ { targets = [ "localhost:${toString p.fail2banExporter}" ]; } ];
        }
        # Jellyfin lacks built-in metrics; skip to avoid scrape errors.
      ];

      exporters.node = {
        enable = true;
        listenAddress = "127.0.0.1";
        port = p.nodeExporter;
        extraFlags = [ "--collector.textfile.directory=/var/lib/node-exporter/textfile" ];
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
          "textfile"
        ];
      };

      exporters.blackbox = {
        enable = true;
        listenAddress = "127.0.0.1";
        port = 9115;
        configFile = ./monitoring-blackbox.yml;
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
          disable_login_form = true;
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
          {
            name = "Loki";
            type = "loki";
            url = "http://localhost:${toString p.loki}";
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
    {
      wireguard-estuary-metrics = {
        description = "Export estuary WireGuard handshake metrics";
        after = [ "wireguard-wg-estuary.service" ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = pkgs.writeShellScript "wireguard-estuary-metrics" ''
            set -euo pipefail
            output=/var/lib/node-exporter/textfile/wireguard-estuary.prom
            latest=$(${pkgs.wireguard-tools}/bin/wg show wg-estuary latest-handshakes | ${pkgs.gawk}/bin/awk '$1 == "fX/cDl6eNrzE93glQ8VOq+6YUfJxPgEArXSh3NY0Ox0=" { print $2 }')
            ${pkgs.coreutils}/bin/printf 'wireguard_latest_handshake_seconds{peer="estuary"} %s\n' "''${latest:-0}" > "$output"
          '';
        };
      };
    }
  ];

  systemd.timers.wireguard-estuary-metrics = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "1m";
      OnUnitActiveSec = "1m";
      Unit = "wireguard-estuary-metrics.service";
    };
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/node-exporter/textfile 0755 root root -"
  ];

  environment.persistence."/persist" = {
    directories = [
      "/var/lib/prometheus2"
      "/var/lib/grafana"
    ];
  };
}
