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

    home-manager = {
      url = "github:nix-community/home-manager";
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
      home-manager,
      ...
    }@inputs:
    {
      nixosConfigurations.mangrove = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit inputs; };
        modules = [
          disko.nixosModules.disko
          sops-nix.nixosModules.sops
          impermanence.nixosModules.impermanence
          nixarr.nixosModules.nixarr
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
    };
}
