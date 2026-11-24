{ config, ... }:

{
  imports = [ ./hardware-configuration.nix ];

  networking.hostName = "vmware";
  nixpkgs.hostPlatform = "x86_64-linux";

  # All profiles use Wayland or a TTY. The headless package supplies the
  # system daemon without the X11 session helper, vmmouse or vmblock mount.
  virtualisation.vmware.guest = {
    enable = true;
    headless = true;
  };

  # Workstation supplies a virtual SVGA device. Linux binds vmwgfx through
  # PCI and the graphical profiles already enable Mesa via hardware.graphics.
  boot.loader = {
    efi.canTouchEfiVariables = true;
    grub = {
      device = "nodev";
      efiSupport = true;
    };
  };

  assertions = [
    {
      assertion = (config.fileSystems.${config.boot.loader.efi.efiSysMountPoint}.fsType or null) == "vfat";
      message = "VMware: добавьте аппаратные данные гостя и укажите точку монтирования тома EFI (vfat). См. docs/VMWARE.md.";
    }
  ];
}
