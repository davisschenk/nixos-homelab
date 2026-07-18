{ config, pkgs, ... }:
let
  sopsFile = ../../secrets/tilt.yaml;
in
{
  sops.secrets = {
    "tilt_db_password" = { inherit sopsFile; };
    "tilt_rocket_secret_key" = { inherit sopsFile; };
    "tilt_oidc_client_secret" = { inherit sopsFile; };
  };

  sops.templates."tilt-env" = {
    content = ''
      DB_PASSWORD=${config.sops.placeholder."tilt_db_password"}
      POSTGRES_PASSWORD=${config.sops.placeholder."tilt_db_password"}
      ROCKET_SECRET_KEY=${config.sops.placeholder."tilt_rocket_secret_key"}
      AUTHENTIK_CLIENT_SECRET=${config.sops.placeholder."tilt_oidc_client_secret"}
      DATABASE_URL=postgres://tilt:${config.sops.placeholder."tilt_db_password"}@tilt-db:5432/tilt
    '';
    restartUnits = [ "docker-tilt-db.service" "docker-tilt.service" ];
  };

  virtualisation.oci-containers.containers = {
    tilt-db = {
      image = "postgres:16-alpine";
      autoStart = true;
      environment = {
        POSTGRES_DB = "tilt";
        POSTGRES_USER = "tilt";
      };
      environmentFiles = [ config.sops.templates."tilt-env".path ];
      volumes = [ "/persist/containers/tilt/postgres:/var/lib/postgresql/data" ];
      extraOptions = [
        "--network=tilt"
        "--health-cmd=pg_isready -U tilt -d tilt"
        "--health-interval=5s"
        "--health-timeout=5s"
        "--health-retries=5"
      ];
    };

    tilt = {
      image = "ghcr.io/davisschenk/tilt-app:latest";
      autoStart = true;
      ports = [ "127.0.0.1:${toString config.mylab.ports.tilt}:8000" ];
      environmentFiles = [ config.sops.templates."tilt-env".path ];
      environment = {
        AUTH_MODE = "oidc";
        AUTHENTIK_ISSUER_URL = "https://auth.schenkenberger.dev/application/o/tilt/";
        AUTHENTIK_CLIENT_ID = "tilt";
        AUTHENTIK_REDIRECT_URL = "https://tilt.schenkenberger.dev/api/v1/auth/callback";
        FRONTEND_URL = "https://tilt.schenkenberger.dev";
        ROCKET_ADDRESS = "0.0.0.0";
        ROCKET_PORT = "8000";
        RUST_LOG = "info";
        UPLOAD_DIR = "/app/uploads";
      };
      volumes = [ "/persist/containers/tilt/uploads:/app/uploads" ];
      dependsOn = [ "tilt-db" ];
      extraOptions = [ "--network=tilt" ];
    };
  };

  systemd.services.docker-tilt-network = {
    description = "Tilt Docker network";
    after = [ "docker.service" ];
    requires = [ "docker.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "create-tilt-network" ''
        ${pkgs.docker}/bin/docker network inspect tilt >/dev/null 2>&1 || \
          ${pkgs.docker}/bin/docker network create tilt >/dev/null
      '';
    };
  };

  systemd.tmpfiles.rules = [
    "d /persist/containers/tilt          0750 root root -"
    "d /persist/containers/tilt/postgres 0700 70   70   -"
    "d /persist/containers/tilt/uploads  0750 root root -"
  ];

  systemd.services."docker-tilt" = {
    after = [ "docker-tilt-network.service" "docker-tilt-db.service" ];
    requires = [ "docker-tilt-network.service" "docker-tilt-db.service" ];
    unitConfig.RequiresMountsFor = [ "/persist/containers/tilt" ];
  };

  systemd.services."docker-tilt-db" = {
    after = [ "docker-tilt-network.service" ];
    requires = [ "docker-tilt-network.service" ];
    unitConfig.RequiresMountsFor = [ "/persist/containers/tilt" ];
  };
}
