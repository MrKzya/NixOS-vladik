{ config, lib, pkgs, ... }:

{
  options.mySystem.macbook.adjacentSwipe.enable = lib.mkEnableOption
    "short three-finger swipes between adjacent Niri columns (experimental)";

  config = {
    programs.niri.package = lib.mkIf (config.programs.niri.enable && config.mySystem.macbook.adjacentSwipe.enable)
      (pkgs.niri.overrideAttrs (old: {
        patches = (old.patches or [ ]) ++ [ ./patches/niri-adjacent-swipe.patch ];
      }));

    systemd.services.display-manager = lib.mkIf config.services.displayManager.ly.enable {
      after = [ "systemd-vconsole-setup.service" ];
      serviceConfig.ExecStartPre = lib.mkAfter [
        "-${pkgs.kbd}/bin/setfont -C /dev/tty${toString config.services.displayManager.ly.settings.tty} ${pkgs.terminus_font}/share/consolefonts/ter-u32n.psf.gz"
      ];
    };
  };
}
