{ config, lib, ... }:

let
  cfg = config.mySystem.laptopPower;
  dms = config.mySystem.desktop.niri.enable && config.mySystem.desktop.dms.enable;
  lid = if cfg.suspend.enable then "suspend" else "ignore";
  seconds = default: description: lib.mkOption {
    type = lib.types.ints.positive;
    inherit default description;
  };
in
{
  options.mySystem.laptopPower = {
    enable = lib.mkEnableOption "laptop power defaults for Niri + DMS" // { default = true; };
    suspend.enable = lib.mkEnableOption "automatic battery and lid suspend" // { default = true; };
    batteryDisplaySeconds = seconds 120 "Display timeout on battery.";
    acDisplaySeconds = seconds 600 "Display timeout on mains power.";
    lockDelaySeconds = seconds 300 "Delay between display timeout and session lock.";
    batterySuspendSeconds = seconds 900 "Total idle time before suspension on battery.";
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    (lib.mkIf (config.mySystem ? macbook || !cfg.suspend.enable) {
      systemd.sleep.settings.Sleep.AllowSuspend = cfg.suspend.enable;
    })
    (lib.mkIf dms {
      # DMS owns idle actions, logind owns only the lid event.
      services.logind.settings.Login = {
        IdleAction = "ignore";
        HandleLidSwitch = lid;
        HandleLidSwitchExternalPower = lid;
        HandleLidSwitchDocked = lid;
      };

      environment.etc."dms/cli-policy.json".text = builtins.toJSON {
        policy_version = 1;
        lock_settings = {
          lockBeforeSuspend = true;
          loginctlLockIntegration = true;
        };
      };

      assertions = [{
        assertion = !cfg.suspend.enable ||
          cfg.batterySuspendSeconds >= cfg.batteryDisplaySeconds + cfg.lockDelaySeconds;
        message = "Laptop idle suspend must allow the display-off and lock delays.";
      }];
    })
  ]);
}
