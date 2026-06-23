{ config, ... }:
{
  services.actual = {
    enable = true;
    settings = {
      hostname = "127.0.0.1";
      port = config.mylab.ports.actual;
    };
  };

  environment.persistence."/persist" = {
    directories = [ "/var/lib/private/actual" ];
  };
}
