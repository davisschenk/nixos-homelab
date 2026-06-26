{ config, pkgs, ... }:
let
  auth-header = pkgs.buildHomeAssistantComponent {
    owner = "BeryJu";
    domain = "auth_header";
    version = "1.12";
    src = pkgs.fetchFromGitHub {
      owner = "BeryJu";
      repo = "hass-auth-header";
      tag = "v1.12";
      hash = "sha256-BPG/G6IM95g9ip2OsPmcAebi2ZvKHUpFzV4oquOFLPM=";
    };
    # The repo's Makefile default target is lint-fix (calls isort/black/ruff),
    # which aren't in the build sandbox. Nothing to compile here anyway.
    dontBuild = true;
  };
in
{
  services.mosquitto = {
    enable = true;
    listeners = [
      {
        # Home Assistant connects from localhost
        address = "127.0.0.1";
        port = config.mylab.ports.mosquitto;
        settings.allow_anonymous = true;
      }
      {
        # Frigate connects via host.docker.internal which resolves to the
        # docker0 bridge gateway (172.17.0.1) via --add-host=host.docker.internal:host-gateway
        address = "172.17.0.1";
        port = config.mylab.ports.mosquitto;
        settings.allow_anonymous = true;
      }
    ];
  };

  services.home-assistant = {
    enable = true;
    customComponents = [ auth-header ];
    config = {
      default_config = { };
      http = {
        server_host = "127.0.0.1";
        server_port = config.mylab.ports.homeassistant;
        use_x_forwarded_for = true;
        trusted_proxies = [ "127.0.0.1" "::1" ];
      };
      homeassistant.auth_providers = [
        {
          type = "auth_header";
          username_header = "X-Authentik-Username";
        }
        { type = "homeassistant"; }
      ];
    };
    extraComponents = [
      "met"
      "radio_browser"
      "mqtt"
    ];
  };

  systemd.services.home-assistant = {
    after = [ "mosquitto.service" ];
    wants = [ "mosquitto.service" ];
  };

  environment.persistence."/persist" = {
    directories = [
      "/var/lib/hass"
      "/var/lib/mosquitto"
    ];
  };
}
