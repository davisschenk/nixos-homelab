{ config, pkgs, ... }:
let
  dbipCity = import ../../modules/common/dbip-city.nix { inherit pkgs; };
in
{
  imports = [
    ../../modules/common/base.nix
    ../../modules/common/wireguard.nix
    ./disko.nix
  ];

  networking = {
    hostName = "estuary";
    useDHCP = true;
    enableIPv6 = false;
  };

  boot = {
    initrd.availableKernelModules = [
      "ahci"
      "sd_mod"
      "virtio_pci"
      "virtio_scsi"
    ];
    loader = {
      grub = {
        enable = true;
      };
    };
  };

  services.qemuGuest.enable = true;
  services.openssh.openFirewall = false;

  sops = {
    defaultSopsFile = ../../secrets/estuary.yaml;
    age.keyFile = "/var/lib/sops-nix/key.txt";
    secrets.wireguard_estuary_private_key.restartUnits = [ "wireguard-wg-estuary.service" ];
  };

  mylab.wireguard = {
    enable = true;
    role = "hub";
    address = "10.88.0.1/24";
    publicInterface = "ens3";
    privateKeyFile = config.sops.secrets.wireguard_estuary_private_key.path;
    peers = [
      {
        publicKey = "UhAhDVhIE4kDj2BPNp0JMAhie0geLUKV+4Zeg+Q8e3o=";
        allowedIPs = [ "10.88.0.2/32" ];
      }
      {
        publicKey = "+NBk1Qx4aWzoDYmglzddn0sMcSdQpovw2ilUa7p9fVQ=";
        allowedIPs = [ "10.88.0.3/32" ];
      }
    ];
  };

  services.prometheus.exporters.node = {
    enable = true;
    listenAddress = "10.88.0.1";
    port = 9100;
    extraFlags = [ "--collector.textfile.directory=/var/lib/node-exporter/textfile" ];
    enabledCollectors = [
      "cpu"
      "diskstats"
      "filesystem"
      "loadavg"
      "meminfo"
      "netdev"
      "pressure"
      "processes"
      "systemd"
      "textfile"
      "time"
    ];
  };

  services.prometheus.exporters.fail2ban = {
    enable = true;
    listenAddress = "10.88.0.1";
    port = 9191;
    openFirewall = false;
  };

  networking.firewall.interfaces.wg-estuary.allowedTCPPorts = [ 9191 ];

  systemd.services.estuary-ssh-probe-metrics = {
    description = "Export public SSH probe metrics";
    after = [ "firewall.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "estuary-ssh-probe-metrics" ''
        set -euo pipefail
        directory=/var/lib/node-exporter/textfile
        output="$directory/estuary-ssh-probes.prom"
        temporary="$output.tmp"
        packets=$(${pkgs.nftables}/bin/nft --json list counter inet estuary-observability public_ssh_probes | ${pkgs.jq}/bin/jq -r '.nftables[] | select(.counter.name == "public_ssh_probes") | .counter.packets')
        ${pkgs.coreutils}/bin/printf '# HELP estuary_public_ssh_probe_packets_total Public TCP port 22 connection attempts blocked by Estuary.\n# TYPE estuary_public_ssh_probe_packets_total counter\nestuary_public_ssh_probe_packets_total %s\n' "$packets" > "$temporary"
        ${pkgs.coreutils}/bin/mv "$temporary" "$output"
      '';
    };
  };

  systemd.timers.estuary-ssh-probe-metrics = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "1m";
      OnUnitActiveSec = "1m";
      Unit = "estuary-ssh-probe-metrics.service";
    };
  };

  systemd.tmpfiles.rules = [ "d /var/lib/node-exporter/textfile 0755 root root -" ];

  services.fail2ban = {
    enable = true;
    maxretry = 3;
    bantime = "1h";
  };

  services.vector = {
    enable = true;
    journaldAccess = true;
    settings = {
      enrichment_tables.dbip_city = {
        type = "mmdb";
        path = "${dbipCity}";
      };
      sources.systemd_journal.type = "journald";
      transforms.estuary_ssh_probes = {
        type = "remap";
        inputs = [ "systemd_journal" ];
        source = ''
          message = string(.message) ?? ""
          if !starts_with(message, "estuary-public-ssh-probe ") { abort }
          fields = parse_regex!(message, r'SRC=(?P<source_ip>[0-9a-fA-F:.]+)')
          .source_ip = fields.source_ip
          location = get_enrichment_table_record!("dbip_city", { "ip": .source_ip })
          .latitude = float!(location.location.latitude)
          .longitude = float!(location.location.longitude)
          .city = string(location.city.names.en) ?? "Unknown"
          .country = string(location.country.names.en) ?? "Unknown"
          .country_code = string(location.country.iso_code) ?? "Unknown"
        '';
      };
      sinks.loki_ssh_probes = {
        type = "loki";
        inputs = [ "estuary_ssh_probes" ];
        endpoint = "http://10.88.0.2:3100";
        encoding.codec = "json";
        labels = {
          job = "estuary-ssh-probes";
          host = "estuary";
        };
        buffer = {
          type = "disk";
          max_size = 268435488;
          when_full = "block";
        };
      };
      tests = [
        {
          name = "geolocate-public-ssh-probe";
          inputs = [
            {
              insert_at = "estuary_ssh_probes";
              type = "log";
              log_fields.message = "estuary-public-ssh-probe IN=ens3 SRC=8.8.8.8 DST=15.204.123.187 PROTO=TCP DPT=22";
            }
          ];
          outputs = [
            {
              extract_from = "estuary_ssh_probes";
              conditions = [
                {
                  type = "vrl";
                  source = ''
                    assert_eq!(.source_ip, "8.8.8.8")
                    assert!(is_float(.latitude))
                    assert!(is_float(.longitude))
                    assert!(is_string(.country_code))
                  '';
                }
              ];
            }
          ];
        }
      ];
    };
  };

  environment.systemPackages = [ pkgs.wireguard-tools ];

  system.stateVersion = "25.05";
}
