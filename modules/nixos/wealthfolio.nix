{ config, ... }:
let
  sopsFile = ../../secrets/wealthfolio.yaml;
in
{
  sops.secrets = {
    "wealthfolio_secret_key" = { inherit sopsFile; };
    "wealthfolio_oidc_client_secret" = { inherit sopsFile; };
  };

  sops.templates."wealthfolio-env" = {
    content = ''
      WF_SECRET_KEY=${config.sops.placeholder."wealthfolio_secret_key"}
      WF_OIDC_CLIENT_SECRET=${config.sops.placeholder."wealthfolio_oidc_client_secret"}
    '';
    restartUnits = [ "docker-wealthfolio.service" ];
  };

  virtualisation.oci-containers.containers.wealthfolio = {
    image = "ghcr.io/wealthfolio/wealthfolio:3.6.1";
    autoStart = true;
    ports = [ "127.0.0.1:${toString config.mylab.ports.wealthfolio}:8088" ];
    volumes = [ "/persist/containers/wealthfolio/data:/data" ];
    environmentFiles = [ config.sops.templates."wealthfolio-env".path ];
    environment = {
      TZ = "America/Denver";
      WF_LISTEN_ADDR = "0.0.0.0:8088";
      WF_DB_PATH = "/data/wealthfolio.db";
      WF_CORS_ALLOW_ORIGINS = "https://wealthfolio.schenkenberger.dev";
      # Issuer URL must retain trailing slash for strict validation; only OIDC login, no password hash.
      WF_OIDC_ISSUER_URL = "https://auth.schenkenberger.dev/application/o/wealthfolio/";
      WF_OIDC_CLIENT_ID = "wealthfolio";
      WF_OIDC_REDIRECT_URL = "https://wealthfolio.schenkenberger.dev/api/v1/auth/oidc/callback";
      WF_OIDC_SCOPES = "openid email profile";
      # Access controlled by Authentik policy bindings, not app-side allowlist.
      WF_OIDC_ALLOW_ANY = "true";
    };
  };

  systemd.tmpfiles.rules = [
    # Container runs as UID 1000 since v3.4.0; SQLite needs write access.
    "d /persist/containers/wealthfolio/data 0750 1000 1000 -"
  ];

  systemd.services."docker-wealthfolio" = {
    unitConfig.RequiresMountsFor = [ "/persist/containers/wealthfolio" ];
  };
}
