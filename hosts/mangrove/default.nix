{ config, ... }:
{
  imports = [
    ./hardware-configuration.nix
    ./disko.nix
  ];

  networking.hostName = "mangrove";

  networking.useDHCP = false;
  networking.interfaces.enp3s0.ipv4.addresses = [
    {
      address = "10.0.0.2";
      prefixLength = 24;
    }
  ];
  networking.defaultGateway = "10.0.0.1";
  networking.nameservers = [
    "10.0.0.1"
    "1.1.1.1"
  ];

  boot = {
    loader = {
      systemd-boot = {
        enable = true;
        configurationLimit = 5;
        editor = false;
      };
      efi.canTouchEfiVariables = true;
    };
    zfs.forceImportRoot = false;
    initrd.systemd.emergencyAccess = true;
    # AMD Radeon 540/550 (01:00.0) + Baffin HDMI audio (01:00.1) — passed to Windows VM
    extraModprobeConfig = "options vfio-pci ids=1002:699f,1002:aae0";
  };

  sops.secrets.curseforge_api_key = {
    sopsFile = ../../secrets/pelican.yaml;
    owner = "root";
    group = "game-servers";
    mode = "0440";
  };

  sops.templates."curseforge-environment" = {
    content = "API_KEY=${config.sops.placeholder.curseforge_api_key}\n";
    owner = "root";
    group = "game-servers";
    mode = "0440";
  };

  mylab.gameServers = {
    enable = true;
    defaultOwner.email = "davis.schenkenberger@gmail.com";

    infrarust = {
      enable = true;
      # Wings publishes 127.0.0.1-declared allocations on its own
      # docker.network.interface instead of literal loopback -- see
      # /var/lib/pelican-wings/config.yml on mangrove.
      backendAddress = "172.19.0.1";
    };

    servers.star-technology = {
      displayName = "Star Technology";
      eggUuid = "019bbf16-a3f3-470a-9c0b-f3995b5e032a";
      image = "ghcr.io/pterodactyl/yolks:java_17";

      # CurseForge Generic egg: downloads the modpack by project/file ID and
      # installs Forge automatically. https://www.curseforge.com/minecraft/modpacks/star-technology
      environment = {
        PROJECT_ID = "924189";
        VERSION_ID = "8174581"; # StarT Theta 1 HF 3 Server Files (1.20.1 THETA 1 HOTFIX 3)
      };
      secretEnvironmentFile = config.sops.templates."curseforge-environment".path;

      limits = {
        memory = 8192;
        swap = 0;
        disk = 51200;
        io = 500;
        cpu = 400;
      };

      allocations.primary = {
        ip = "127.0.0.1";
        port = 25566;
        primary = true;
      };

      minecraft.infrarust = {
        enable = true;
        domains = [ "star.mc.schenkenberger.dev" ];
      };
    };

    servers.atm10-aeronautics = {
      displayName = "All the Mods 10: Aeronautics";
      eggUuid = "019bbf16-a3f3-470a-9c0b-f3995b5e032a";
      image = "ghcr.io/pterodactyl/yolks:java_21";

      environment = {
        PROJECT_ID = "1644918";
        VERSION_ID = "8751735";
      };
      secretEnvironmentFile = config.sops.templates."curseforge-environment".path;

      limits = {
        memory = 12288;
        swap = 0;
        disk = 102400;
        io = 500;
        cpu = 600;
      };

      allocations.primary = {
        ip = "127.0.0.1";
        port = 25567;
        primary = true;
      };

      minecraft.infrarust = {
        enable = true;
        domains = [ "aeronautics.mc.schenkenberger.dev" ];
      };
    };
  };

  system.stateVersion = "25.05";
}
