{ config, ... }:

{
  imports = [
    ../../modules/hardware/apple-t2.nix
    ./hardware-configuration.nix
    ./packages.nix
  ];

  networking.hostName = "macbook";
  nixpkgs.hostPlatform = "x86_64-linux";
  hardware.enableRedistributableFirmware = true;
  mySystem.bluetooth.enable = true;

  assertions = [
    {
      assertion = (config.fileSystems.${config.boot.loader.efi.efiSysMountPoint}.fsType or null) == "vfat";
      message = "MacBook T2: укажите выделенный Linux ESP (vfat) и его точку монтирования.";
    }
    {
      assertion = config.boot.loader.grub.efiInstallAsRemovable && !config.boot.loader.efi.canTouchEfiVariables;
      message = "MacBook T2: после проверки отдельного Linux ESP включите efiInstallAsRemovable без записи NVRAM.";
    }
  ];

  # Set true in the hardware file after checking the dedicated Linux ESP.
  # boot.loader.grub.efiInstallAsRemovable = true;
  boot.loader.grub = {
    device = "nodev";
    efiSupport = true;
  };
}
