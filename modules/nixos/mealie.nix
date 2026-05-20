{ ... }:
{
  services.mealie = {
    enable = true;
    listenAddress = "127.0.0.1";
    port = 9925;
    settings = {
      ALLOW_SIGNUP = "false";
    };
  };

  services.caddy.virtualHosts."mealie.schenkenberger.dev" = {
    listenAddresses = [ "127.0.0.1" ];
    extraConfig = ''
      import authentik_forward_auth
      reverse_proxy localhost:9925
    '';
  };

  environment.persistence."/persist" = {
    directories = [ "/var/lib/mealie" ];
  };
}
