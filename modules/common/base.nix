{ pkgs, ... }:
{
  time.timeZone = "America/Denver";
  i18n.defaultLocale = "en_US.UTF-8";

  users.mutableUsers = false;
  users.users.davis = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHcsz+eVVzP7F9kK1kvFoa05/9W4/xPgWCSD+cSJoh5a davis@tilt-app"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICXMMUeIDraWyUbGvSN4J7wJz10HPDSUgDbQ6u4UAusd github-actions@nixos-homelab"
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
  };

  environment.systemPackages = with pkgs; [
    age
    git
    htop
    sops
    vim
  ];

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
