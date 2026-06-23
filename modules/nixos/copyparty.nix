{ config, ... }:
{
  services.copyparty = {
    enable = true;
    settings = {
      i = "127.0.0.1";
      p = config.mylab.ports.copyparty;
      no-reload = true;
    };
    volumes = {
      "/media" = {
        path = "/data/media";
        access = {
          r = "*";
        };
        flags = { };
      };
    };
  };

  systemd.services.copyparty.unitConfig.RequiresMountsFor = [ "/data/media" ];

  environment.persistence."/persist" = {
    directories = [ "/var/lib/copyparty" ];
  };
}
