{ hostDir }:
{ config, lib, nixosConfig, pkgs, ... }:

let
  cfg = nixosConfig.mySystem;
  enableDms = cfg.desktop.dms.enable;
  enableVicinae = cfg.desktop.vicinae.enable;
  base = ../configs/niri;
  dms = ../configs/dms;
  configHome = config.xdg.configHome;
  wallpaper = config.xdg.dataFile."wallpapers/Oboi.jpg".source;
  applyWallpaper = pkgs.writeShellApplication {
    name = "apply-dms-wallpaper-default";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.jq
      pkgs.systemd
      nixosConfig.programs.dux-shell.package
      nixosConfig.programs.dux-shell.quickshell.package
    ];
    text = builtins.readFile ../scripts/apply-dms-wallpaper-default.sh;
  };
  cursorSize = nixosConfig.mySystem.cursor.size;
  dmsSettings = builtins.fromJSON (builtins.readFile (dms + "/settings.json"));
  dmsSeed = pkgs.writeText "dms-settings.json" (builtins.toJSON (dmsSettings // {
    customThemeFile = "${configHome}/dms/themes/kanagawa/theme.json";
    cursorSettings = dmsSettings.cursorSettings // { theme = "macOS"; size = cursorSize; };
  }));
  seed = source: target: ''
    run ${pkgs.bash}/bin/bash ${../scripts/seed-config.sh} ${source} ${lib.escapeShellArg "${configHome}/${target}"}
  '';
in
{
  dconf.enable = true;
  dconf.settings."org/gnome/desktop/interface" = {
    cursor-theme = "macOS";
    cursor-size = lib.hm.gvariant.mkInt32 cursorSize;
  };

  xdg.configFile = (lib.genAttrs
    (map (name: "niri/cfg/${name}.kdl") [ "animation" "input" "kanagawa" "layout" "misc" "rules" ])
    (name: { source = base + (lib.removePrefix "niri" name); })
  ) // {
    "niri/config.kdl".source = base + "/config.kdl";
    "niri/cfg/display.kdl".source = hostDir + "/niri/display.kdl";
    "niri/cfg/autostart.kdl".source = hostDir + "/niri/autostart.kdl";
    "niri/cfg/cursor.kdl".text = ''
      cursor {
          xcursor-theme "macOS"
          xcursor-size ${toString cursorSize}
      }
    '';
    "niri/cfg/keybinds.kdl".text = import ./niri-keybinds.nix { inherit cfg lib; };
    "dms/themes/kanagawa/theme.json" = lib.mkIf enableDms { source = dms + "/themes/kanagawa/theme.json"; };
  };

  # The application owns its mutable files, including after a component is disabled.
  home.activation.seedDms = lib.mkIf enableDms (lib.hm.dag.entryAfter [ "linkGeneration" ] (
    ''
      if [[ ! -e ${lib.escapeShellArg "${configHome}/DankMaterialShell/settings.json"} ]]; then
        ${seed dmsSeed "dms/settings.json"}
      fi
    ''
    + ''
      if [[ ! -e ${lib.escapeShellArg "${configHome}/DankMaterialShell/plugin_settings.json"} ]]; then
        ${seed (dms + "/plugin_settings.json") "dms/plugin_settings.json"}
      fi
    ''
    + lib.concatMapStrings (name:
      seed (base + "/dms/${name}") "niri/dms/${name}"
    ) (builtins.attrNames (builtins.readDir (base + "/dms")))
  ));

  home.activation.seedVicinae = lib.mkIf enableVicinae (
    lib.hm.dag.entryAfter [ "linkGeneration" ] (seed ../configs/vicinae/settings.json "vicinae/settings.json")
  );

  home.activation.applyDmsWallpaperDefault = lib.mkIf enableDms (lib.hm.dag.entryAfter [ "seedDms" ] ''
    run ${lib.getExe applyWallpaper} ${lib.escapeShellArgs [ config.xdg.stateHome wallpaper ]}
  '');
}
