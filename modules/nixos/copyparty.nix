{ config, ... }:
{
  services.copyparty = {
    enable = true;
    settings = {
      i = "127.0.0.1";
      p = config.mylab.ports.copyparty;
      no-reload = true;
      idp-h-usr = "x-idp-user";
      idp-h-grp = "x-idp-groups";
      xff-src = "127.0.0.1";
    };
    volumes = {
      "/media" = {
        path = "/data/media";
        access = {
          r = "*";
        };
      };
    };
  };

  systemd.services.copyparty.unitConfig.RequiresMountsFor = [ "/data/media" ];

  environment.persistence."/persist" = {
    directories = [ "/var/lib/copyparty" ];
  };
}
