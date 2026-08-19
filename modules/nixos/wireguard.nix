{ config, ... }:
{
  sops.secrets.wireguard_mangrove_private_key = {
    sopsFile = ../../secrets/wireguard.yaml;
    restartUnits = [ "wireguard-wg-estuary.service" ];
  };

  mylab.wireguard = {
    enable = true;
    role = "spoke";
    address = "10.88.0.2/24";
    privateKeyFile = config.sops.secrets.wireguard_mangrove_private_key.path;
    lanInterface = "enp3s0";
    peers = [
      {
        publicKey = "fX/cDl6eNrzE93glQ8VOq+6YUfJxPgEArXSh3NY0Ox0=";
        allowedIPs = [ "0.0.0.0/0" ];
        endpoint = "play.schenkenberger.dev:51820";
        persistentKeepalive = 25;
      }
    ];
  };
}
