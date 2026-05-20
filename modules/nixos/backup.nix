{ config, ... }:
let
  sopsFile = ../../secrets/restic.yaml;
  commonSettings = {
    initialize = true;
    repositoryFile = config.sops.secrets."restic_repository".path;
    passwordFile = config.sops.secrets."restic_password".path;
    environmentFile = config.sops.secrets."restic_environment".path;
    pruneOpts = [
      "--keep-daily 7"
      "--keep-weekly 4"
      "--keep-monthly 3"
    ];
  };
in
{
  sops.secrets."restic_repository" = { inherit sopsFile; };
  sops.secrets."restic_password" = { inherit sopsFile; };
  sops.secrets."restic_environment" = { inherit sopsFile; };

  services.restic.backups = {
    persist = commonSettings // {
      paths = [
        "/persist"
        "/data/downloads/.qbittorrent"
      ];
      exclude = [ "/persist/containers/romm/db" ];
      timerConfig = {
        OnCalendar = "03:00";
        Persistent = true;
      };
    };

    postgresql = commonSettings // {
      backupPrepareCommand = ''
        mkdir -p /var/backup/postgresql
        ${config.services.postgresql.package}/bin/pg_dumpall \
          -U postgres > /var/backup/postgresql/all.sql
      '';
      paths = [ "/var/backup/postgresql" ];
      timerConfig = {
        OnCalendar = "02:00";
        Persistent = true;
      };
    };
  };

  environment.persistence."/persist" = {
    directories = [ "/var/backup/postgresql" ];
  };
}
