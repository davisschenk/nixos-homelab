{ pkgs }:
let
  hubPrivateKey = pkgs.writeText "estuary-test-private-key" "EM771qebn0IpEzCLal33m1FCtUct93j6YGxA6yH582Y=";
  spokePrivateKey = pkgs.writeText "mangrove-test-private-key" "OCrNF0F118EjJ+p0hySUVvp6fwnHqm4iKlh2jZ9molg=";
  runnerPrivateKey = pkgs.writeText "runner-test-private-key" "CJ+fRjtZMegF6Sq3qTUyfSorxelhAuGRGA+rdaSsumc=";
  server = pkgs.writeText "estuary-ingress-server.py" ''
    import socket
    import sys
    import threading

    def tcp(port):
        sock = socket.socket()
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        sock.bind(("0.0.0.0", port))
        sock.listen()
        while True:
            connection, peer = sock.accept()
            connection.sendall(peer[0].encode())
            connection.close()

    def udp(host, port):
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.bind((host, port))
        while True:
            _, peer = sock.recvfrom(1024)
            sock.sendto(peer[0].encode(), peer)

    if sys.argv[1] == "container":
        tcp(25566)
    else:
        threading.Thread(target=tcp, args=(2022,), daemon=True).start()
        threading.Thread(target=tcp, args=(25565,), daemon=True).start()
        threading.Thread(target=udp, args=("10.88.0.2", 25565), daemon=True).start()
        threading.Event().wait()
  '';
  probe = pkgs.writeText "estuary-ingress-probe.py" ''
    import socket
    import sys

    protocol, host, port, expected = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4]
    if protocol == "tcp":
        with socket.create_connection((host, port), timeout=2) as sock:
            observed = sock.recv(1024).decode()
    else:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
            sock.settimeout(2)
            sock.sendto(b"source", (host, port))
            observed = sock.recvfrom(1024)[0].decode()
    if observed != expected:
        raise SystemExit(f"destination observed {observed}, expected {expected}")
  '';
