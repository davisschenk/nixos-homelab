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
}
