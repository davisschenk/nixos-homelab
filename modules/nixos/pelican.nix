# Pelican Panel + Wings
#
# Panel manages game-server infrastructure via a web UI.
# Wings is the node daemon that executes containers on this host.
#
# Boot-order for first deploy:
#   1. Deploy with Wings disabled (uuid is not yet known).
#   2. Log into the Panel, create a Node — the Panel generates a UUID + token pair.
#   3. Fill in wings.uuid (from Node settings) and populate the sops secrets:
#        pelican_token_id  — "Token ID" shown in Node → Configuration tab
#        pelican_token     — "Token"    shown in Node → Configuration tab
#   4. Re-enable wings.enable = true and redeploy.
{
  config,
  ...
}:
{
  # ---------------------------------------------------------------------------
  # Panel
  # ---------------------------------------------------------------------------
  services.pelican.panel = {
    enable = true;

    app = {
      url = "https://panel.schenkenberger.dev";
      # APP_KEY is a Laravel encryption key — generate once with:
      #   php artisan key:generate --show
      # Store the result (base64:…) as pelican_app_key in secrets/pelican.yaml
      keyFile = config.sops.secrets.pelican_app_key.path;
    };

    database = {
      # MariaDB created locally; password kept in sops
      createLocally = true;
      passwordFile = config.sops.secrets.pelican_db_password.path;
    };

    redis = {
      # Redis created locally; no password needed for local-only socket
      createLocally = true;
    };

    # nginx vhost is set up by the module automatically from app.url
    enableNginx = true;
  };

  # Restrict nginx to loopback so Caddy can proxy panel.schenkenberger.dev → 127.0.0.1:8000
  # without competing with Caddy on port 80.
  services.nginx.defaultListenAddresses = [ "127.0.0.1" ];
  services.nginx.virtualHosts."panel.schenkenberger.dev" = {
    listen = [ { addr = "127.0.0.1"; port = 8000; ssl = false; } ];
  };

  # ---------------------------------------------------------------------------
  # Wings (node daemon)
  # ---------------------------------------------------------------------------
  # Wings is disabled until the Panel has been bootstrapped and a Node UUID +
  # token pair has been assigned.  See the comment block at the top of this
  # file for the enable procedure.
  services.pelican.wings = {
    enable = false; # set to true after filling in uuid below

    # Fill this in from the Panel → Nodes → <this node> → Configuration tab
    uuid = "00000000-0000-0000-0000-000000000000"; # PLACEHOLDER — replace after first deploy

    remote = "https://panel.schenkenberger.dev";

    # Token credentials come from the Panel's Node configuration page
    tokenIdFile = config.sops.secrets.pelican_token_id.path;
    tokenFile = config.sops.secrets.pelican_token.path;

    # Bind Wings API to loopback — Panel is co-located on this host
    api = {
      host = "127.0.0.1";
      port = 8080;
    };

    openFirewall = false; # manage ports explicitly below
  };

  # SFTP for game server file management (Wings, not the system SSH)
  networking.firewall.allowedTCPPorts = [ 2022 ];

  # ---------------------------------------------------------------------------
  # Additional sops secrets (panel-specific)
  # The pelican_token_id and pelican_token secrets are declared in base.nix.
  # ---------------------------------------------------------------------------
  sops.secrets.pelican_app_key = {
    sopsFile = ../../secrets/pelican.yaml;
    owner = config.services.pelican.panel.user;
  };

  sops.secrets.pelican_db_password = {
    sopsFile = ../../secrets/pelican.yaml;
    owner = config.services.pelican.panel.user;
  };
}
