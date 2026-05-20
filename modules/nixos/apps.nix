{ ... }:
{
  # ---------------------------------------------------------------------------
  # Mealie — recipe manager and meal planner
  # Port 9925 (avoids conflict with Authentik on 9000)
  # Caddy: mealie.schenkenberger.dev → localhost:9925
  # ---------------------------------------------------------------------------
  services.mealie = {
    enable = true;
    listenAddress = "127.0.0.1";
    port = 9925;
    settings = {
      ALLOW_SIGNUP = "false";
    };
  };

  # ---------------------------------------------------------------------------
  # Actual Budget — privacy-focused personal finance app
  # Port 5006, state lives in /var/lib/actual (persisted via impermanence)
  # Caddy: actual.schenkenberger.dev → localhost:5006
  # ---------------------------------------------------------------------------
  services.actual = {
    enable = true;
    settings = {
      hostname = "127.0.0.1";
      port = 5006;
    };
  };

  # Persist state directories for services that use DynamicUser or need
  # their /var/lib data to survive the btrfs root wipe on reboot.
  environment.persistence."/persist" = {
    directories = [
      "/var/lib/actual"
      "/var/lib/mealie"
    ];
  };

  # ---------------------------------------------------------------------------
  # Copyparty — web-based file manager / media share
  # Serves /data/media on port 3923 (loopback only)
  # Caddy: files.schenkenberger.dev → localhost:3923
  # ---------------------------------------------------------------------------
  services.copyparty = {
    enable = true;
    settings = {
      i = "127.0.0.1";
      p = 3923;
      no-reload = true;
    };
    volumes = {
      "/media" = {
        path = "/data/media";
        access = {
          r = "*";
        };
        flags = { };
      };
    };
  };
}
