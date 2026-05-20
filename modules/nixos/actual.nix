{ config, ... }:
{
  services.actual = {
    enable = true;
    settings = {
      hostname = "127.0.0.1";
      port = config.mylab.ports.actual;
    };
  };

  services.caddy.virtualHosts."actual.schenkenberger.dev" = {
    listenAddresses = [ "127.0.0.1" ];
    extraConfig = ''
      import authentik_forward_auth
      reverse_proxy localhost:${toString config.mylab.ports.actual}
    '';
  };

  environment.persistence."/persist" = {
    directories = [ "/var/lib/actual" ];
  };
}
