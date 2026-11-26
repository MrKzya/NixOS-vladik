{ nixosConfig, ... }:

let
  mac = nixosConfig.mySystem.macbook.macOSKeybindings.enable or false;
in

{
  xdg.configFile = {
    "kitty/kitty.conf" = if mac then {
      text = (builtins.readFile ../configs/kitty/kitty.conf) + ''
        map super+c copy_to_clipboard
        map super+v paste_from_clipboard
      '';
    } else { source = ../configs/kitty/kitty.conf; };
    "kitty/kanagawa.conf".source = ../configs/kitty/kanagawa.conf;
    "kitty/current-theme.conf".source = ../configs/kitty/themes/kanagawa-generated.conf;
    "kitty/themes/kanagawa-generated.conf".source = ../configs/kitty/themes/kanagawa-generated.conf;
  };
}
