{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.mylab.wireguard;
  inherit (lib) mkIf mkOption types;
  ingress = builtins.fromJSON (builtins.readFile ../../infra/ingress.json);
  indexedIngress = lib.imap0 (index: entry: entry // { inherit index; }) ingress;
  tcpIngress = builtins.filter (entry: entry.protocol == "tcp") ingress;
  udpIngress = builtins.filter (entry: entry.protocol == "udp") ingress;
  portRanges = entries: map (entry: { inherit (entry) from to; }) entries;
  nftPort =
    entry:
    if entry.from == entry.to then
      toString entry.from
    else
      "${toString entry.from}-${toString entry.to}";
  rangesDisjoint = lib.all (
    left:
    lib.all (
      right:
      left.index >= right.index
      || left.protocol != right.protocol
      || left.to < right.from
      || right.to < left.from
    ) indexedIngress
  ) indexedIngress;
  peerType = types.submodule {
    options = {
      publicKey = mkOption { type = types.str; };
      allowedIPs = mkOption { type = types.listOf types.str; };
      endpoint = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
      persistentKeepalive = mkOption {
        type = types.nullOr types.int;
        default = null;
      };
    };
  };
  wireguardPeers = map (
    peer:
    {
      inherit (peer) publicKey allowedIPs;
    }
    // lib.optionalAttrs (peer.endpoint != null) { inherit (peer) endpoint; }
    // lib.optionalAttrs (peer.persistentKeepalive != null) { inherit (peer) persistentKeepalive; }
  ) cfg.peers;
  dnatRules = lib.concatMapStringsSep "\n" (
    entry:
    ''iifname "${cfg.publicInterface}" ${entry.protocol} dport ${nftPort entry} dnat to ${cfg.forwardTarget}''
  ) ingress;
in
{
  options.mylab.wireguard = {
    enable = lib.mkEnableOption "estuary WireGuard routing";
    role = mkOption {
      type = types.enum [
        "hub"
        "spoke"
      ];
    };
    interfaceName = mkOption {
      type = types.str;
      default = "wg-estuary";
    };
    address = mkOption { type = types.str; };
    listenPort = mkOption {
      type = types.port;
      default = 51820;
    };
    mtu = mkOption {
      type = types.int;
      default = 1380;
    };
    privateKeyFile = mkOption { type = types.str; };
    peers = mkOption {
      type = types.listOf peerType;
      default = [ ];
    };
    publicInterface = mkOption {
      type = types.nullOr types.str;
      default = null;
    };
    lanInterface = mkOption {
      type = types.nullOr types.str;
      default = null;
    };
    forwardTarget = mkOption {
      type = types.str;
      default = "10.88.0.2";
    };
    policyMark = mkOption {
      type = types.str;
      default = "0x88";
    };
    policyTable = mkOption {
      type = types.int;
      default = 51820;
    };
  };

  config = mkIf cfg.enable (
    lib.mkMerge [
      {
        assertions = [
          {
            assertion = lib.all (entry: builtins.match "^[a-z0-9-]+$" entry.name != null) ingress;
            message = "Ingress names must contain only lowercase letters, digits, and hyphens.";
          }
          {
            assertion =
              builtins.length (lib.unique (map (entry: entry.name) ingress)) == builtins.length ingress;
            message = "Ingress names must be unique.";
          }
          {
            assertion = lib.all (
              entry:
              builtins.elem entry.protocol [
                "tcp"
                "udp"
              ]
            ) ingress;
            message = "Ingress protocols must be tcp or udp.";
          }
          {
            assertion = lib.all (entry: entry.target == "mangrove") ingress;
            message = "Ingress targets must be mangrove.";
          }
          {
            assertion = lib.all (entry: entry.from >= 1 && entry.from <= entry.to && entry.to <= 65535) ingress;
            message = "Ingress ports must be ordered and between 1 and 65535.";
          }
          {
            assertion = rangesDisjoint;
            message = "Ingress ranges using the same protocol must not overlap.";
          }
          {
            assertion = cfg.role != "hub" || cfg.publicInterface != null;
            message = "WireGuard hubs require mylab.wireguard.publicInterface.";
          }
        ];

        networking.nftables.enable = true;
        networking.firewall.enable = true;

        networking.wireguard.interfaces.${cfg.interfaceName} = {
          ips = [ cfg.address ];
          inherit (cfg) privateKeyFile mtu;
          peers = wireguardPeers;
          allowedIPsAsRoutes = cfg.role == "hub";
          dynamicEndpointRefreshSeconds = 300;
        }
        // lib.optionalAttrs (cfg.role == "hub") { inherit (cfg) listenPort; }
        // lib.optionalAttrs (cfg.role == "spoke") {
          fwMark = "0x51820";
          preSetup = ''
            ${pkgs.iproute2}/bin/ip rule add priority 100 fwmark ${cfg.policyMark} lookup ${toString cfg.policyTable} 2>/dev/null || true
            ${pkgs.iproute2}/bin/ip route replace blackhole default table ${toString cfg.policyTable}
          '';
          postSetup = ''
            ${pkgs.iproute2}/bin/ip route replace default dev ${cfg.interfaceName} table ${toString cfg.policyTable}
          '';
          postShutdown = ''
            ${pkgs.iproute2}/bin/ip route replace blackhole default table ${toString cfg.policyTable}
          '';
        };
      }

      (mkIf (cfg.role == "hub") {
        boot.kernel.sysctl."net.ipv4.ip_forward" = 1;

        networking.firewall = {
          filterForward = true;
          allowedTCPPorts = [ 22 ];
          allowedUDPPorts = [ cfg.listenPort ];
          allowedTCPPortRanges = portRanges tcpIngress;
          allowedUDPPortRanges = portRanges udpIngress;
          extraForwardRules = ''
            iifname "${cfg.interfaceName}" oifname "${cfg.interfaceName}" ip saddr 10.88.0.3 ip daddr ${cfg.forwardTarget} accept
          '';
          interfaces.${cfg.interfaceName}.allowedTCPPorts = [
            22
            9100
          ];
        };

        networking.nftables.tables.estuary-ingress = {
          family = "ip";
          content = ''
            chain prerouting {
              type nat hook prerouting priority dstnat; policy accept;
              ${dnatRules}
            }
          '';
        };
      })

      (mkIf (cfg.role == "spoke") {
        boot.kernel.sysctl."net.ipv4.conf.all.src_valid_mark" = 1;

        networking.firewall = {
          checkReversePath = "loose";
          interfaces.${cfg.interfaceName} = {
            allowedTCPPorts = [ 22 ];
            allowedTCPPortRanges = portRanges tcpIngress;
            allowedUDPPortRanges = portRanges udpIngress;
          };
        };

        networking.nftables.tables.estuary-policy = {
          family = "inet";
          content = ''
            chain prerouting {
              type filter hook prerouting priority mangle; policy accept;
              iifname "${cfg.interfaceName}" ct mark set ${cfg.policyMark}
              ct direction reply ct mark ${cfg.policyMark} meta mark set ct mark
            }

            chain output {
              type route hook output priority mangle; policy accept;
              ct direction reply ct mark ${cfg.policyMark} meta mark set ct mark
            }
          '';
        };
      })

      (mkIf (cfg.role == "spoke" && cfg.lanInterface != null) {
        networking.firewall.interfaces.${cfg.lanInterface} = {
          allowedTCPPorts = [ 22 ];
          allowedTCPPortRanges = portRanges tcpIngress;
          allowedUDPPortRanges = portRanges udpIngress;
        };
      })
    ]
  );
}
