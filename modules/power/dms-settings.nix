cfg:
{
  acMonitorTimeout = cfg.acDisplaySeconds;
  acLockTimeout = cfg.acDisplaySeconds + cfg.lockDelaySeconds;
  acSuspendTimeout = 0;
  batteryMonitorTimeout = cfg.batteryDisplaySeconds;
  batteryLockTimeout = cfg.batteryDisplaySeconds + cfg.lockDelaySeconds;
  batterySuspendTimeout = if cfg.suspend.enable then cfg.batterySuspendSeconds else 0;
  acPostLockMonitorTimeout = 0;
  batteryPostLockMonitorTimeout = 0;
  fadeToDpmsEnabled = false;
  fadeToLockEnabled = false;
  lockBeforeSuspend = true;
  loginctlLockIntegration = true;
}
