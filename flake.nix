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

    impermanence = {
      url = "github:nix-community/impermanence";
      inputs.nixpkgs.follows = "nixpkgs";
    };

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
              isoImage.edition = nixpkgs.lib.mkOverride 500 "minimal";
              image.baseName = nixpkgs.lib.mkForce "mangrove-installer";
              documentation.man.enable = nixpkgs.lib.mkOverride 500 true;
              documentation.doc.enable = nixpkgs.lib.mkOverride 500 true;
              fonts.fontconfig.enable = nixpkgs.lib.mkOverride 500 false;
              environment.systemPackages = [
                disko.packages.${system}.disko
                disko.packages.${system}.disko-install
                (pkgs.writeShellScriptBin "install-mangrove" ''
                  set -euo pipefail
                  echo "==> Installing mangrove from github:davisschenk/nixos-homelab#mangrove"
                  echo "==> This will ERASE nvme-Samsung_SSD_980_PRO_2TB_S76ENL0XB05058E and ata-ST8000DM004-2U9188_ZR162NST. Ctrl-C to abort."
                  read -rp "Press Enter to continue..."
                  sudo ${disko.packages.${system}.disko-install}/bin/disko-install \
                    --mode destroy \
                    --flake "github:davisschenk/nixos-homelab#mangrove" \
                    --disk nvme /dev/disk/by-id/nvme-Samsung_SSD_980_PRO_2TB_S76ENL0XB05058E \
                    --disk hdd /dev/disk/by-id/ata-ST8000DM004-2U9188_ZR162NST
                  echo "==> Done. You may now reboot."
                '')
              ];
            };
          }
        ];
      };

      packages.${system} = {
        mangrove-iso =
          self.nixosConfigurations.mangrove-iso.config.system.build.images."iso-installer";

        coder-workspace-image = import ./modules/nixos/coder/workspace-image.nix {
          # claude-code is unfree; allow without affecting default pkgs
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfreePredicate = pkg: builtins.elem (nixpkgs.lib.getName pkg) [ "claude-code" ];
          };
        };
      };
    };
}
