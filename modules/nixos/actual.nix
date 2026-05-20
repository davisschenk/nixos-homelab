{ ... }:
{
  services.actual = {
    enable = true;
    settings = {
      hostname = "127.0.0.1";
      port = 5006;
    };
  };

  services.caddy.virtualHosts."actual.schenkenberger.dev" = {
    listenAddresses = [ "127.0.0.1" ];
    extraConfig = ''
      import authentik_forward_auth
      reverse_proxy localhost:5006
    '';
  };

  environment.persistence."/persist" = {
    directories = [ "/var/lib/actual" ];
  };
}
