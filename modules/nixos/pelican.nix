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
  mailSopsFile = ../../secrets/mail.yaml;
in
{
  sops.secrets = {
    pelican_token_id = lib.mkIf config.services.pelican.wings.enable {
      inherit sopsFile;
      owner = config.services.pelican.wings.user;
    };
    pelican_token = lib.mkIf config.services.pelican.wings.enable {
      inherit sopsFile;
      owner = config.services.pelican.wings.user;
    };
    pelican_app_key = lib.mkIf config.services.pelican.panel.enable {
      inherit sopsFile;
      owner = config.services.pelican.panel.user;
    };
    pelican_db_password = lib.mkIf config.services.pelican.panel.enable {
      inherit sopsFile;
      owner = config.services.pelican.panel.user;
    };
    pelican_oauth_client_id = lib.mkIf config.services.pelican.panel.enable {
      inherit sopsFile;
      owner = config.services.pelican.panel.user;
    };
    pelican_oauth_client_secret = lib.mkIf config.services.pelican.panel.enable {
      inherit sopsFile;
      owner = config.services.pelican.panel.user;
    };
    "mail_username" = lib.mkIf config.services.pelican.panel.enable {
      sopsFile = mailSopsFile;
      owner = config.services.pelican.panel.user;
    };
    "mail_password" = lib.mkIf config.services.pelican.panel.enable {
      sopsFile = mailSopsFile;
      owner = config.services.pelican.panel.user;
    };
  };

  sops.templates."pelican-extra-env" = {
    content = ''
      MAIL_USERNAME=${config.sops.placeholder."mail_username"}
      MAIL_PASSWORD=${config.sops.placeholder."mail_password"}
      OAUTH_AUTHENTIK_CLIENT_ID=${config.sops.placeholder."pelican_oauth_client_id"}
      OAUTH_AUTHENTIK_CLIENT_SECRET=${config.sops.placeholder."pelican_oauth_client_secret"}
    '';
    owner = config.services.pelican.panel.user;
    restartUnits = [ "pelican-panel-setup.service" "pelican-queue.service" ];
  };

  services = {
    pelican = {
      panel = {
        enable = true;
        app = {
          url = "https://panel.schenkenberger.dev";
          keyFile = config.sops.secrets.pelican_app_key.path;
        };
        database = {
          createLocally = true;
          passwordFile = config.sops.secrets.pelican_db_password.path;
        };
        redis.createLocally = true;
        mail = {
          host = "in-v3.mailjet.com";
          port = 587;
          encryption = "tls";
          fromAddress = "pelican@schenkenberger.dev";
          fromName = "Pelican";
        };
        extraEnvironment = {
          OAUTH_AUTHENTIK_ENABLED = "true";
          OAUTH_AUTHENTIK_BASE_URL = "https://auth.schenkenberger.dev";
          OAUTH_AUTHENTIK_SHOULD_CREATE_MISSING_USERS = "true";
          OAUTH_AUTHENTIK_SHOULD_LINK_MISSING_USERS = "true";
        };
        extraEnvironmentFile = config.sops.templates."pelican-extra-env".path;
        enableNginx = true;
      };

      wings = {
        enable = true;
        uuid = "32011034-c138-4c4f-88be-d7c478faa405";
        remote = "https://panel.schenkenberger.dev";
        tokenIdFile = config.sops.secrets.pelican_token_id.path;
        tokenFile = config.sops.secrets.pelican_token.path;
        api = {
          host = "0.0.0.0";
          port = config.mylab.ports.wings;
        };
        openFirewall = false;
      };
    };

    nginx = {
      defaultListenAddresses = [ "127.0.0.1" ];
      virtualHosts."panel.schenkenberger.dev" = {
        listen = [
          {
            addr = "127.0.0.1";
            port = config.mylab.ports.pelican;
            ssl = false;
          }
        ];
      };
    };

  };

  assertions = [
    {
      assertion =
        !config.services.pelican.wings.enable
        || config.services.pelican.wings.uuid != "00000000-0000-0000-0000-000000000000";
      message = "Set services.pelican.wings.uuid to the real node UUID from Panel → Nodes → <node> → Configuration before enabling Wings.";
    }
  ];

  # Only open Wings SFTP port (2022) when Wings is actually enabled
  networking.firewall.allowedTCPPorts = lib.mkIf config.services.pelican.wings.enable [ config.mylab.ports.wingsSftp ];

  # Upstream nix-pelican only sets After=mysql.service on the setup unit, with
  # no Requires= and nothing at all for redis. After= alone doesn't pull the
  # target into the same start transaction — if switch-to-configuration issues
  # these as separate systemctl calls, there's nothing forcing mysql/redis to
  # actually be queued (let alone ready) before this runs, and it races them
  # on every deploy that restarts both. Requires= is what makes the ordering
  # real.
  systemd.services.pelican-panel-setup = {
    after = [ "redis-pelican-panel.service" ];
    requires = [ "mysql.service" "redis-pelican-panel.service" ];
  };

  environment.persistence."/persist" = {
    directories = [
      "/var/lib/pelican-panel" # upstream nix-pelican dataDir default
      "/var/lib/pelican-wings"
      "/var/lib/mysql"
    ];
  };
}
