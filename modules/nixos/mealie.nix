{ config, ... }:
let
  sopsFile = ../../secrets/mealie.yaml;
in
{
  sops.secrets."mealie_oidc_client_secret" = { inherit sopsFile; };
  sops.secrets."mealie_smtp_password" = { inherit sopsFile; };
  sops.secrets."mealie_openai_api_key" = { inherit sopsFile; };

  # credentialsFile must be KEY=value format (systemd EnvironmentFile);
  # sops.templates interpolates secrets into the file at activation time.
  sops.templates."mealie-credentials" = {
    content = ''
      OIDC_CLIENT_SECRET=${config.sops.placeholder."mealie_oidc_client_secret"}
      SMTP_PASSWORD=${config.sops.placeholder."mealie_smtp_password"}
      OPENAI_API_KEY=${config.sops.placeholder."mealie_openai_api_key"}
    '';
    # mealie uses DynamicUser; mode 0440 + root ownership is fine since
    # systemd loads EnvironmentFile before dropping privileges.
    mode = "0440";
    restartUnits = [ "mealie.service" ];
  };

  services.mealie = {
    enable = true;
    listenAddress = "127.0.0.1";
    port = config.mylab.ports.mealie;
    database.createLocally = true;
    credentialsFile = config.sops.templates."mealie-credentials".path;
    settings = {
      ALLOW_SIGNUP = "false";
      # OIDC — non-secret settings; client secret is in credentialsFile
      OIDC_AUTH_ENABLED = "true";
      OIDC_PROVIDER_NAME = "Authentik";
      OIDC_CONFIGURATION_URL = "https://auth.schenkenberger.dev/application/o/mealie/.well-known/openid-configuration";
      OIDC_CLIENT_ID = "mealie";
      OIDC_SIGNUP_ENABLED = "true";
      OIDC_USER_GROUP = "mealie_user";
      OIDC_ADMIN_GROUP = "mealie_admin";
      OIDC_AUTO_REDIRECT = "false";
      OIDC_REMEMBER_ME = "true";
      # SMTP
      SMTP_HOST = "smtp.gmail.com";
      SMTP_PORT = "587";
      SMTP_FROM_EMAIL = "homelab@schenkenberger.dev";
      SMTP_AUTH_STRATEGY = "TLS";
      SMTP_USER = "homelab@schenkenberger.dev";
      # OpenAI
      OPENAI_ENABLE = "true";
    };
  };

  services.caddy.virtualHosts."mealie.schenkenberger.dev" = {
    listenAddresses = [ "127.0.0.1" ];
    extraConfig = ''
      import authentik_forward_auth
      reverse_proxy localhost:${toString config.mylab.ports.mealie}
    '';
  };

  environment.persistence."/persist" = {
    directories = [
      "/var/lib/mealie"
      # /var/lib/postgresql is persisted by auth.nix (shared PostgreSQL instance)
    ];
  };
}
