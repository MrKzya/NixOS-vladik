{ config, lib, pkgs, ... }:

let
  cfg = config.mySystem;
in
{
  options.mySystem = {
    development.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Установить инструменты разработки и VS Code в Default.";
    };
    binaryCompatibility.enable = lib.mkEnableOption "nix-ld и поддержку запуска AppImage";
    networkApps.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Установить Karing и TG WS Proxy в Default.";
    };
  };

  config = lib.mkIf config.programs.niri.enable {
    programs.nix-ld.enable = cfg.binaryCompatibility.enable;
    programs.appimage = {
      enable = cfg.binaryCompatibility.enable;
      binfmt = cfg.binaryCompatibility.enable;
    };

    environment.systemPackages = [ pkgs.os-prober ];
    home-manager.sharedModules = [ ../../home/packages.nix ];
  };
}
