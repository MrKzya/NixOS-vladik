{ config, lib, pkgs, hostDir, ... }:

let
  cfg = config.mySystem;
  niri = cfg.desktop.niri.enable;
  dms = cfg.desktop.dms.enable;
  vicinae = cfg.desktop.vicinae.enable;
  niriUnit = [ "niri.service" ];
in

lib.mkIf niri {
  programs = {
    niri = {
      enable = true;
      useNautilus = cfg.apps.nautilus.enable;
    };
    dux-shell = lib.mkIf dms {
      enable = true;
      systemd.target = "niri.service";
      plugins.dankKbdLayout.src = ../../configs/dms/dankKbdLayout;
    };
    dux-search = lib.mkIf dms {
      enable = true;
      systemd.target = "niri.service";
    };
  };

  security.pam.services.dankshell = lib.mkIf dms { };
  programs.dconf.enable = true;
  services = {
    upower.enable = true;
  };
  environment.systemPackages = with pkgs; [
    glib.bin
    xrdb
    libnotify
    xwayland-satellite
    qt6.qtwayland
  ] ++ lib.optionals dms [ pkgs.dux-gop ]
    ++ lib.optionals (!dms) [ config.services.pipewire.wireplumber.package ]
    ++ lib.optionals vicinae [ pkgs.vicinae pkgs.nodejs ];
  fonts.packages = with pkgs; [ inter fira-code ];
  xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-gtk ];

  systemd.user.services.dms = lib.mkIf dms {
    after = niriUnit;
    partOf = niriUnit;
  };

  systemd.user.services.dsearch = lib.mkIf dms {
    after = niriUnit;
    partOf = niriUnit;
  };

  systemd.user.services.niri-polkit = lib.mkIf (!dms) {
    description = "Polkit authentication agent for Niri";
    wantedBy = niriUnit;
    after = niriUnit;
    partOf = niriUnit;
    serviceConfig.ExecStart = "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1";
  };

  systemd.user.services.vicinae = lib.mkIf vicinae {
    description = "Vicinae launcher for Niri";
    wantedBy = niriUnit;
    after = niriUnit;
    partOf = niriUnit;
    unitConfig.ConditionEnvironment = "WAYLAND_DISPLAY";
    enableDefaultPath = false;
    environment = {
      USE_LAYER_SHELL = "1";
      PATH = lib.concatStringsSep ":" [
        "/etc/profiles/per-user/%u/bin"
        "/run/wrappers/bin"
        "/run/current-system/sw/bin"
        (lib.makeBinPath [ pkgs.pulseaudio ]) # pactl talks to PipeWire's PulseAudio server.
      ];
    };
    serviceConfig = {
      ExecStart = "${lib.getExe pkgs.vicinae} server";
      Restart = "on-failure";
      RestartSec = 2;
    };
  };

  home-manager.sharedModules = [
    (import ../../home/niri.nix { inherit hostDir; })
  ];
}
