{ config, modulesPath, ... }:

{
  imports = [ (modulesPath + "/virtualisation/qemu-vm.nix") ];

  networking.hostName = "vladik-vm";
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

  # Disposable test login for this VM only.
  users.users.${config.mySystem.user}.initialPassword = "vm-only";
}
