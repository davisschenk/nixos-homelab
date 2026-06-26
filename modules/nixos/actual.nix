{ config, ... }:
{
  sops.secrets."actual_oidc_client_secret" = {
    sopsFile = ../../secrets/actual.yaml;
    # DynamicUser preStart script runs as the service user and needs to read
    # this file. Since no fixed UID exists, owner= cannot be used. mode 0444
    # is acceptable here — the secret also ends up in /run/actual/config.json
    # which is only readable by the service user anyway.
    mode = "0444";
  };

  services.actual = {
    enable = true;
    settings = {
      hostname = "127.0.0.1";
      port = config.mylab.ports.actual;
      loginMethod = "openid";
      trustedProxies = [ "127.0.0.1" "::1" ];
      openId = {
        discoveryURL = "https://auth.schenkenberger.dev/application/o/actual/";
        client_id = "actual";
        client_secret._secret = config.sops.secrets."actual_oidc_client_secret".path;
        server_hostname = "https://actual.schenkenberger.dev";
        authMethod = "oauth2";
      };
    };
  };

  environment.persistence."/persist" = {
    directories = [ "/var/lib/private/actual" ];
  };
}
