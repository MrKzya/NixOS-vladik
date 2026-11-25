{ config, ... }:

{
  imports = [ ./hardware-configuration.nix ];

  networking.hostName = "vmware";
  nixpkgs.hostPlatform = "x86_64-linux";

  mySystem = {
    desktop = {
      niri.enable = true;
      plasma.enable = false;
      dms.enable = true;
      vicinae.enable = true;
      defaultSession = null; # Niri first, then Plasma when enabled.
    };

    apps = {
      firefox.enable = true;
      zen.enable = false;
      telegram.enable = true;
      vesktop.enable = false;
      obsidian.enable = true;
      vscode.enable = true;
      zed.enable = false;
      kitty.enable = true;
      nautilus.enable = true;
      obs.enable = false;
      mpv.enable = false;
      vlc.enable = false;
      karing.enable = true;
      tgProxy.enable = true;
      gpuScreenRecorder.enable = false;
      starship.enable = true;
      fastfetch.enable = true;
      pwgen.enable = true;
      tmux.enable = true;
      playerctl.enable = true;
    };

    gaming = {
      steam.enable = false;
      heroic.enable = false;
      lutris.enable = false;
      protonupQt.enable = false;
      prismLauncher.enable = false;
      gamemode.enable = false;
      mangohud.enable = false;
    };

    system = {
      flatpak.enable = false;
      development.enable = true;
      appimage.enable = false;
      nixLd.enable = false;
      osProber.enable = true;
    };

    bluetooth.enable = false;
    cursor.size = 24;
    grub.theme = "minegrub";
  };

  # The configured desktops use Wayland. The headless package supplies the
  # system daemon without the X11 session helper, vmmouse or vmblock mount.
  virtualisation.vmware.guest = {
    enable = true;
    headless = true;
  };

  # Workstation supplies a virtual SVGA device. Linux binds vmwgfx through
  # PCI and the graphical modules enable Mesa via hardware.graphics.
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
