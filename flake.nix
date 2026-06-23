{
  description = "mangrove homelab";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    nixarr = {
      url = "github:rasmus-kirk/nixarr";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    authentik-nix = {
      url = "github:nix-community/authentik-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-pelican = {
      url = "github:Hythera/nix-pelican";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    copyparty = {
      url = "github:9001/copyparty";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    impermanence.url = "github:nix-community/impermanence";

  };

  outputs =
    {
      self,
      nixpkgs,
      disko,
      sops-nix,
      impermanence,
      nixarr,
      authentik-nix,
      nix-pelican,
      copyparty,
      ...
    }@inputs:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      nixosConfigurations.mangrove = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit inputs; };
        modules = [
          disko.nixosModules.disko
          sops-nix.nixosModules.sops
          impermanence.nixosModules.impermanence
          nixarr.nixosModules.default
          authentik-nix.nixosModules.default
          nix-pelican.nixosModules.default
          {
            nixpkgs.overlays = [
              nix-pelican.overlays.default
              copyparty.overlays.default
            ];
          }
          copyparty.nixosModules.default
          ./hosts/mangrove
          ./modules/nixos
        ];
      };

      nixosConfigurations.mangrove-iso = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit inputs; };
        modules = [
          disko.nixosModules.disko
          {
            environment.systemPackages = [ pkgs.git ];
            boot.zfs.forceImportRoot = false;
            image.modules."iso-installer" = {
              imports = [
                "${nixpkgs}/nixos/modules/profiles/minimal.nix"
                "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-base.nix"
              ];
              isoImage.squashfsCompression = "zstd -Xcompression-level 6";
              isoImage.edition = pkgs.lib.mkOverride 500 "minimal";
              image.baseName = pkgs.lib.mkForce "mangrove-installer";
              documentation.man.enable = pkgs.lib.mkOverride 500 true;
              documentation.doc.enable = pkgs.lib.mkOverride 500 true;
              fonts.fontconfig.enable = pkgs.lib.mkOverride 500 false;
              environment.systemPackages = [
                disko.packages.${system}.disko
                (pkgs.writeShellScriptBin "install-mangrove" ''
                  set -euo pipefail
                  echo "==> Installing mangrove from github:davisschenk/nixos-homelab#mangrove"
                  echo "==> This will ERASE /dev/nvme0n1 and /dev/sda. Ctrl-C to abort."
                  read -rp "Press Enter to continue..."
                  sudo disko-install \
                    --flake "github:davisschenk/nixos-homelab#mangrove" \
                    --disk nvme /dev/nvme0n1 \
                    --disk hdd /dev/sda
                  echo "==> Done. You may now reboot."
                '')
              ];
            };
          }
        ];
      };

      packages.${system}.mangrove-iso =
        self.nixosConfigurations.mangrove-iso.config.system.build.images."iso-installer";
    };
}
