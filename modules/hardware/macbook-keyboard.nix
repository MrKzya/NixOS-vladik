{ config, lib, pkgs, ... }:

let
  cfg = config.mySystem.macbook.macOSKeybindings;
  enabled = cfg.enable && config.mySystem.desktop.niri.enable;
  group = "macbook-remap";
  browser = [ "/(?i)^(firefox|firefox-esr|org\\.mozilla\\.firefox|zen|zen-beta|app\\.zen_browser\\.zen|chromium|google-chrome)$/" ];
  editor = [ "/(?i)^(code|code-url-handler|com\\.visualstudio\\.code)$/" ];
  obsidian = [ "/(?i)^(obsidian|md\\.obsidian\\.obsidian)$/" ];
  other = [ "/(?i)^(nautilus|org\\.gnome\\.nautilus|telegramdesktop|org\\.telegram\\.desktop)$/" ];
  # Use app ID matching without translating the modifier itself.
  mapFor = name: only: remap: { inherit name remap; application = { inherit only; }; exact_match = true; };
  keymap = [
    (mapFor "Browser tabs and navigation" browser {
      Super-t = "Ctrl-t"; Super-w = "Ctrl-w"; Super-Shift-t = "Ctrl-Shift-t";
      Super-l = "Ctrl-l"; Super-r = "Ctrl-r"; Super-Shift-r = "Ctrl-Shift-r";
      Super-n = "Ctrl-n"; Super-o = "Ctrl-o"; Super-Shift-z = "Ctrl-Shift-z";
    })
    (mapFor "VS Code" editor {
      Super-w = "Ctrl-w"; Super-Shift-t = "Ctrl-Shift-t";
      Super-n = "Ctrl-Shift-n"; Super-o = "Ctrl-o"; Super-Shift-z = "Ctrl-y";
    })
    (mapFor "Obsidian tabs and files" obsidian {
      Super-t = "Ctrl-t"; Super-w = "Ctrl-w"; Super-Shift-t = "Ctrl-Shift-t";
      Super-o = "Ctrl-o"; Super-Shift-z = "Ctrl-Shift-z";
    })
    (mapFor "Editing in known graphical applications" (browser ++ editor ++ obsidian ++ other) {
      Super-c = "Ctrl-c"; Super-v = "Ctrl-v"; Super-x = "Ctrl-x"; Super-a = "Ctrl-a";
      Super-z = "Ctrl-z"; Super-s = "Ctrl-s"; Super-f = "Ctrl-f";
    })
  ];
  mapping = pkgs.writeText "macbook-xremap.json" (builtins.toJSON {
    inherit keymap;
    modmap = lib.optional (cfg.fnKey != null && cfg.fnDevice != null) {
      name = "Fn tap on the verified internal keyboard";
      device.only = [ cfg.fnDevice ];
      remap.${cfg.fnKey} = {
        tap = "F24";
        hold = cfg.fnKey;
        tap_timeout_millis = 180;
      };
    };
  });
in
{
  options.mySystem.macbook.macOSKeybindings = {
    enable = lib.mkEnableOption "MacBook Command shortcuts in Niri and supported apps";
    fnKey = lib.mkOption {
      type = lib.types.nullOr (lib.types.enum [ "KEY_FN" "KEY_WAKEUP" ]);
      default = null;
      description = "Fn evdev event measured on the active T2 driver.";
    };
    fnDevice = lib.mkOption {
      type = lib.types.nullOr lib.types.nonEmptyStr;
      default = null;
      description = "Internal keyboard evdev name or persistent path verified with evtest.";
    };
  };

  config = lib.mkIf enabled {
    assertions = [{
      assertion = (cfg.fnKey == null) == (cfg.fnDevice == null);
      message = "Configure both the verified Fn event and its internal keyboard, or neither.";
    }];
    users.groups.${group} = { };
    boot.kernelModules = [ "uinput" ];
    # hid_apple's media-first mode leaves F1–F12 available while Fn is held.
    boot.extraModprobeConfig = "options hid_apple fnmode=1";
    services.udev.extraRules = ''
      SUBSYSTEM=="input", KERNEL=="event*", ENV{ID_INPUT_KEYBOARD}=="1", GROUP="${group}", MODE="0660"
      SUBSYSTEM=="misc", KERNEL=="uinput", GROUP="${group}", MODE="0660", OPTIONS+="static_node=uinput"
    '';
    security.wrappers.macbook-xremap = {
      source = lib.getExe pkgs.xremap.niri;
      owner = config.mySystem.user;
      inherit group;
      permissions = "u+rx,g-rwx,o-rwx";
      setgid = true;
    };
    systemd.user.services.macbook-shortcuts = {
      description = "MacBook app shortcuts for Niri";
      wantedBy = [ "niri.service" ];
      after = [ "niri.service" ];
      partOf = [ "niri.service" ];
      unitConfig = {
        ConditionUser = config.mySystem.user;
        ConditionEnvironment = "NIRI_SOCKET";
      };
      serviceConfig = {
        ExecStart = "${config.security.wrapperDir}/macbook-xremap --watch=device ${mapping}";
        Restart = "on-failure";
        RestartSec = 2;
      };
    };
  };
}
