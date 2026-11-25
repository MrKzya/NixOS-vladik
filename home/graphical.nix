{ nixosConfig, pkgs, ... }:

{
  xdg.dataFile."wallpapers/Oboi.jpg".source = builtins.path {
    path = ../assets/wallpapers/Oboi.jpg;
    name = "nixos-vladik-wallpaper.jpg";
  };

  home.pointerCursor = {
    enable = true;
    package = pkgs.apple-cursor;
    name = "macOS";
    size = nixosConfig.mySystem.cursor.size;
    dotIcons.enable = true;
  };
}
