{ config, lib, pkgs, ... }:

let
  cursorSize = config.mySystem.cursor.size;
in
{
  hardware.graphics.enable = true;
  hardware.bluetooth.enable = config.mySystem.bluetooth.enable;

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
  };
  services.udev.packages = [ pkgs.brightnessctl ];
  security.rtkit.enable = true;
  security.polkit.enable = true;

  fonts.packages = with pkgs; [ nerd-fonts.jetbrains-mono ];

  services.displayManager.ly = {
    enable = true;
    x11Support = false;
    settings = import ./ly-settings.nix { inherit lib; } // {
      # The module uses this for both the generated INI and TTYPath.
      tty = lib.mkForce 2;
    };
  };
  systemd.defaultUnit = "graphical.target";
  systemd.targets.getty.wants = [ "autovt@tty1.service" ];
  systemd.services.display-manager = {
    after = [ "autovt@tty2.service" "getty@tty2.service" ];
    conflicts = lib.mkForce [ "autovt@tty2.service" "getty@tty2.service" ];
  };

  environment = {
    systemPackages = with pkgs; [ brightnessctl playerctl ];
    sessionVariables = {
      XCURSOR_THEME = "macOS";
      XCURSOR_SIZE = toString cursorSize;
    };
  };

  home-manager.sharedModules = [ ../../home/graphical.nix ];
}
