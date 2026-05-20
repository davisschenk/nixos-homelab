# Pelican Panel + Wings
#
# Deploy order for first install:
#   1. Deploy with wings.enable = false. Log into Panel, create a Node.
#   2. Copy UUID + token from Panel → Nodes → <node> → Configuration tab
#      into secrets/pelican.yaml, re-encrypt, set wings.enable = true, redeploy.
{
  config,
  lib,
  ...
}:
let
  sopsFile = ../../secrets/pelican.yaml;
in
{
  sops.secrets.pelican_token_id = { inherit sopsFile; };
  sops.secrets.pelican_token = { inherit sopsFile; };
  sops.secrets.pelican_app_key = {
    inherit sopsFile;
    owner = config.services.pelican.panel.user;
  };
  sops.secrets.pelican_db_password = {
    inherit sopsFile;
    owner = config.services.pelican.panel.user;
  };

  services.pelican.panel = {
    enable = true;
    app = {
      url = "https://panel.schenkenberger.dev";
      keyFile = config.sops.secrets.pelican_app_key.path;
    };
    database = {
      createLocally = true;
      passwordFile = config.sops.secrets.pelican_db_password.path;
    };
    redis = {
      createLocally = true;
    };
    enableNginx = true;
  };

  services.nginx.defaultListenAddresses = [ "127.0.0.1" ];
  services.nginx.virtualHosts."panel.schenkenberger.dev" = {
    listen = [
      {
        addr = "127.0.0.1";
        port = config.mylab.ports.pelican;
        ssl = false;
      }
    ];
  };

  services.pelican.wings = {
    enable = false;
    uuid = "00000000-0000-0000-0000-000000000000"; # Replace from Panel → Nodes → <node> → Configuration
    remote = "https://panel.schenkenberger.dev";
    tokenIdFile = config.sops.secrets.pelican_token_id.path;
    tokenFile = config.sops.secrets.pelican_token.path;
    api = {
      host = "127.0.0.1";
      port = config.mylab.ports.wings;
    };
    openFirewall = false;
  };

  # Only open Wings SFTP port (2022) when Wings is actually enabled
  networking.firewall.allowedTCPPorts = lib.mkIf config.services.pelican.wings.enable [ 2022 ];

  services.caddy.virtualHosts."panel.schenkenberger.dev" = {
    listenAddresses = [ "127.0.0.1" ];
    extraConfig = ''
      reverse_proxy localhost:${toString config.mylab.ports.pelican}
    '';
  };

  environment.persistence."/persist" = {
    directories = [
      "/var/lib/pelican-panel" # upstream nix-pelican dataDir default
      "/var/lib/pelican-wings"
      "/var/lib/mysql"
    ];
  };
}
