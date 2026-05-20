{ config, ... }:
{
  sops.secrets."authentik_secret_key" = {
    sopsFile = ../../secrets/authentik.yaml;
  };

  sops.templates."authentik-env" = {
    content = ''
      AUTHENTIK_SECRET_KEY=${config.sops.placeholder."authentik_secret_key"}
    '';
    restartUnits = [
      "authentik.service"
      "authentik-worker.service"
    ];
  };

  services.authentik = {
    enable = true;
    environmentFile = config.sops.templates."authentik-env".path;
    settings = {
      disable_startup_analytics = true;
      avatars = "initials";
    };
  };

  services.caddy.virtualHosts."auth.schenkenberger.dev" = {
    listenAddresses = [ "127.0.0.1" ];
    extraConfig = ''
      reverse_proxy localhost:${toString config.mylab.ports.authentik}
    '';
  };

  environment.persistence."/persist" = {
    directories = [
      "/var/lib/authentik"
      "/var/lib/postgresql"
    ];
  };
}
