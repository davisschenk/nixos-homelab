{ config, pkgs, ... }:
let
  sopsFile = ../../../secrets/authentik.yaml;
  mailSopsFile = ../../../secrets/mail.yaml;
in
{
  sops.secrets = {
    "authentik_secret_key" = { inherit sopsFile; };
    "mail_username" = { sopsFile = mailSopsFile; };
    "mail_password" = { sopsFile = mailSopsFile; };
    "grafana_oauth_client_secret" = { sopsFile = ../../../secrets/grafana.yaml; };
    "jellyfin_oidc_client_secret" = { sopsFile = ../../../secrets/jellyfin.yaml; };
    "jellyseerr_oidc_client_secret" = { sopsFile = ../../../secrets/jellyseerr.yaml; };
    "actual_oidc_client_secret" = { sopsFile = ../../../secrets/actual.yaml; };
    "pelican_oauth_client_id" = { sopsFile = ../../../secrets/pelican.yaml; };
    "pelican_oauth_client_secret" = { sopsFile = ../../../secrets/pelican.yaml; };
    # Declared here so the authentik-env template is self-contained; mealie.nix and
    # romm.nix keep their own declarations (sops-nix merges duplicates harmlessly).
    "mealie_oidc_client_secret" = { sopsFile = ../../../secrets/mealie.yaml; };
    "romm_oidc_client_secret" = { sopsFile = ../../../secrets/romm.yaml; };
  };

  sops.templates."authentik-env" = {
    content = ''
      AUTHENTIK_SECRET_KEY=${config.sops.placeholder."authentik_secret_key"}
      AUTHENTIK_EMAIL__USERNAME=${config.sops.placeholder."mail_username"}
      AUTHENTIK_EMAIL__PASSWORD=${config.sops.placeholder."mail_password"}
      MEALIE_OIDC_CLIENT_SECRET=${config.sops.placeholder."mealie_oidc_client_secret"}
      ROMM_OIDC_CLIENT_SECRET=${config.sops.placeholder."romm_oidc_client_secret"}
      GRAFANA_OIDC_CLIENT_SECRET=${config.sops.placeholder."grafana_oauth_client_secret"}
      JELLYFIN_OIDC_CLIENT_SECRET=${config.sops.placeholder."jellyfin_oidc_client_secret"}
      JELLYSEERR_OIDC_CLIENT_SECRET=${config.sops.placeholder."jellyseerr_oidc_client_secret"}
      ACTUAL_OIDC_CLIENT_SECRET=${config.sops.placeholder."actual_oidc_client_secret"}
      PELICAN_OAUTH_CLIENT_ID=${config.sops.placeholder."pelican_oauth_client_id"}
      PELICAN_OAUTH_CLIENT_SECRET=${config.sops.placeholder."pelican_oauth_client_secret"}
    '';
    restartUnits = [
      "authentik.service"
      "authentik-worker.service"
      "authentik-ldap.service"
      "authentik-proxy.service"
      "authentik-radius.service"
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

  };

  system.activationScripts.authentik-branding = {
    text = ''
      install -d -m 0755 /var/lib/private/authentik/media/public/branding
      install -m 0644 ${../../../assets/flow_background.jpg} \
        /var/lib/private/authentik/media/public/branding/flow_background.jpg
    '';
  };

  environment.persistence."/persist" = {
    directories = [
      "/var/lib/private/authentik"
    ];
  };
}
