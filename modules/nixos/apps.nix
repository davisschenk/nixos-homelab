{ ... }:
{
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
