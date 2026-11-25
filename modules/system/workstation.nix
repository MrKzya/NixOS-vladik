{ config, inputs, lib, pkgs, ... }:

let
  cfg = config.mySystem;
  hasDesktop = cfg.desktop.niri.enable || cfg.desktop.plasma.enable;
  wineLaunchers = cfg.gaming.heroic.enable || cfg.gaming.lutris.enable;
  mkSwitches = specs: lib.mapAttrs (name: enabled: {
    enable = lib.mkEnableOption "mySystem component ${name}" // { default = enabled; };
  }) specs;
  enabledPackages = options: packages:
    lib.concatLists (lib.mapAttrsToList (name: package:
      lib.optional options.${name}.enable package
    ) packages);
in
{
  options.mySystem = {
    apps = mkSwitches {
      firefox = true;
      zen = false;
      telegram = true;
      vesktop = false;
      obsidian = true;
      vscode = true;
      zed = false;
      kitty = true;
      nautilus = true;
      obs = false;
      mpv = false;
      vlc = false;
      karing = true;
      tgProxy = true;
      gpuScreenRecorder = false;
      starship = true;
      fastfetch = true;
      pwgen = true;
      tmux = true;
      playerctl = true;
    };
    gaming = mkSwitches {
      steam = false;
      heroic = false;
      lutris = false;
      protonupQt = false;
      prismLauncher = false;
      gamemode = false;
      mangohud = false;
    };
    system = mkSwitches {
      flatpak = false;
      development = true;
      appimage = false;
      nixLd = false;
      osProber = true;
    };
  };

  config = lib.mkMerge [
    {
      home-manager.users.${cfg.user}.home.packages = with pkgs;
        enabledPackages cfg.apps {
          inherit firefox obsidian vscode vesktop kitty nautilus mpv vlc starship fastfetch pwgen tmux playerctl;
          zen = inputs.zen.packages.${stdenv.hostPlatform.system}.beta;
          telegram = telegram-desktop;
          zed = zed-editor;
          obs = obs-studio;
          karing = callPackage ../../pkgs/karing.nix { };
          tgProxy = callPackage ../../pkgs/tg-ws-proxy.nix { };
        }
        ++ enabledPackages cfg.gaming {
          inherit heroic lutris mangohud;
          protonupQt = protonup-qt;
          prismLauncher = prismlauncher;
        }
        ++ lib.optionals cfg.system.development.enable [
          gcc gnumake binutils bison fakeroot file findutils flex gettext gawk
          diffutils m4 patch pkg-config autoconf automake libtool which
        ];

      home-manager.sharedModules = lib.optional cfg.apps.kitty.enable ../../home/kitty.nix;

      environment.systemPackages = lib.optional cfg.system.osProber.enable pkgs.os-prober;
      services.gvfs.enable = cfg.apps.nautilus.enable && hasDesktop;
      programs = {
        steam.enable = cfg.gaming.steam.enable;
        gamemode.enable = cfg.gaming.gamemode.enable;
        gpu-screen-recorder.ui.enable = cfg.apps.gpuScreenRecorder.enable;
        nix-ld.enable = cfg.system.nixLd.enable;
        appimage = {
          enable = cfg.system.appimage.enable;
          binfmt = cfg.system.appimage.enable;
        };
      };
      services.flatpak.enable = cfg.system.flatpak.enable;
    }
    (lib.mkIf cfg.system.flatpak.enable {
      xdg.portal.enable = true;
      xdg.portal.extraPortals = lib.optional (!hasDesktop) pkgs.xdg-desktop-portal-gtk;
      xdg.portal.config.common.default = lib.mkDefault "gtk";
    })
    (lib.mkIf wineLaunchers {
      hardware.graphics = {
        enable = true;
        enable32Bit = true;
      };
      services.pipewire.alsa.support32Bit = lib.mkDefault config.services.pipewire.alsa.enable;
    })
  ];
}
