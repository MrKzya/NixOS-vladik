{ config, lib, pkgs, ... }:

let
  cfg = config.mySystem.macbook.macOSKeybindings;
  enabled = cfg.enable && config.mySystem.desktop.niri.enable;
  group = "macbook-remap";
  upstream = lib.getExe pkgs.xremap.niri;
  internalName = "Apple Inc. Apple Internal Keyboard / Trackpad";
  internalDevice = "/dev/input/macbook-internal-keyboard";
  fnDevice = if cfg.fnDevice == null || cfg.fnDevice == internalName then internalDevice else cfg.fnDevice;
  hasFn = pkgs.writeShellScript "macbook-keyboard-has-fn" ''
    # Kernel sysfs key bitmap, most significant machine word first (x86_64).
    read -r -a bits < "/sys$1/device/capabilities/key" || exit 1
    key=${if cfg.fnKey == "KEY_WAKEUP" then "143" else "464"}
    wordIndex=$((''${#bits[@]} - 1 - key / 64))
    (( wordIndex >= 0 )) || exit 1
    word=''${bits[wordIndex]}
    lowWord=''${bits[-1]}
    # Require KEY_A and KEY_SPACE on the same device as Fn.
    [[ $lowWord =~ ^[[:xdigit:]]+$ ]] || exit 1
    (( ((16#$lowWord >> 30) & 1) && ((16#$lowWord >> 57) & 1) )) || exit 1
    [[ $word =~ ^[[:xdigit:]]+$ ]] && (( (16#$word >> (key % 64)) & 1 ))
  '';
  browser = [ "/(?i)^(firefox|firefox-esr|org\\.mozilla\\.firefox|zen|zen-beta|app\\.zen_browser\\.zen|chromium|google-chrome)$/" ];
  editor = [ "/(?i)^(code|code-url-handler|com\\.visualstudio\\.code)$/" ];
  obsidian = [ "/(?i)^(obsidian|md\\.obsidian\\.obsidian)$/" ];
  # Use app ID matching without translating the modifier itself.
  mapFor = name: only: remap: { inherit name remap; application = { inherit only; }; exact_match = true; };
  keymap = [
    (mapFor "Browser tabs and navigation" browser {
      Super-t = "Ctrl-t"; Super-w = "Ctrl-w"; Super-Shift-t = "Ctrl-Shift-t";
      Super-l = "Ctrl-l"; Super-r = "Ctrl-r"; Super-Shift-r = "Ctrl-Shift-r";
      Super-n = "Ctrl-n"; Super-o = "Ctrl-o";
    })
    (mapFor "VS Code" editor {
      Super-w = "Ctrl-w"; Super-Shift-t = "Ctrl-Shift-t";
      # Ctrl+T opens Quick Symbols in VS Code. Open a blank editor instead.
      Super-t = "Ctrl-n";
      Super-n = "Ctrl-Shift-n"; Super-o = "Ctrl-o";
    })
    (mapFor "Obsidian tabs and files" obsidian {
      Super-t = "Ctrl-t"; Super-w = "Ctrl-w"; Super-Shift-t = "Ctrl-Shift-t";
      Super-o = "Ctrl-o";
    })
  ];
  mapping = pkgs.writeText "macbook-xremap.json" (builtins.toJSON {
    inherit keymap;
    modmap = lib.optional (cfg.fnKey != null) {
      name = "Fn tap on the verified internal keyboard";
      device.only = [ fnDevice ];
      remap.${cfg.fnKey} = {
        tap = "F24";
        hold = cfg.fnKey;
        tap_timeout_millis = 180;
        hold_threshold_millis = 0;
      };
    };
  });
in
{
  options.mySystem.macbook.macOSKeybindings = {
    enable = lib.mkEnableOption "MacBook Command shortcuts in Niri and supported apps";
    fnKey = lib.mkOption {
      type = lib.types.nullOr (lib.types.enum [ "KEY_FN" "KEY_WAKEUP" ]);
      default = "KEY_FN";
      description = "Fn evdev event measured on the active T2 driver.";
    };
    fnDevice = lib.mkOption {
      type = lib.types.nullOr lib.types.nonEmptyStr;
      default = null;
      description = "Optional override for the persistent internal keyboard device. Null selects the verified device via udev.";
    };
  };

  config = lib.mkIf enabled {
    users.groups.${group} = { };
    boot.kernelModules = [ "uinput" ];
    # hid_apple's media-first mode leaves F1–F12 available while Fn is held.
    boot.extraModprobeConfig = "options hid_apple fnmode=1";
    services.udev.extraRules = ''
      SUBSYSTEM=="input", KERNEL=="event*", ENV{ID_INPUT_KEYBOARD}=="1", GROUP="${group}", MODE="0660"
      SUBSYSTEM=="input", KERNEL=="event*", ENV{ID_INPUT_KEYBOARD}=="1", ENV{ID_INPUT_TOUCHPAD}!="1", ATTRS{name}=="${internalName}", PROGRAM=="${hasFn} %p", SYMLINK+="input/macbook-internal-keyboard"
      SUBSYSTEM=="misc", KERNEL=="uinput", GROUP="${group}", MODE="0660", OPTIONS+="static_node=uinput"
    '';
    security.wrappers.macbook-xremap = {
      source = upstream;
      owner = config.mySystem.user;
      inherit group;
      # Linux requires S_IXGRP for setgid on exec; membership is confined to this wrapper.
      permissions = "u+rx,g+x,g-rw,o-rwx";
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
        StartLimitIntervalSec = 30;
        StartLimitBurst = 3;
      };
      serviceConfig = {
        ExecStartPre = "${upstream} --validate-config ${mapping}";
        ExecStart = "${config.security.wrapperDir}/macbook-xremap --watch=device --no-window-logging --allow-launch=false ${mapping}";
        Restart = "on-failure";
        RestartSec = 2;
      };
    };
  };
}
