{
  description = "NixOS Владислава · ThinkPad, Intel MacBook T2, VMware и тестовая ВМ QEMU";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-hardware = {
      url = "github:NixOS/nixos-hardware";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    minegrub = {
      url = "github:Lxtharia/minegrub-theme";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    minegrub-world = {
      url = "github:Lxtharia/minegrub-world-sel-theme";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    zen = {
      url = "github:0xc000022070/zen-browser-flake";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };
    t2fanrd = {
      url = "github:GnomedDev/T2FanRD";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ nixpkgs, home-manager, ... }:
    let
      system = "x86_64-linux";

      mkHost = hostDir: nixpkgs.lib.nixosSystem {
        specialArgs = { inherit inputs hostDir; };
        modules = [
          home-manager.nixosModules.home-manager
          ./modules/system/base.nix
          ./modules/system/workstation.nix
          ./modules/boot/grub.nix
          ./modules/desktop/shared.nix
          ./modules/desktop/niri.nix
          ./modules/desktop/plasma.nix
          (hostDir + "/configuration.nix")
        ];
      };

      hosts = {
        thinkpad = mkHost ./hosts/thinkpad;
        macbook = mkHost ./hosts/macbook;
        vm = mkHost ./hosts/vm;
        vmware = mkHost ./hosts/vmware;
      };
    in
    {
      nixosConfigurations = hosts;

      packages.${system}.vm = hosts.vm.config.system.build.vm;
      checks.${system} = import ./scripts/checks.nix {
        pkgs = nixpkgs.legacyPackages.${system};
        inherit hosts;
      };

      formatter.${system} = nixpkgs.legacyPackages.${system}.nixfmt;
    };
}
