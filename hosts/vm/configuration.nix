{ config, modulesPath, ... }:

{
  imports = [ (modulesPath + "/virtualisation/qemu-vm.nix") ];

  networking.hostName = "vladik-vm";
  nixpkgs.hostPlatform = "x86_64-linux";
  virtualisation = {
    useBootLoader = true;
    useEFIBoot = true;
    cores = 4;
    memorySize = 6144;
    diskSize = 32768;
  };

  boot.loader.grub = {
    efiSupport = true;
    efiInstallAsRemovable = true;
  };

  # Disposable test login for this VM only, shared by all guest profiles.
  users.users.${config.mySystem.user}.initialPassword = "vm-only";
}
