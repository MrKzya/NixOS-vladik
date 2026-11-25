{ config, inputs, lib, ... }:

let
  theme = config.mySystem.grub.theme;
in
{
  imports = [
    inputs.minegrub.nixosModules.default
    inputs.minegrub-world.nixosModules.default
  ];

  options.mySystem.grub.theme = lib.mkOption {
    type = lib.types.enum [ "minegrub" "world-selection" "none" ];
    default = "minegrub";
    description = "Тема меню GRUB.";
  };

  config.boot.loader = {
    efi.canTouchEfiVariables = lib.mkDefault false;

    grub = {
      enable = true;
      configurationLimit = 10;
      useOSProber = lib.mkDefault false;
      minegrub-theme = {
        enable = theme == "minegrub";
        # Retain the artwork shipped with the theme.
        splash = "";
        boot-options-count = 2; # Current generation and the previous-generations submenu.
      };
      minegrub-world-sel.enable = theme == "world-selection";
    };
  };
}
