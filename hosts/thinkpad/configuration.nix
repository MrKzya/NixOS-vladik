{ config, lib, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./packages.nix
  ];

  networking.hostName = "thinkpad";
  nixpkgs.hostPlatform = "x86_64-linux";
  hardware.enableRedistributableFirmware = true;
  services.power-profiles-daemon.enable = lib.mkDefault config.services.displayManager.enable;

  mySystem.bluetooth.enable = true;

  assertions = [
    {
      assertion = !config.boot.loader.grub.efiSupport
        || (config.fileSystems.${config.boot.loader.efi.efiSysMountPoint}.fsType or null) == "vfat";
      message = "ThinkPad: для UEFI укажите настоящий ESP (vfat) и его точку монтирования.";
    }
  ];

  # Confirm firmware mode and the actual ESP in hardware-configuration.nix.
  boot.loader.grub = {
    device = "nodev";
    efiSupport = true;
  };
}
