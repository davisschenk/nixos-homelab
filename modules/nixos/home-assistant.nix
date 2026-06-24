{ config, ... }:
{
  services.mosquitto = {
    enable = true;
    listeners = [{
      port = 1883;
      settings.allow_anonymous = true;
    }];
  };

  services.home-assistant = {
    enable = true;
    config = {
      default_config = { };
      http = {
        server_port = config.mylab.ports.homeassistant;
        use_x_forwarded_for = true;
        trusted_proxies = [ "127.0.0.1" ];
      };
    };
    extraComponents = [
      "met"
      "radio_browser"
      "mqtt"
    ];
  };

  environment.persistence."/persist" = {
    directories = [
      "/var/lib/hass"
      "/var/lib/mosquitto"
    ];
  };
}
