{ config, ... }:
{
  sops.secrets."authentik_secret_key" = {
    sopsFile = ../../secrets/authentik.yaml;
  };

  # Render the secret key into a systemd EnvironmentFile (KEY=VALUE format)
  sops.templates."authentik-env" = {
    content = ''
      AUTHENTIK_SECRET_KEY=${config.sops.placeholder."authentik_secret_key"}
    '';
    restartUnits = [ "authentik.service" "authentik-worker.service" ];
  };

  services.authentik = {
    enable = true;
    environmentFile = config.sops.templates."authentik-env".path;
    settings = {
      disable_startup_analytics = true;
      avatars = "initials";
    };
  };
}
