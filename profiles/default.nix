{ pkgs, ... }:

{
  imports = [
    ../modules/desktop/shared.nix
    ../modules/desktop/niri.nix
  ];

  system.nixos.tags = [ "Default" ];
  services.displayManager.defaultSession = "niri";

  fonts.packages = with pkgs; [ inter fira-code ];
}
