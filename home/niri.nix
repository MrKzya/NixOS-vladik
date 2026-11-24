{ hostDir }:
{ config, lib, nixosConfig, pkgs, ... }:

let
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
    (map (name: "niri/cfg/${name}.kdl") [ "animation" "input" "keybinds" "kanagawa" "layout" "misc" "rules" ])
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
    "autostart/polkit-gnome-authentication-agent-1.desktop".text = ''
      [Desktop Entry]
      Type=Application
      Hidden=true
    '';
    "dms/themes/kanagawa/theme.json".source = dms + "/themes/kanagawa/theme.json";
  };

  # Mutable files survive the activation of Gaming and Minimal.
  home.activation.seedNiriDesktop = lib.hm.dag.entryAfter [ "linkGeneration" ] (
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
    + seed ../configs/vicinae/settings.json "vicinae/settings.json"
    + lib.concatMapStrings (name:
      seed (base + "/dms/${name}") "niri/dms/${name}"
    ) (builtins.attrNames (builtins.readDir (base + "/dms")))
  );

  home.activation.applyDmsWallpaperDefault = lib.hm.dag.entryAfter [ "seedNiriDesktop" ] ''
    run ${lib.getExe applyWallpaper} ${lib.escapeShellArgs [ config.xdg.stateHome wallpaper ]}
  '';
}
