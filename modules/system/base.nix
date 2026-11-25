{ config, inputs, lib, pkgs, ... }:

let
  cfg = config.mySystem;
in
{
  options.mySystem = {
    user = lib.mkOption {
      type = lib.types.str;
      default = "vladik";
      description = "Локальная учётная запись, общая для всех профилей хоста.";
    };
    bluetooth.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Включить Bluetooth в графических профилях этого хоста.";
    };
    cursor.size = lib.mkOption {
      type = lib.types.ints.positive;
      default = 24;
      description = "Размер курсора в графических профилях этого хоста.";
    };
  };

  config = {
    system.stateVersion = "26.05";
    nix.settings = {
      experimental-features = [ "nix-command" "flakes" ];
      auto-optimise-store = lib.mkDefault true;
    };
    nix.gc = {
      automatic = lib.mkDefault true;
      dates = lib.mkDefault "weekly";
      options = lib.mkDefault "--delete-older-than 14d";
    };

    nixpkgs.config.allowUnfreePredicate = pkg:
      builtins.elem (lib.getName pkg) [
        "apple_cursor"
        "brcm-firmware"
        "obsidian"
        "vscode"
        "steam"
        "steam-original"
        "steam-run"
        "steam-unwrapped"
      ];

    networking.networkmanager.enable = true;
    programs.fish.enable = true;

    # The first password is set during installation on the target.
    users.users.${cfg.user} = {
      isNormalUser = true;
      shell = pkgs.fish;
      extraGroups = [ "wheel" "networkmanager" ];
    };

    environment.systemPackages = with pkgs; [
      curl
      dosfstools
      git
      iproute2
      nano
      ntfs3g
      ripgrep
      tree
    ];

    home-manager = {
      extraSpecialArgs = { inherit inputs; };
      useGlobalPkgs = true;
      useUserPackages = true;
      sharedModules = [ ../../home/common.nix ];
      users.${cfg.user} = { };
    };
  };
}
