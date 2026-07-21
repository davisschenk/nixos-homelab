{ config, ... }:
let
  p = config.mylab.ports;
in
{
  # Suricata: alerting-only IDS to avoid dashboard noise and reduce Loki storage consumption
  services.suricata = {
    enable = true;
    disabledRules = [
      # modbus / dnp3 app-layer protocols not compiled into this Suricata build
      "2009286"
      "2250001" "2250002" "2250003" "2250005" "2250006"
      "2250007" "2250008" "2250009"
      "2270000" "2270001" "2270002" "2270003" "2270004"
      "2270005" "2270006"
    ];
    settings = {
      "af-packet" = [
        {
          interface = "enp3s0";
          "cluster-type" = "cluster_flow";
          defrag = true;
        }
      ];

      outputs = [
        {
          "eve-log" = {
            enabled = true;
            filetype = "regular";
            filename = "/var/log/suricata/eve.json";
            types = [
              { alert = { payload = false; packet = false; }; }
            ];
          };
        }
        { fast = { enabled = false; filename = "fast.log"; }; }
      ];

      logging = {
        "default-log-level" = "notice";
        outputs = {
          syslog = {
            enable = true;
            facility = "local5";
          };
          console.enable = false;
        };
      };

      "detection-engine" = {
        profile = "medium";
        "rule-reload" = true;
      };
    };
  };

  services.loki = {
    enable = true;
    configuration = {
      auth_enabled = false;
      server = {
        http_listen_address = "127.0.0.1";
        http_listen_port = p.loki;
        log_level = "warn";
      };
      common = {
        instance_addr = "127.0.0.1";
        path_prefix = "/var/lib/loki";
        storage.filesystem = {
          chunks_directory = "/var/lib/loki/chunks";
          rules_directory = "/var/lib/loki/rules";
        };
        replication_factor = 1;
        ring.kvstore.store = "inmemory";
      };
      query_range.results_cache.cache.embedded_cache = {
        enabled = true;
        max_size_mb = 100;
      };
      schema_config.configs = [
        {
          from = "2024-01-01";
          store = "tsdb";
          object_store = "filesystem";
          schema = "v13";
          index = {
            prefix = "index_";
            period = "24h";
          };
        }
      ];
      limits_config = {
        retention_period = "30d";
        reject_old_samples = true;
        reject_old_samples_max_age = "168h";
        ingestion_rate_mb = 8;
        ingestion_burst_size_mb = 16;
      };
      compactor = {
        retention_enabled = true;
        delete_request_store = "filesystem";
      };
      ruler.alertmanager_url = "http://localhost:9093";
    };
  };

  services.vector = {
    enable = true;
    journaldAccess = true;
    settings = {
      sources = {
        systemd_journal = {
          type = "journald";
          include_units = [];
        };

        suricata_eve = {
          type = "file";
          include = [ "/var/log/suricata/eve.json" ];
          read_from = "end";
        };
      };

      transforms = {
        parse_suricata = {
          type = "remap";
          inputs = [ "suricata_eve" ];
          source = ''
            . = parse_json!(string!(.message))
          '';
        };

        suricata_labels = {
          type = "remap";
          inputs = [ "parse_suricata" ];
          source = ''
            # EVE file persists across reboots; filter to alerts only to avoid historical noise
            if .event_type != "alert" { abort }

            # Low-cardinality labels only; IPs/signatures in body avoid unbounded streams
            .alert_severity = string(.alert.severity) ?? "unknown"
            .alert_category = string(.alert.category) ?? "unknown"
            .alert_signature = string(.alert.signature) ?? "unknown"
            .alert_signature_id = string(.alert.signature_id) ?? "unknown"
          '';
        };

        journal_labels = {
          type = "remap";
          inputs = [ "systemd_journal" ];
          source = ''
            .unit = string(._SYSTEMD_UNIT) ?? string(.SYSLOG_IDENTIFIER) ?? "unknown"
          '';
        };

        parse_f2b_ban = {
          type = "remap";
          inputs = [ "systemd_journal" ];
          source = ''
            .unit = string(._SYSTEMD_UNIT) ?? string(.SYSLOG_IDENTIFIER) ?? "unknown"
            if .unit != "fail2ban.service" { abort }
            msg = string(.MESSAGE) ?? ""
            m, err = parse_regex(msg, r'^\S+\s+\[(?P<jail>[^\]]+)\]\s+Ban\s+(?P<ip>[\d\.a-fA-F:]+)')
            if err != null {
              m, err = parse_regex(msg, r'Ban\s+(?P<ip>[\d\.a-fA-F:]+)')
              if err != null { abort }
              .jail = "unknown"
            } else {
              .jail = string(m.jail) ?? "unknown"
            }
            .banned_ip = string(m.ip) ?? ""
            if .banned_ip == "" { abort }
          '';
        };
      };

      sinks = {
        loki_suricata = {
          type = "loki";
          inputs = [ "suricata_labels" ];
          endpoint = "http://127.0.0.1:${toString p.loki}";
          encoding.codec = "json";
          # Safe to allow unconfined templates; values from trusted remap transforms, not raw input
          dangerously_allow_unconfined_template_resolution = true;
          labels = {
            job = "suricata";
            host = "mangrove";
            severity = "{{ alert_severity }}";
            category = "{{ alert_category }}";
          };
        };

        loki_f2b_bans = {
          type = "loki";
          inputs = [ "parse_f2b_ban" ];
          endpoint = "http://127.0.0.1:${toString p.loki}";
          encoding.codec = "json";
          dangerously_allow_unconfined_template_resolution = true;
          labels = {
            job = "fail2ban-bans";
            host = "mangrove";
            jail = "{{ jail }}";
            banned_ip = "{{ banned_ip }}";
          };
        };

        loki_journal = {
          type = "loki";
          inputs = [ "journal_labels" ];
          endpoint = "http://127.0.0.1:${toString p.loki}";
          encoding.codec = "json";
          dangerously_allow_unconfined_template_resolution = true;
          labels = {
            job = "systemd";
            host = "mangrove";
            unit = "{{ unit }}";
          };
        };
      };
    };
  };

  services.fail2ban = {
    enable = true;
    maxretry = 5;
    bantime = "1h";
    bantime-increment = {
      enable = true;
      multipliers = "1 2 4 8 16 32 64";
      maxtime = "168h";
      overalljails = true;
    };
    ignoreIP = [
      "127.0.0.0/8"
      "10.0.0.0/8"
      "192.168.0.0/16"
    ];
    jails = {
      sshd = {
        settings = {
          enabled = true;
          backend = "systemd";
          filter = "sshd";
          maxretry = 3;
          bantime = "1h";
        };
      };
    };
  };

  services.prometheus.exporters.fail2ban = {
    enable = true;
    port = p.fail2banExporter;
    openFirewall = false;
  };

  # Impermanence creates dirs as root; services need ownership fixed
  # (Loki: 'loki' user; Suricata: 'suricata' user; fail2ban: root)
  systemd.tmpfiles.rules = [
    "d /persist/var/lib/loki 0700 loki loki -"
    "d /persist/var/log/suricata 0755 suricata suricata -"
    "d /persist/var/lib/fail2ban 0750 root root -"
  ];

  environment.persistence."/persist" = {
    directories = [
      { directory = "/var/lib/loki"; user = "loki"; group = "loki"; mode = "0700"; }
      { directory = "/var/log/suricata"; user = "suricata"; group = "suricata"; mode = "0755"; }
      { directory = "/var/lib/fail2ban"; user = "root"; group = "root"; mode = "0750"; }
    ];
  };
}
