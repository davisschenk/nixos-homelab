{ ... }:
{
  virtualisation.docker.enable = true;

  virtualisation.oci-containers = {
    backend = "docker";

    containers.romm = {
      image = "rommapp/romm:latest";
      autoStart = true;
      ports = [ "127.0.0.1:8888:8080" ];
      volumes = [
        "/persist/containers/romm/data:/romm/data"
        "/persist/containers/romm/config:/romm/config"
        "/data/media/roms:/romm/library"
      ];
      environment = {
        ROMM_BASE_PATH = "/romm";
      };
    };
  };

  # Pre-create volume source directories under /persist (survives impermanence)
  systemd.tmpfiles.rules = [
    "d /persist/containers/romm/data   0750 root root -"
    "d /persist/containers/romm/config 0750 root root -"
    "d /data/media/roms                0755 root root -"
  ];

  # Ensure /data and /persist mounts are up before Docker starts the container
  systemd.services."docker-romm" = {
    unitConfig.RequiresMountsFor = [
      "/persist/containers/romm"
      "/data/media/roms"
    ];
  };
}
