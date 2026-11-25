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
    # Only the MacBook kernel uses the compiler, patches and configuration of T2 Live.
    t2-kernel-nixpkgs.url = "github:NixOS/nixpkgs/567a49d1913ce81ac6e9582e3553dd90a955875f";
    t2-kernel-hardware = {
      url = "github:NixOS/nixos-hardware/875776f0252fcb8618bb948640a0d1f7a5b362be";
      inputs.nixpkgs.follows = "t2-kernel-nixpkgs";
    };
    t2fanrd = {
      url = "github:GnomedDev/T2FanRD";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ nixpkgs, home-manager, ... }:
    let
      system = "x86_64-linux";

      mkHost = hostDir:
        let installed = builtins.pathExists (hostDir + "/installer.local.nix");
        in
        nixpkgs.lib.nixosSystem {
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
          ]
          ++ nixpkgs.lib.optional installed (hostDir + "/installer.local.nix")
          ++ nixpkgs.lib.optional (!installed && hostDir == ./hosts/vm) ./hosts/vm/qemu.nix;
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

      packages.${system} = nixpkgs.lib.optionalAttrs (!(builtins.pathExists ./hosts/vm/installer.local.nix)) {
        vm = hosts.vm.config.system.build.vm;
      };
      checks.${system} = import ./scripts/checks.nix {
        pkgs = nixpkgs.legacyPackages.${system};
        inherit hosts;
      };

      formatter.${system} = nixpkgs.legacyPackages.${system}.nixfmt;
    };
}
