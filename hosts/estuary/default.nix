{ config, pkgs, ... }:
{
  imports = [
    ../../modules/common/base.nix
    ../../modules/common/wireguard.nix
    ./disko.nix
  ];

  networking.hostName = "estuary";
  networking.useDHCP = true;

  boot = {
    initrd.availableKernelModules = [
      "ahci"
      "sd_mod"
      "virtio_pci"
      "virtio_scsi"
    ];
    loader = {
      efi.canTouchEfiVariables = false;
      grub = {
        enable = true;
        device = "nodev";
        efiInstallAsRemovable = true;
        efiSupport = true;
      };
    };
  };

  services.qemuGuest.enable = true;

  sops = {
    defaultSopsFile = ../../secrets/estuary.yaml;
    age.keyFile = "/var/lib/sops-nix/key.txt";
    secrets.wireguard_estuary_private_key.restartUnits = [ "wireguard-wg-estuary.service" ];
  };

  mylab.wireguard = {
    enable = true;
    role = "hub";
    address = "10.88.0.1/24";
    publicInterface = "ens3";
    privateKeyFile = config.sops.secrets.wireguard_estuary_private_key.path;
    peers = [
      {
        publicKey = "UhAhDVhIE4kDj2BPNp0JMAhie0geLUKV+4Zeg+Q8e3o=";
        allowedIPs = [ "10.88.0.2/32" ];
      }
      {
        publicKey = "+NBk1Qx4aWzoDYmglzddn0sMcSdQpovw2ilUa7p9fVQ=";
        allowedIPs = [ "10.88.0.3/32" ];
      }
    ];
  };

  services.prometheus.exporters.node = {
    enable = true;
    listenAddress = "10.88.0.1";
    port = 9100;
    enabledCollectors = [
      "cpu"
      "diskstats"
      "filesystem"
      "loadavg"
      "meminfo"
      "netdev"
      "pressure"
      "processes"
      "systemd"
      "time"
    ];
  };

  services.fail2ban = {
    enable = true;
    maxretry = 3;
    bantime = "1h";
  };

  environment.systemPackages = [ pkgs.wireguard-tools ];

  system.stateVersion = "25.05";
}
