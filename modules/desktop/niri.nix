{ lib, pkgs, hostDir, ... }:

{
  programs = {
    niri.enable = true;
    dux-shell = {
      enable = true;
      systemd.target = "niri.service";
      plugins.dankKbdLayout.src = ../../configs/dms/dankKbdLayout;
    };
    dux-search = {
      enable = true;
      systemd.target = "niri.service";
    };
  };

  security.pam.services.dankshell = { };
  programs.dconf.enable = true;
  services = {
    upower.enable = true;
    gvfs.enable = true;
  };
  environment.systemPackages = with pkgs; [
    dux-gop
    glib.bin
    xrdb
    libnotify
    polkit_gnome
    vicinae
    xwayland-satellite
  ];
  xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-gtk ];

  systemd.user.services.dms = {
    after = [ "niri.service" ];
    partOf = [ "niri.service" ];
  };

  systemd.user.services.dsearch = {
    after = [ "niri.service" ];
    partOf = [ "niri.service" ];
  };

  systemd.user.services.vicinae = {
    description = "Vicinae launcher for Niri";
    wantedBy = [ "niri.service" ];
    after = [ "niri.service" ];
    partOf = [ "niri.service" ];
    unitConfig.ConditionEnvironment = "WAYLAND_DISPLAY";
    environment.USE_LAYER_SHELL = "1";
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
