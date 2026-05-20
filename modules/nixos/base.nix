{
  config,
  lib,
  pkgs,
  ...
}:
{
  time.timeZone = "America/Chicago";
  i18n.defaultLocale = "en_US.UTF-8";

  # Disable mutable users — all users declared in Nix
  users.mutableUsers = false;

  users.users.davis = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "libvirtd"
      "docker"
    ];
    # Replace with your actual SSH public key before deploying
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAA_REPLACE_WITH_YOUR_KEY davis@mangrove"
    ];
  };

  security.sudo.wheelNeedsPassword = false;

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
      {
        path = "/persist/etc/ssh/ssh_host_rsa_key";
        type = "rsa";
        bits = 4096;
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
  # postDeviceCommands is not supported with systemd initrd, so force it off
  boot.initrd.systemd.enable = lib.mkForce false;
  boot.initrd.supportedFilesystems = [ "btrfs" ];
  boot.initrd.postDeviceCommands = lib.mkAfter ''
    mkdir -p /btrfs_tmp
    mount -t btrfs -o subvol=/ /dev/disk/by-label/root /btrfs_tmp

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

  # Bind-mount persisted paths from /persist back into the live system
  environment.persistence."/persist" = {
    hideMounts = true;
    directories = [
      # /etc/ssh is intentionally omitted: openssh hostKeys already writes
      # directly to /persist/etc/ssh/... so no bind-mount is needed.
      "/etc/sops/age"
    ];
    files = [
      "/etc/machine-id"
    ];
  };

  # /persist itself must survive — it's on @persist subvolume, not wiped
  fileSystems."/persist".neededForBoot = true;

  # sops-nix secrets management with age encryption
  # Each secret specifies its own sopsFile explicitly; no defaultSopsFile needed.
  sops = {
    age.keyFile = "/persist/etc/sops/age/keys.txt";
  };

}
