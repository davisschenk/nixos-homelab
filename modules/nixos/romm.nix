{ config, pkgs, ... }:
let
  sopsFile = ../../secrets/romm.yaml;
in
{
  sops.secrets = {
    "romm_db_password" = { inherit sopsFile; };
    "romm_auth_secret_key" = { inherit sopsFile; };
    "romm_oidc_client_secret" = { inherit sopsFile; };
    "romm_igdb_client_id" = { inherit sopsFile; };
    "romm_igdb_client_secret" = { inherit sopsFile; };
  };

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

  virtualisation.docker = {
    enable = true;
    daemon.settings = {
      log-driver = "json-file";
      log-opts = {
        max-size = "10m";
        max-file = "3";
      };
    };
  };

  virtualisation.oci-containers = {
    backend = "docker";

    containers.romm-db = {
      image = "mariadb:10.11.11";
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
        "--network=romm-net"
        "--health-cmd=healthcheck.sh --connect --innodb_initialized"
        "--health-interval=10s"
        "--health-timeout=5s"
        "--health-retries=5"
        "--health-start-period=30s"
      ];
    };

    containers.romm = {
      image = "rommapp/romm:3.10.1";
      autoStart = true;
      dependsOn = [ "romm-db" ];
      extraOptions = [ "--network=romm-net" ];
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
        OIDC_CLIENT_ID = "romm";
        OIDC_REDIRECT_URI = "https://romm.schenkenberger.dev/api/oauth/openid";
        OIDC_SERVER_APPLICATION_URL = "https://auth.schenkenberger.dev/application/o/romm";
      };
    };
  };

  systemd = {
    tmpfiles.rules = [
      "d /persist/containers/romm/db     0750 root root -"
      "d /persist/containers/romm/data   0750 root root -"
      "d /persist/containers/romm/config 0750 root root -"
      "d /data/media/roms                0755 root root -"
    ];

    services = {
      init-romm-network = {
        description = "Create romm Docker network";
        after = [ "docker.service" ];
        requires = [ "docker.service" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          ${pkgs.docker}/bin/docker network inspect romm-net > /dev/null 2>&1 || \
            ${pkgs.docker}/bin/docker network create romm-net
        '';
      };

      "docker-romm" = {
        after = [ "init-romm-network.service" ];
        requires = [ "init-romm-network.service" ];
        unitConfig.RequiresMountsFor = [
          "/persist/containers/romm"
          "/data/media/roms"
        ];
      };

      "docker-romm-db" = {
        after = [ "init-romm-network.service" ];
        requires = [ "init-romm-network.service" ];
        unitConfig.RequiresMountsFor = [
          "/persist/containers/romm/db"
        ];
      };
    };
  };

  services.caddy.virtualHosts."romm.schenkenberger.dev" = {
    listenAddresses = [ "127.0.0.1" ];
    extraConfig = ''
      reverse_proxy localhost:${toString config.mylab.ports.romm}
    '';
  };

  # romm container volumes bind directly to /persist (never wiped); no
  # impermanence bind-mount needed for those paths.
  # /var/lib/docker is persisted so images survive reboots without re-pulling.
  environment.persistence."/persist" = {
    directories = [ "/var/lib/docker" ];
  };
}
