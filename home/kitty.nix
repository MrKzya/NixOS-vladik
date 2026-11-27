{ nixosConfig, ... }:

{
  xdg.configFile = {
    "kitty/kitty.conf" = if (nixosConfig.mySystem.macbook.macOSKeybindings.enable or false) then {
      text = (builtins.readFile ../configs/kitty/kitty.conf) + ''
        map super+t new_tab
        map super+w close_tab
      '';
    } else { source = ../configs/kitty/kitty.conf; };
    "kitty/kanagawa.conf".source = ../configs/kitty/kanagawa.conf;
    "kitty/current-theme.conf".source = ../configs/kitty/themes/kanagawa-generated.conf;
    "kitty/themes/kanagawa-generated.conf".source = ../configs/kitty/themes/kanagawa-generated.conf;
  };
}
