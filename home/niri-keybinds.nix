{ cfg, lib }:

let
  source = builtins.readFile ../configs/niri/cfg/keybinds.kdl;
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

  render = line:
    let
      disabled = "/- " + line;
      spawns = program: lib.hasInfix ''{ spawn "${program}"'' line
        || lib.hasInfix ''{spawn "${program}"'' line;
      key = builtins.match "[[:space:]]*([^[:space:]]+).*" line;
      replacement = if key == null then null else mediaFallbacks.${builtins.head key} or null;
    in
    if spawns "zen-beta" && !cfg.apps.zen.enable then
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
