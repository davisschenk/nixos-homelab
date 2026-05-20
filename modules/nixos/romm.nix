{ config, ... }:
let
  sopsFile = ../../secrets/romm.yaml;
in
{
  sops.secrets."romm_db_password" = { inherit sopsFile; };
  sops.secrets."romm_auth_secret_key" = { inherit sopsFile; };
  sops.secrets."romm_oidc_client_secret" = { inherit sopsFile; };
  sops.secrets."romm_igdb_client_id" = { inherit sopsFile; };
  sops.secrets."romm_igdb_client_secret" = { inherit sopsFile; };

  # Produce a KEY=value EnvironmentFile for the romm container with all secrets
  sops.templates."romm-env" = {
    content = ''
      MYSQL_PASSWORD=${config.sops.placeholder."romm_db_password"}
      ROMM_DB_PASSWD=${config.sops.placeholder."romm_db_password"}
      ROMM_AUTH_SECRET_KEY=${config.sops.placeholder."romm_auth_secret_key"}
      OIDC_CLIENT_SECRET=${config.sops.placeholder."romm_oidc_client_secret"}
      IGDB_CLIENT_ID=${config.sops.placeholder."romm_igdb_client_id"}
      IGDB_CLIENT_SECRET=${config.sops.placeholder."romm_igdb_client_secret"}
    '';
    restartUnits = [
      "docker-romm.service"
      "docker-romm-db.service"
    ];
  };

  virtualisation.docker.enable = true;

  virtualisation.oci-containers = {
    backend = "docker";

    containers.romm-db = {
      image = "mariadb:10.11";
      autoStart = true;
      volumes = [
        "/persist/containers/romm/db:/var/lib/mysql"
      ];
      environmentFiles = [ config.sops.templates."romm-env".path ];
      environment = {
        MYSQL_DATABASE = "romm";
        MYSQL_USER = "romm-user";
        MARIADB_RANDOM_ROOT_PASSWORD = "yes";
      };
      extraOptions = [
        "--health-cmd=healthcheck.sh --connect --innodb_initialized"
        "--health-interval=10s"
        "--health-timeout=5s"
        "--health-retries=5"
      ];
    };

    containers.romm = {
      image = "rommapp/romm:latest";
      autoStart = true;
      dependsOn = [ "romm-db" ];
      ports = [ "127.0.0.1:${toString config.mylab.ports.romm}:8080" ];
      volumes = [
        "/persist/containers/romm/data:/romm/data"
        "/persist/containers/romm/config:/romm/config"
        "/data/media/roms:/romm/library"
      ];
      environmentFiles = [ config.sops.templates."romm-env".path ];
      environment = {
        DB_HOST = "romm-db";
        DB_NAME = "romm";
        DB_USER = "romm-user";
        OIDC_ENABLED = "true";
        OIDC_PROVIDER = "authentik";
        OIDC_REDIRECT_URI = "https://romm.schenkenberger.dev/api/oauth2/openid/redirect";
        OIDC_SERVER_APPLICATION_URL = "https://auth.schenkenberger.dev";
        ROMM_BASE_PATH = "/romm";
      };
    };
  };

  systemd.tmpfiles.rules = [
    "d /persist/containers/romm/db     0750 root root -"
    "d /persist/containers/romm/data   0750 root root -"
    "d /persist/containers/romm/config 0750 root root -"
    "d /data/media/roms                0755 root root -"
  ];

  systemd.services."docker-romm" = {
    unitConfig.RequiresMountsFor = [
      "/persist/containers/romm"
      "/data/media/roms"
    ];
  };

  systemd.services."docker-romm-db" = {
    unitConfig.RequiresMountsFor = [
      "/persist/containers/romm/db"
    ];
  };

  services.caddy.virtualHosts."romm.schenkenberger.dev" = {
    listenAddresses = [ "127.0.0.1" ];
    extraConfig = ''
      import authentik_forward_auth
      reverse_proxy localhost:${toString config.mylab.ports.romm}
    '';
  };

  # Volumes bind directly to /persist which lives on the @persist btrfs
  # subvolume (never wiped); no impermanence bind-mount needed.
}
