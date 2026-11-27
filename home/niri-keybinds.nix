{ cfg, lib }:

let
  source = builtins.readFile ../configs/niri/cfg/keybinds.kdl;
  mac = cfg.macbook.macOSKeybindings.enable or false;
  fn = mac && (cfg.macbook.macOSKeybindings.fnKey or null) != null;
  backlight = cfg.macbook.keyboardBacklight.enable or false;
  moved = [ "Mod+L" "Mod+T" "Mod+W" "Mod+O" "Mod+TAB" ];
  macBind = line:
    let
      key = builtins.match "([[:space:]]*)([^[:space:]]+)(.*)" line;
    in
    if mac && key != null && builtins.elem (builtins.elemAt key 1) moved then
      builtins.head key + lib.replaceStrings [ "Mod+" ] [ "Mod+Alt+" ] (builtins.elemAt key 1) + builtins.elemAt key 2
    else line;
  extra = lib.optionalString (mac && cfg.desktop.vicinae.enable) ''
    Mod+Space repeat=false { spawn "vicinae" "toggle"; }
  '' + lib.optionalString backlight ''
    XF86KbdBrightnessUp allow-when-locked=true { spawn "macbook-backlight" "up"; }
    XF86KbdBrightnessDown allow-when-locked=true { spawn "macbook-backlight" "down"; }
    XF86MonBrightnessUp allow-when-locked=true { spawn "macbook-backlight" "display-up"; }
    XF86MonBrightnessDown allow-when-locked=true { spawn "macbook-backlight" "display-down"; }
  '' + lib.optionalString fn ''
    F24 repeat=false { switch-layout "next"; }
  '';
  # Without DMS, the media keys still work through the common session tools.
  mediaFallbacks = {
    XF86AudioRaiseVolume = ''spawn "wpctl" "set-volume" "-l" "1.0" "@DEFAULT_AUDIO_SINK@" "5%+";'';
    XF86AudioLowerVolume = ''spawn "wpctl" "set-volume" "@DEFAULT_AUDIO_SINK@" "5%-";'';
    XF86AudioMute = ''spawn "wpctl" "set-mute" "@DEFAULT_AUDIO_SINK@" "toggle";'';
    XF86AudioMicMute = ''spawn "wpctl" "set-mute" "@DEFAULT_AUDIO_SOURCE@" "toggle";'';
    XF86AudioNext = ''spawn "playerctl" "next";'';
    XF86AudioPrev = ''spawn "playerctl" "previous";'';
    XF86AudioPlay = ''spawn "playerctl" "play-pause";'';
    XF86AudioPause = ''spawn "playerctl" "play-pause";'';
    XF86MonBrightnessUp = ''spawn "brightnessctl" "set" "+5%";'';
    XF86MonBrightnessDown = ''spawn "brightnessctl" "set" "5%-";'';
  };

  render = original:
    let
      line = macBind original;
      disabled = "/- " + line;
      spawns = program: lib.hasInfix ''{ spawn "${program}"'' line
        || lib.hasInfix ''{spawn "${program}"'' line;
      key = builtins.match "[[:space:]]*([^[:space:]]+).*" line;
      replacement = if key == null then null else mediaFallbacks.${builtins.head key} or null;
    in
    if line == "}" then extra + line
    else if backlight && key != null && builtins.elem (builtins.head key) [ "XF86MonBrightnessUp" "XF86MonBrightnessDown" ] then disabled
    else if fn && cfg.macbook.macOSKeybindings.fnKey == "KEY_WAKEUP"
      && lib.hasPrefix "XF86WakeUp " (lib.trim line) then disabled
    else if spawns "zen-beta" && !cfg.apps.zen.enable then
      if cfg.apps.firefox.enable then
        lib.replaceStrings [ "Open Browser: Zen" "zen-beta" ] [ "Open Browser: Firefox" "firefox" ] line
      else disabled
    else if (spawns "kitty" && !cfg.apps.kitty.enable)
      || (spawns "nautilus" && !cfg.apps.nautilus.enable)
      || (spawns "vicinae" && !cfg.desktop.vicinae.enable) then disabled
    else if spawns "dms" && !cfg.desktop.dms.enable then
      if replacement == null || (!cfg.apps.playerctl.enable && lib.hasInfix ''"playerctl"'' replacement) then disabled
      else builtins.head (lib.splitString "{" line) + "{ ${replacement} }"
    else line;
in
lib.concatMapStringsSep "\n" render (lib.splitString "\n" source)
+ lib.optionalString mac ''
  recent-windows {
      binds {
          Alt+Tab { next-window; }
          Alt+Shift+Tab { previous-window; }
          Alt+grave { next-window filter="app-id"; }
          Alt+Shift+grave { previous-window filter="app-id"; }
          Mod+Tab { next-window; }
          Mod+Shift+Tab { previous-window; }
          Mod+grave { next-window filter="app-id"; }
          Mod+Shift+grave { previous-window filter="app-id"; }
      }
  }
''
