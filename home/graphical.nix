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

  xdg.configFile = {
    "kitty/kitty.conf".source = ../configs/kitty/kitty.conf;
    "kitty/kanagawa.conf".source = ../configs/kitty/kanagawa.conf;
    "kitty/current-theme.conf".source = ../configs/kitty/themes/kanagawa-generated.conf;
    "kitty/themes/kanagawa-generated.conf".source = ../configs/kitty/themes/kanagawa-generated.conf;
  };
}
