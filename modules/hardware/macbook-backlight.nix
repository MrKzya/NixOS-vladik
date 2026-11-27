{ config, lib, pkgs, ... }:

let
  cfg = config.mySystem.macbook.keyboardBacklight;
  backlight = pkgs.writeShellApplication {
    name = "macbook-backlight";
    runtimeInputs = [ pkgs.brightnessctl pkgs.coreutils pkgs.util-linux ];
    text = builtins.readFile ../../scripts/macbook-backlight.sh;
  };
  plugin = pkgs.runCommand "macbook-backlight-dms-plugin" { } ''
    mkdir -p "$out"
    cp ${../../configs/dms/macbookBacklight/plugin.json} "$out/plugin.json"
    substitute ${../../configs/dms/macbookBacklight/Backlight.qml} "$out/Backlight.qml" \
      --replace-fail '@backlight@' ${lib.getExe backlight} \
      --replace-fail '@idleEnabled@' ${lib.boolToString cfg.idle.enable}
  '';
in
{
  options.mySystem.macbook.keyboardBacklight = {
    enable = lib.mkEnableOption "MacBook keyboard and display brightness keys" // { default = true; };
    idle.enable = lib.mkEnableOption "60-second keyboard backlight idle timer in DMS" // { default = true; };
  };

  config = lib.mkIf (cfg.enable && config.mySystem.desktop.niri.enable) {
    environment.systemPackages = [ backlight ];
    # systemd-backlight normally raises a restored display level of zero.
    services.udev.extraRules = ''
      SUBSYSTEM=="backlight", KERNEL=="intel_backlight", ENV{ID_BACKLIGHT_CLAMP}="0"
    '';
    programs.dux-shell.plugins.macbookBacklight = lib.mkIf config.mySystem.desktop.dms.enable {
      src = plugin;
    };
    systemd.user.services.dms.serviceConfig.ExecStopPost = lib.mkIf config.mySystem.desktop.dms.enable
      [ "${lib.getExe backlight} snapshot" ];
  };
}
