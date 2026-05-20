# Pelican Panel + Wings
#
# Deploy order for first install:
#   1. Deploy with wings.enable = false. Log into Panel, create a Node.
#   2. Copy UUID + token from Panel → Nodes → <node> → Configuration tab
#      into secrets/pelican.yaml, re-encrypt, set wings.enable = true, redeploy.
{
  config,
  ...
}:
{
  sops.secrets.pelican_token_id = {
    sopsFile = ../../secrets/pelican.yaml;
  };

  sops.secrets.pelican_token = {
    sopsFile = ../../secrets/pelican.yaml;
  };

  sops.secrets.pelican_app_key = {
    sopsFile = ../../secrets/pelican.yaml;
    owner = config.services.pelican.panel.user;
  };

  sops.secrets.pelican_db_password = {
    sopsFile = ../../secrets/pelican.yaml;
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
    listen = [ { addr = "127.0.0.1"; port = 8000; ssl = false; } ];
  };

  services.pelican.wings = {
    enable = false;
    uuid = "00000000-0000-0000-0000-000000000000";
    remote = "https://panel.schenkenberger.dev";
    tokenIdFile = config.sops.secrets.pelican_token_id.path;
    tokenFile = config.sops.secrets.pelican_token.path;
    api = {
      host = "127.0.0.1";
      port = 8080;
    };
    openFirewall = false;
  };

  networking.firewall.allowedTCPPorts = [ 2022 ];

  services.caddy.virtualHosts."panel.schenkenberger.dev" = {
    listenAddresses = [ "127.0.0.1" ];
    extraConfig = ''
      reverse_proxy localhost:8000
    '';
  };

  environment.persistence."/persist" = {
    directories = [
      "/var/lib/pelican"
      "/var/lib/pelican-wings"
      "/var/lib/mysql"
    ];
  };
}
