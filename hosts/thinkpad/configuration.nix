{ config, lib, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./packages.nix
  ];

  networking.hostName = "thinkpad";
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

    bluetooth.enable = true;
    cursor.size = 24;
    grub.theme = "minegrub";
  };

  hardware.enableRedistributableFirmware = true;
  services.power-profiles-daemon.enable = lib.mkDefault config.services.displayManager.enable;

  assertions = [
    {
      assertion = !config.boot.loader.grub.efiSupport
        || (config.fileSystems.${config.boot.loader.efi.efiSysMountPoint}.fsType or null) == "vfat";
      message = "ThinkPad: для UEFI укажите настоящий ESP (vfat) и его точку монтирования.";
    }
  ];

  # Confirm firmware mode and the actual ESP in hardware-configuration.local.nix.
  boot.loader.grub = {
    device = "nodev";
    efiSupport = true;
  };
}
