{ pkgs, hosts }:

let
  inherit (pkgs) lib;
  home = cfg: cfg.home-manager.users.${cfg.mySystem.user};
  packageNames = cfg: map lib.getName (cfg.environment.systemPackages ++ (home cfg).home.packages);
  keybinds = cfg: (home cfg).xdg.configFile."niri/cfg/keybinds.kdl".text;

  checkDesktop = cfg:
    let
      desktop = cfg.mySystem.desktop;
      graphical = desktop.niri.enable || desktop.plasma.enable;
      sessions = cfg.services.displayManager.sessionData.sessionNames or [ ];
      niriDms = desktop.niri.enable && desktop.dms.enable;
      niriVicinae = desktop.niri.enable && desktop.vicinae.enable;
    in
    (builtins.elem "niri" sessions == desktop.niri.enable)
    && (builtins.elem "plasma" sessions == desktop.plasma.enable)
    && (cfg.services.displayManager.ly.enable == graphical)
    && (cfg.systemd.defaultUnit == (if graphical then "graphical.target" else "multi-user.target"))
    && (cfg.programs.dux-shell.enable == niriDms)
    && (cfg.programs.dux-search.enable == niriDms)
    && ((cfg.systemd.user.services ? vicinae) == niriVicinae)
    && ((cfg.systemd.user.services ? niri-polkit) == (desktop.niri.enable && !desktop.dms.enable))
    && (!niriDms || cfg.systemd.user.services.dms.wantedBy == [ "niri.service" ])
    && (!niriVicinae || (
      cfg.systemd.user.services.vicinae.wantedBy == [ "niri.service" ]
      && lib.hasPrefix "/etc/profiles/per-user/%u/bin:" cfg.systemd.user.services.vicinae.environment.PATH
      && lib.hasSuffix "/bin" cfg.systemd.user.services.vicinae.environment.PATH
    ))
    && ((home cfg).home.activation ? applyDmsWallpaperDefault == niriDms)
    && ((home cfg).xdg.dataFile ? "wallpapers/Next/metadata.json" == desktop.plasma.enable);

  evaluate = modules: (hosts.vm.extendModules { inherit modules; }).config;
  desktopCase = settings:
    evaluate [{ mySystem.desktop = lib.mkForce ({
      niri.enable = true;
      plasma.enable = false;
      dms.enable = true;
      vicinae.enable = true;
      defaultSession = null;
    } // settings); }];

  cases = {
    niri = desktopCase { };
    plasma = desktopCase { niri.enable = false; plasma.enable = true; };
    both = desktopCase { plasma.enable = true; defaultSession = "plasma"; };
    tty = desktopCase { niri.enable = false; };
    noVicinae = desktopCase { vicinae.enable = false; };
    noDms = desktopCase { dms.enable = false; };
    steam = evaluate [{ mySystem.gaming.steam.enable = lib.mkForce true; }];
    zen = evaluate [{ mySystem.apps.zen.enable = lib.mkForce true; }];
    noApps = evaluate [({ options, ... }: {
      mySystem.apps = lib.mapAttrs (_: _: { enable = lib.mkForce false; }) options.mySystem.apps;
      mySystem.gaming = lib.mapAttrs (_: _: { enable = lib.mkForce false; }) options.mySystem.gaming;
      mySystem.system = lib.mapAttrs (_: _: { enable = lib.mkForce false; }) options.mySystem.system;
    })];
  };

  test = name: ok:
    assert lib.assertMsg ok "Failed component check: ${name}";
    pkgs.runCommand name { } ''touch "$out"'';

  validateNiri = name: cfg:
    let
      files = lib.filterAttrs (path: _: lib.hasPrefix "niri/" path) (home cfg).xdg.configFile;
      stage = path: file: ''install -Dm644 ${file.source} ${lib.escapeShellArg path}'';
    in
    pkgs.runCommand "niri-${name}-validate" { nativeBuildInputs = [ pkgs.niri ]; } ''
      ${lib.concatStringsSep "\n" (lib.mapAttrsToList stage files)}
      niri validate --config "$PWD/niri/config.kdl"
      touch "$out"
    '';
in
{
  components = test "component-invariants" (lib.all (name:
    let cfg = hosts.${name}.config;
    in checkDesktop cfg
      && cfg.specialisation == { }
      && ((cfg.users.users.${cfg.mySystem.user}.initialPassword == "vm-only") == (name == "vm"))
      && (cfg.virtualisation.vmware.guest.enable == (name == "vmware"))
      && (name != "vmware" || !(cfg.virtualisation ? fileSystems))
      && (builtins.elem "apple-bce" cfg.boot.initrd.kernelModules == (name == "macbook"))
      && lib.all (pkg: !(builtins.elem pkg (packageNames cfg))) [ "noctalia" "noctalia-shell" ]
  ) (builtins.attrNames hosts));

  desktop-matrix = test "desktop-matrix" (
    lib.all checkDesktop (builtins.attrValues cases)
    && cases.both.services.displayManager.defaultSession == "plasma"
    && !cases.plasma.programs.steam.enable
    && !cases.plasma.hardware.graphics.enable32Bit
    && !cases.tty.services.pipewire.enable
    && !cases.tty.services.displayManager.enable
    && cases.steam.programs.steam.enable
    && !cases.steam.services.desktopManager.plasma6.enable
    && cases.steam.hardware.graphics.enable32Bit
    && !cases.niri.hardware.graphics.enable32Bit
    && lib.hasInfix ''spawn "firefox"'' (keybinds cases.niri)
    && lib.hasInfix ''spawn "zen-beta"'' (keybinds cases.zen)
    && lib.hasInfix ''spawn "wpctl"'' (keybinds cases.noDms)
    && lib.all (pkg: !(builtins.elem pkg (packageNames cases.noApps)))
      [ "firefox" "zen-beta" "nautilus" "kitty" "vscode" "starship" "fastfetch" "steam" ]
  );

  niri-optional-bindings = validateNiri "optional-bindings" (evaluate [{
    mySystem = {
      desktop = {
        dms.enable = lib.mkForce false;
        vicinae.enable = lib.mkForce false;
      };
      apps = {
        firefox.enable = lib.mkForce false;
        zen.enable = lib.mkForce false;
        kitty.enable = lib.mkForce false;
        nautilus.enable = lib.mkForce false;
        playerctl.enable = lib.mkForce false;
      };
    };
  }]);

  shell-config = pkgs.runCommand "shell-config" { nativeBuildInputs = [ pkgs.fish ]; } ''
    fish --no-config --no-execute ${../configs/fish/config.fish}
    bash -n ${./seed-config.sh}
    bash -n ${./apply-dms-wallpaper-default.sh}
    target="$PWD/config/settings.json"
    bash ${./seed-config.sh} ${../configs/dms/settings.json} "$target"
    cmp ${../configs/dms/settings.json} "$target"
    printf '%s\n' local-change > "$target"
    bash ${./seed-config.sh} ${../configs/dms/settings.json} "$target"
    grep -Fx local-change "$target"
    touch "$out"
  '';
}
// lib.mapAttrs' (name: host: lib.nameValuePair "niri-${name}" (validateNiri name host.config))
  (lib.filterAttrs (_: host: host.config.programs.niri.enable) hosts)
