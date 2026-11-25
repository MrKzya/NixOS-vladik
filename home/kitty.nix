{ ... }:

{
  xdg.configFile = {
    "kitty/kitty.conf".source = ../configs/kitty/kitty.conf;
    "kitty/kanagawa.conf".source = ../configs/kitty/kanagawa.conf;
    "kitty/current-theme.conf".source = ../configs/kitty/themes/kanagawa-generated.conf;
    "kitty/themes/kanagawa-generated.conf".source = ../configs/kitty/themes/kanagawa-generated.conf;
  };
}
