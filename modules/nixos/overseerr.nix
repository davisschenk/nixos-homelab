{ config, ... }:
{
  sops.secrets."jellyseerr_oidc_client_secret" = {
    sopsFile = ../../../secrets/jellyseerr.yaml;
  };

  sops.templates."jellyseerr-env" = {
    content = ''
      JELLYFIN_SERVER_URL=http://localhost:${toString config.mylab.ports.jellyfin}
    '';
    restartUnits = [ "docker-jellyseerr.service" ];
  };

  virtualisation.oci-containers.containers.jellyseerr = {
    image = "fallenbagel/jellyseerr:2.5.2";
    autoStart = true;
    ports = [ "127.0.0.1:${toString config.mylab.ports.jellyseerr}:5055" ];
    volumes = [ "/persist/containers/jellyseerr/config:/app/config" ];
    environment = {
      LOG_LEVEL = "info";
      TZ = "America/Denver";
    };
  };

  systemd.tmpfiles.rules = [
    "d /persist/containers/jellyseerr/config 0750 root root -"
  ];

  systemd.services."docker-jellyseerr" = {
    unitConfig.RequiresMountsFor = [ "/persist/containers/jellyseerr" ];
  };

  environment.persistence."/persist" = {
    directories = [ "/var/lib/docker" ];
  };
}
