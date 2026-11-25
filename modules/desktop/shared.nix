{ config, lib, pkgs, ... }:

let
  cfg = config.mySystem;
  desktop = cfg.desktop;
  cursorSize = cfg.cursor.size;
  enabled = desktop.niri.enable || desktop.plasma.enable;
  session =
    if desktop.defaultSession != null then desktop.defaultSession
    else if desktop.niri.enable then "niri"
    else "plasma";
  enableComponent = name: lib.mkEnableOption name // { default = true; };
in
{
  options.mySystem.desktop = {
    niri.enable = enableComponent "Niri";
    plasma.enable = lib.mkEnableOption "KDE Plasma";
    dms.enable = enableComponent "DMS in the Niri session";
    vicinae.enable = enableComponent "Vicinae in the Niri session";
    defaultSession = lib.mkOption {
      type = lib.types.nullOr (lib.types.enum [ "niri" "plasma" ]);
      default = null;
      description = "NixOS default session. Null prefers Niri when enabled. Ly remembers the last selection.";
    };
  };

  config = lib.mkMerge [
    {
      assertions = [{
        assertion = desktop.defaultSession == null
          || (desktop.defaultSession == "niri" && desktop.niri.enable)
          || (desktop.defaultSession == "plasma" && desktop.plasma.enable);
        message = "mySystem.desktop.defaultSession must be null or select an enabled desktop.";
      }];
      systemd.defaultUnit = if enabled then "graphical.target" else "multi-user.target";
      hardware.bluetooth.enable = cfg.bluetooth.enable;
    }
    (lib.mkIf enabled {
      hardware.graphics.enable = true;

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
      services.displayManager.defaultSession = session;
      systemd.targets.getty.wants = [ "autovt@tty1.service" ];
      systemd.services.display-manager = {
        after = [ "autovt@tty2.service" "getty@tty2.service" ];
        conflicts = lib.mkForce [ "autovt@tty2.service" "getty@tty2.service" ];
      };

      environment = {
        systemPackages = with pkgs; [ brightnessctl ];
        sessionVariables = {
          XCURSOR_THEME = "macOS";
          XCURSOR_SIZE = toString cursorSize;
        };
      };

      home-manager.sharedModules = [ ../../home/graphical.nix ];
    })
  ];
}
