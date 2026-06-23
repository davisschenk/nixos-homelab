{ config, ... }:
let
  sopsFile = ../../secrets/authentik.yaml;
  mailSopsFile = ../../secrets/mail.yaml;
in
{
  sops.secrets = {
    "authentik_secret_key" = { inherit sopsFile; };
    "mail_username" = { sopsFile = mailSopsFile; };
    "mail_password" = { sopsFile = mailSopsFile; };
  };

  sops.templates."authentik-env" = {
    content = ''
      AUTHENTIK_SECRET_KEY=${config.sops.placeholder."authentik_secret_key"}
      AUTHENTIK_EMAIL__USERNAME=${config.sops.placeholder."mail_username"}
      AUTHENTIK_EMAIL__PASSWORD=${config.sops.placeholder."mail_password"}
      MEALIE_OIDC_CLIENT_SECRET=${config.sops.placeholder."mealie_oidc_client_secret"}
      ROMM_OIDC_CLIENT_SECRET=${config.sops.placeholder."romm_oidc_client_secret"}
    '';
    restartUnits = [
      "authentik.service"
      "authentik-worker.service"
    ];
  };

  services = {
    authentik = {
      enable = true;
      environmentFile = config.sops.templates."authentik-env".path;
      settings = {
        disable_startup_analytics = true;
        avatars = "initials";
        email = {
          host = "in-v3.mailjet.com";
          port = 587;
          use_tls = true;
          use_ssl = false;
          timeout = 10;
          from = "authentik@schenkenberger.dev";
        };
      };
    };

    caddy.virtualHosts."auth.schenkenberger.dev" = {
      listenAddresses = [ "127.0.0.1" ];
      extraConfig = ''
        reverse_proxy localhost:${toString config.mylab.ports.authentik}
      '';
    };
  };

  environment.persistence."/persist" = {
    directories = [
      "/var/lib/private/authentik"
    ];
  };
}