in
{
  name = "estuary-ingress";

  nodes = {
    client = {
      virtualisation.vlans = [ 1 ];
      networking = {
        useDHCP = false;
        interfaces.eth1.ipv4.addresses = [
          {
            address = "192.0.2.2";
            prefixLength = 24;
          }
        ];
        defaultGateway = "192.0.2.1";
        firewall.enable = false;
      };
      system.stateVersion = "25.05";
    };

    estuary = {
      imports = [ ../modules/common/wireguard.nix ];
      virtualisation.vlans = [
        1
        2
      ];
      networking = {
        useDHCP = false;
        interfaces.eth1.ipv4.addresses = [
          {
            address = "192.0.2.1";
            prefixLength = 24;
          }
        ];
        interfaces.eth2.ipv4.addresses = [
          {
            address = "198.51.100.1";
            prefixLength = 24;
          }
        ];
      };
      mylab.wireguard = {
        enable = true;
        role = "hub";
        address = "10.88.0.1/24";
        privateKeyFile = "${hubPrivateKey}";
        publicInterface = "eth1";
        peers = [
          {
            publicKey = "AaFtDRPYtxhQCJ8EpbdN1vS7Va/W4P8/6ndrOut2YzA=";
            allowedIPs = [ "10.88.0.2/32" ];
          }
          {
            publicKey = "YVbKvMTRkurSRI/4KaOcDvw9iy7+QGuwJshTdfZo7Vo=";
            allowedIPs = [ "10.88.0.3/32" ];
          }
        ];
      };
      system.stateVersion = "25.05";
    };

    runner = {
      virtualisation.vlans = [ 1 ];
      networking = {
        useDHCP = false;
        interfaces.eth1.ipv4.addresses = [
          {
            address = "192.0.2.3";
            prefixLength = 24;
          }
        ];
        defaultGateway = "192.0.2.1";
        firewall.enable = false;
        wireguard.interfaces.wg-ci = {
          ips = [ "10.88.0.3/32" ];
          privateKeyFile = "${runnerPrivateKey}";
          peers = [
            {
              publicKey = "tnXmN42VSar/VkBjLG/KzOU9OFKHd9uIstlltOfollQ=";
              allowedIPs = [ "10.88.0.0/24" ];
              endpoint = "192.0.2.1:51820";
              persistentKeepalive = 25;
            }
          ];
        };
      };
      system.stateVersion = "25.05";
    };

    mangrove = {
      imports = [ ../modules/common/wireguard.nix ];
      virtualisation.vlans = [ 2 ];
      networking = {
        useDHCP = false;
        interfaces.eth1.ipv4.addresses = [
          {
            address = "198.51.100.2";
            prefixLength = 24;
          }
        ];
        defaultGateway = "198.51.100.254";
        firewall.filterForward = true;
      };
      boot.kernel.sysctl."net.ipv4.ip_forward" = 1;
      mylab.wireguard = {
        enable = true;
        role = "spoke";
        address = "10.88.0.2/24";
        privateKeyFile = "${spokePrivateKey}";
        peers = [
          {
            publicKey = "tnXmN42VSar/VkBjLG/KzOU9OFKHd9uIstlltOfollQ=";
            allowedIPs = [ "0.0.0.0/0" ];
            endpoint = "198.51.100.1:51820";
            persistentKeepalive = 25;
          }
        ];
      };
      networking.nftables.tables.test-container = {
        family = "ip";
        content = ''
          chain prerouting {
            type nat hook prerouting priority dstnat; policy accept;
            iifname "wg-estuary" tcp dport 25566 dnat to 172.18.0.2
          }
        '';
      };
      systemd.services.ingress-test = {
        wantedBy = [ "multi-user.target" ];
        wants = [ "network-online.target" ];
        after = [ "network-online.target" ];
        serviceConfig.ExecStart = "${pkgs.python3}/bin/python ${server} host";
      };
      systemd.services.container-ingress-test = {
        wantedBy = [ "multi-user.target" ];
        wants = [ "network-online.target" ];
        after = [ "network-online.target" ];
        path = [ pkgs.iproute2 ];
        preStart = ''
          ip netns add game
          ip link add veth-host type veth peer name veth-game
          ip address add 172.18.0.1/24 dev veth-host
          ip link set veth-host up
          ip link set veth-game netns game
          ip netns exec game ip link set lo up
          ip netns exec game ip address add 172.18.0.2/24 dev veth-game
          ip netns exec game ip link set veth-game up
          ip netns exec game ip route add default via 172.18.0.1
        '';
        serviceConfig = {
          ExecStart = "${pkgs.iproute2}/bin/ip netns exec game ${pkgs.python3}/bin/python ${server} container";
          ExecStopPost = "${pkgs.iproute2}/bin/ip netns delete game";
        };
      };
      system.stateVersion = "25.05";
    };
  };

  testScript = ''
    start_all()
    estuary.wait_for_unit("wireguard-wg-estuary.service")
    mangrove.wait_for_unit("wireguard-wg-estuary.service")
    runner.wait_for_unit("wireguard-wg-ci.service")
    mangrove.wait_for_unit("ingress-test.service")
    mangrove.wait_for_unit("container-ingress-test.service")
    estuary.wait_until_succeeds("wg show wg-estuary latest-handshakes | grep -Ev '[[:space:]]0$'")
    runner.wait_until_succeeds("wg show wg-ci latest-handshakes | grep -Ev '[[:space:]]0$'")

    runner.wait_until_succeeds("ping -c 1 -W 1 10.88.0.2", timeout=30)
    runner.fail("ping -c 1 -W 1 198.51.100.2")

    client.succeed("${pkgs.python3}/bin/python ${probe} tcp 192.0.2.1 2022 192.0.2.2")
    client.succeed("${pkgs.python3}/bin/python ${probe} tcp 192.0.2.1 25565 192.0.2.2")
    client.succeed("${pkgs.python3}/bin/python ${probe} udp 192.0.2.1 25565 192.0.2.2")
    client.succeed("${pkgs.python3}/bin/python ${probe} tcp 192.0.2.1 25566 192.0.2.2")
    client.fail("${pkgs.python3}/bin/python ${probe} tcp 192.0.2.1 25576 192.0.2.2")

    mangrove.succeed("ip route get 203.0.113.1 | grep 'via 198.51.100.254 dev eth1'")
    mangrove.succeed("systemctl stop wireguard-wg-estuary.service")
    mangrove.fail("ip route get 203.0.113.1 mark 0x88")
  '';
}
