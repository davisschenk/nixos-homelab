{ config, ... }:
let
  p = config.mylab.ports;
in
{
  # ---------------------------------------------------------------------------
  # Suricata — network IDS watching the physical LAN interface.
  # Runs in IDS (AF_PACKET) mode; writes EVE JSON to /var/log/suricata/eve.json
  # which Vector picks up and ships to Loki.
  # ---------------------------------------------------------------------------
  services.suricata = {
    enable = true;
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
              { dns = {}; }
              { http = { extended = true; }; }
              { tls = { extended = true; }; }
              { flow = {}; }
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

  # ---------------------------------------------------------------------------
  # Loki — log aggregation backend. Listens on localhost only.
  # ---------------------------------------------------------------------------
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
        ingestion_rate_mb = 4;
        ingestion_burst_size_mb = 8;
      };
      compactor = {
        retention_enabled = true;
        delete_request_store = "filesystem";
      };
      ruler.alertmanager_url = "http://localhost:9093";
    };
  };

  # ---------------------------------------------------------------------------
  # Vector — log shipping pipeline.
  #   Source 1: systemd journal  → labels: {job="systemd"}
  #   Source 2: Suricata EVE JSON → labels: {job="suricata", event_type=<type>}
  # Both sinks push to local Loki via HTTP.
  # ---------------------------------------------------------------------------
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
          read_from = "beginning";
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
            .event_type = string(.event_type) ?? "unknown"
          '';
        };

        journal_labels = {
          type = "remap";
          inputs = [ "systemd_journal" ];
          source = ''
            .unit = string(._SYSTEMD_UNIT) ?? string(.SYSLOG_IDENTIFIER) ?? "unknown"
          '';
        };
      };

      sinks = {
        loki_suricata = {
          type = "loki";
          inputs = [ "suricata_labels" ];
          endpoint = "http://127.0.0.1:${toString p.loki}";
          encoding.codec = "json";
          labels = {
            job = "suricata";
            host = "mangrove";
            event_type = "{{ event_type }}";
          };
        };

        loki_journal = {
          type = "loki";
          inputs = [ "journal_labels" ];
          endpoint = "http://127.0.0.1:${toString p.loki}";
          encoding.codec = "json";
          labels = {
            job = "systemd";
            host = "mangrove";
            unit = "{{ unit }}";
          };
        };
      };
    };
  };

  # ---------------------------------------------------------------------------
  # Persistence — survive impermanence reboots
  # ---------------------------------------------------------------------------

  # Impermanence creates bind-mount source dirs as root:root 0755.
  # Loki runs as the 'loki' system user and needs to own its state dir.
  # Suricata runs as 'suricata'; its module sets up /var/log/suricata itself,
  # but we ensure the persist source dir is also correctly owned.
  systemd.tmpfiles.rules = [
    "d /persist/var/lib/loki 0700 loki loki -"
    "d /persist/var/log/suricata 0755 suricata suricata -"
  ];

  environment.persistence."/persist" = {
    directories = [
      { directory = "/var/lib/loki"; user = "loki"; group = "loki"; mode = "0700"; }
      { directory = "/var/log/suricata"; user = "suricata"; group = "suricata"; mode = "0755"; }
    ];
  };
}
