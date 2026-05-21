{ config, pkgs, ... }:
let
  sopsFile = ../../secrets/restic.yaml;
  commonSettings = {
    initialize = true;
    repositoryFile = config.sops.secrets."restic_repository".path;
    passwordFile = config.sops.secrets."restic_password".path;
    environmentFile = config.sops.secrets."restic_environment".path;
    pruneOpts = [
      "--keep-daily 7"
      "--keep-weekly 8"
      "--keep-monthly 12"
      "--keep-yearly 3"
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
      exclude = [
        "/persist/containers/romm/db"
        "/persist/var/lib/mysql"
        "/persist/etc/ssh/ssh_host_ed25519_key"
        "/persist/etc/sops/age/keys.txt"
      ];
      timerConfig = {
        OnCalendar = "03:00";
        Persistent = true;
      };
    };

    postgresql = commonSettings // {
      backupPrepareCommand = ''
        mkdir -p /var/backup/postgresql
        su -s /bin/sh postgres \
          -c "${config.services.postgresql.package}/bin/pg_dumpall \
            -f /var/backup/postgresql/all.sql"
      '';
      paths = [ "/var/backup/postgresql" ];
      timerConfig = {
        OnCalendar = "02:00";
        Persistent = true;
      };
    };

    mysql = commonSettings // {
      backupPrepareCommand = ''
        mkdir -p /var/backup/mysql
        su -s /bin/sh mysql \
          -c "${pkgs.mariadb}/bin/mysqldump \
            --all-databases \
            --single-transaction \
            --result-file=/var/backup/mysql/all.sql"
      '';
      paths = [ "/var/backup/mysql" ];
      timerConfig = {
        OnCalendar = "02:30";
        Persistent = true;
      };
    };
  };

  # Create backup staging dirs on /persist before impermanence bind-mounts them,
  # so the directories exist on first boot when the dump jobs run.
  systemd.tmpfiles.rules = [
    "d /persist/var/backup/postgresql 0750 postgres postgres -"
    "d /persist/var/backup/mysql      0750 mysql    mysql    -"
  ];

  environment.persistence."/persist" = {
    directories = [
      "/var/backup/postgresql"
      "/var/backup/mysql"
    ];
  };
}
