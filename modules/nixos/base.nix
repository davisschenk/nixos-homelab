{
  config,
  pkgs,
  lib,
  ...
}:
{
  time.timeZone = "America/Denver";
  i18n.defaultLocale = "en_US.UTF-8";

  users.mutableUsers = false;

  users.users.davis = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "libvirtd"
    ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHcsz+eVVzP7F9kK1kvFoa05/9W4/xPgWCSD+cSJoh5a davis@tilt-app"
    ];
  };

  security.sudo.wheelNeedsPassword = false;

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "no";
      AllowUsers = [ "davis" ];
      MaxAuthTries = 3;
    };
    # Store host keys in /persist so they survive reboots
    hostKeys = [
      {
        path = "/persist/etc/ssh/ssh_host_ed25519_key";
        type = "ed25519";
      }
    ];
  };

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 config.mylab.ports.minecraft ];
    allowedUDPPorts = [ config.mylab.ports.minecraft ];
    # UDP 5353 is opened by services.avahi.openFirewall = true (the default)
  };

  services.avahi = {
    enable = true;
    nssmdns4 = true;
    allowInterfaces = [ "enp3s0" ];
    publish = {
      enable = true;
      addresses = true;
    };
  };

  environment.systemPackages = with pkgs; [
    git
    vim
    htop
    btrfs-progs
    age
    sops
    lshw
    pciutils
    usbutils
  ];

  # Required for NixOS 26.05+ (scripted initrd deprecated)
  boot.initrd = {
    systemd.enable = true;
    supportedFilesystems = [ "btrfs" ];
    systemd.services.wipe-root = {
      description = "Wipe / btrfs subvolume on each boot";
      wantedBy = [ "initrd.target" ];
      after = [
        "dev-nvme0n1p2.device"
      ];
      requires = [ "dev-nvme0n1p2.device" ];
      before = [ "sysroot.mount" ];
      unitConfig.DefaultDependencies = false;
      serviceConfig.Type = "oneshot";
      script = ''
        mkdir -p /btrfs_tmp
        mount -t btrfs -o subvol=/ /dev/nvme0n1p2 /btrfs_tmp

        if [[ -e /btrfs_tmp/@ ]]; then
          mkdir -p /btrfs_tmp/old_roots
          timestamp=$(date --date="@$(stat -c %Y /btrfs_tmp/@)" "+%Y-%m-%-d_%H:%M:%S")
          mv /btrfs_tmp/@ "/btrfs_tmp/old_roots/$timestamp"
        fi

        delete_subvolume_recursively() {
          local IFS=$'\n'
          for i in $(btrfs subvolume list -o "$1" | cut -f 9- -d ' '); do
            delete_subvolume_recursively "/btrfs_tmp/$i"
          done
          btrfs subvolume delete "$1"
        }

        for i in $(find /btrfs_tmp/old_roots/ -mindepth 1 -maxdepth 1 -mtime +30 2>/dev/null); do
          delete_subvolume_recursively "$i"
        done

        btrfs subvolume create /btrfs_tmp/@
        umount /btrfs_tmp
      '';
    };
  };

  environment.persistence."/persist" = {
    hideMounts = true;
    files = [
      "/etc/machine-id"
    ];
    directories = [
      "/var/lib/nixos"
      "/var/lib/postgresql"
    ];
  };

  # /persist itself must survive — it's on @persist subvolume, not wiped
  fileSystems."/persist".neededForBoot = true;
  # @log subvolume must be mounted before the journal starts writing
  fileSystems."/var/log".neededForBoot = true;

  # Workaround: impermanence resets /var/lib/private; force tmpfiles re-run (see issue #254)
  systemd.tmpfiles.rules = [
    "d /persist/var/lib/private 0700 root root -"
    "e /var/lib/private 0700 root root -"
  ];
  systemd.services."systemd-tmpfiles-resetup".serviceConfig.RemainAfterExit = lib.mkForce false;

  zramSwap.enable = true;

  nix = {
    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      trusted-users = [
        "root"
        "@wheel"
      ];
    };
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };
    optimise.automatic = true;
  };

}
