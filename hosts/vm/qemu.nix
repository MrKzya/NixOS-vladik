{ config, modulesPath, ... }:

{
  imports = [ (modulesPath + "/virtualisation/qemu-vm.nix") ];

  virtualisation = {
    useBootLoader = true;
    useEFIBoot = true;
    cores = 4;
    memorySize = 6144;
    diskSize = 32768;
  };

  # Disposable test login for this VM only.
  users.users.${config.mySystem.user}.initialPassword = "vm-only";
}
