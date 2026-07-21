{ config, ... }:
let
  sopsFile = ../../secrets/mealie.yaml;
  mailSopsFile = ../../secrets/mail.yaml;
in
{
  sops.secrets = {
    "mealie_oidc_client_secret" = { inherit sopsFile; };
    "mealie_openai_api_key" = { inherit sopsFile; };
    "mail_username" = { sopsFile = mailSopsFile; };
    "mail_password" = { sopsFile = mailSopsFile; };
  };

  # credentialsFile must be KEY=value format for systemd EnvironmentFile.
  sops.templates."mealie-credentials" = {
    content = ''
      OIDC_CLIENT_SECRET=${config.sops.placeholder."mealie_oidc_client_secret"}
      SMTP_USER=${config.sops.placeholder."mail_username"}
      SMTP_PASSWORD=${config.sops.placeholder."mail_password"}
      OPENAI_API_KEY=${config.sops.placeholder."mealie_openai_api_key"}
    '';
    # DynamicUser + systemd loads EnvironmentFile before privilege drop allows 0440.
    mode = "0440";
    restartUnits = [ "mealie.service" ];
  };

  services = {
    mealie = {
      enable = true;
      listenAddress = "127.0.0.1";
      port = config.mylab.ports.mealie;
      database.createLocally = true;
      credentialsFile = config.sops.templates."mealie-credentials".path;
      settings = {
        ALLOW_SIGNUP = "false";
        ALLOW_PASSWORD_LOGIN = "false";
        # OIDC — non-secret settings; client secret is in credentialsFile
        OIDC_AUTH_ENABLED = "true";
        OIDC_PROVIDER_NAME = "Authentik";
        OIDC_CONFIGURATION_URL = "https://auth.schenkenberger.dev/application/o/mealie/.well-known/openid-configuration";
        OIDC_CLIENT_ID = "mealie";
        OIDC_SIGNUP_ENABLED = "true";
        OIDC_USER_GROUP = "mealie-user";
        OIDC_ADMIN_GROUP = "mealie-admin";
        OIDC_AUTO_REDIRECT = "true";
        OIDC_REMEMBER_ME = "true";
        OIDC_SCOPES_OVERRIDE = "openid profile email groups";
        # SMTP — user (API key) and password (secret key) are in credentialsFile
        SMTP_HOST = "in-v3.mailjet.com";
        SMTP_PORT = "587";
        SMTP_FROM_EMAIL = "mealie@schenkenberger.dev";
        BASE_URL = "https://mealie.schenkenberger.dev";
        SMTP_AUTH_STRATEGY = "STARTTLS";
        # OpenAI
        OPENAI_ENABLE = "true";
      };
    };

  };

  environment.persistence."/persist" = {
    directories = [
      "/var/lib/private/mealie"
      # /var/lib/postgresql is persisted by base.nix (shared PostgreSQL instance)
    ];
  };
}
