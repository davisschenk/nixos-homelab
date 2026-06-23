{
  pkgs,
  ...
}:
{
  time.timeZone = "America/Denver";
  i18n.defaultLocale = "en_US.UTF-8";

  # Disable mutable users — all users declared in Nix
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

  security.sudo = {
    wheelNeedsPassword = true;
    extraRules = [
      {
        users = [ "davis" ];
        commands = [
          { command = "/run/current-system/sw/bin/nixos-rebuild"; options = [ "NOPASSWD" ]; }
          { command = "/run/current-system/sw/bin/systemctl"; options = [ "NOPASSWD" ]; }
        ];
      }
    ];
  };

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "no";
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
    allowedTCPPorts = [ 22 ];
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

  # Wipe / on each boot by deleting and recreating the @ btrfs subvolume
  # Uses systemd initrd (required for NixOS 26.05+; scripted initrd is deprecated)
  boot.initrd = {
    systemd.enable = true;
    supportedFilesystems = [ "btrfs" ];
    systemd.services.wipe-root = {
      description = "Wipe / btrfs subvolume on each boot";
      wantedBy = [ "initrd.target" ];
      after = [
        "systemd-cryptsetup.target"
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

  # Bind-mount persisted paths from /persist back into the live system
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

  # sops-nix secrets management with age encryption
  # Each secret specifies its own sopsFile explicitly; no defaultSopsFile needed.
  sops = {
    age.keyFile = "/persist/etc/sops/age/keys.txt";
  };

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
