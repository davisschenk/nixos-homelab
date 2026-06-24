{ config, ... }:
{
  services.overseerr = {
    enable = true;
    port = config.mylab.ports.overseerr;
  };

  environment.persistence."/persist" = {
    directories = [ "/var/lib/overseerr" ];
  };
}
