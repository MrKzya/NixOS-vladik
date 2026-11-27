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
    && ((cfg.environment.etc ? "xdg/kxkbrc") == desktop.plasma.enable)
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

  macbook = hosts.macbook.config;
  thinkpad = hosts.thinkpad.config;
  power = cfg: import ../modules/power/dms-settings.nix cfg.mySystem.laptopPower;
  macNoRemap = (hosts.macbook.extendModules {
    modules = [ { mySystem.macbook.macOSKeybindings.enable = lib.mkForce false; } ];
  }).config;
  macWithKey = key: (hosts.macbook.extendModules {
    modules = [ { mySystem.macbook.macOSKeybindings = {
      fnKey = key;
      fnDevice = "fixture keyboard";
    }; } ];
  }).config;
  macWithFn = macWithKey "KEY_FN";
  macWithoutSuspend = (hosts.macbook.extendModules {
    modules = [ { mySystem.laptopPower.suspend.enable = lib.mkForce false; } ];
  }).config;

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
      && builtins.elem "python3" (packageNames cfg)
      && ((cfg.systemd.user.services ? macbook-shortcuts) ==
        (name == "macbook" && cfg.mySystem.desktop.niri.enable && cfg.mySystem.macbook.macOSKeybindings.enable))
      && ((cfg.mySystem ? laptopPower) == builtins.elem name [ "macbook" "thinkpad" ])
      && ((cfg.users.users.${cfg.mySystem.user}.initialPassword == "vm-only") == (name == "vm" && !(builtins.pathExists ../hosts/vm/installer.local.nix)))
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

  laptop-power = test "laptop-power-and-keyboard" (
    ((power macbook).batterySuspendTimeout == 900)
    && ((power macbook).acSuspendTimeout == 0)
    && ((power thinkpad).batterySuspendTimeout == 900)
    && ((power thinkpad).acSuspendTimeout == 0)
    && ((power thinkpad).batteryMonitorTimeout == 120)
    && ((power thinkpad).acMonitorTimeout == 600)
    && ((power thinkpad).batteryLockTimeout == 420)
    && ((power thinkpad).acLockTimeout == 900)
    && macbook.systemd.sleep.settings.Sleep.AllowSuspend
    && macbook.services.logind.settings.Login.HandleLidSwitchExternalPower == "suspend"
    && macbook.services.logind.settings.Login.IdleAction == "ignore"
    && !macWithoutSuspend.systemd.sleep.settings.Sleep.AllowSuspend
    && ((power macWithoutSuspend).batterySuspendTimeout == 0)
    && macWithoutSuspend.services.logind.settings.Login.HandleLidSwitch == "ignore"
    && !(macbook.systemd.user.services ? swayidle)
    && !(thinkpad.systemd.user.services ? swayidle)
    && (macbook.security.wrappers.macbook-xremap.permissions == "u+rx,g+x,g-rw,o-rwx")
    && macbook.systemd.user.services.macbook-shortcuts.unitConfig.StartLimitBurst == 3
    && lib.hasInfix "Mod+Space repeat=false" (keybinds macbook)
    && lib.hasInfix "Mod+Tab { next-window; }" (keybinds macbook)
    && lib.hasInfix "Mod+Alt+TAB" (keybinds macbook)
    && lib.hasInfix "F24 repeat=false" (keybinds macbook)
    && lib.hasInfix "F24 repeat=false" (keybinds macWithFn)
    && lib.hasInfix ''spawn "macbook-backlight" "display-up"'' (keybinds macbook)
    && !lib.hasInfix ''spawn "macbook-backlight"'' (keybinds cases.niri)
    && lib.hasInfix "/-     XF86WakeUp" (keybinds (macWithKey "KEY_WAKEUP"))
    && !(macNoRemap.systemd.user.services ? macbook-shortcuts)
    && !lib.hasInfix "Mod+Space repeat=false" (keybinds macNoRemap)
    && !lib.hasInfix "Mod+Space repeat=false" (keybinds cases.niri)
  );

  laptop-power-fixtures = pkgs.runCommand "laptop-power-fixtures" { nativeBuildInputs = [ pkgs.bash pkgs.jq ]; } ''
    bash ${../.}/scripts/test-laptop-power.sh
    touch "$out"
  '';

  niri-macbook-fn = validateNiri "macbook-fn" macWithFn;
  tg-ws-proxy = pkgs.callPackage ../pkgs/tg-ws-proxy.nix { };

  python-path = pkgs.runCommand "python-on-path" { nativeBuildInputs = [ pkgs.python3 ]; } ''
    python --version
    python3 --version
    printf '%s\n' 'assert 2 + 2 == 4' > example.py
    python example.py
    touch "$out"
  '';

  minegrub = pkgs.runCommand "minegrub-fixtures" {
    nativeBuildInputs = [ pkgs.patch pkgs.perl pkgs.python3 ];
  } ''
    cp ${pkgs.path}/nixos/modules/system/boot/loader/grub/install-grub.pl .
    chmod u+w install-grub.pl
    patch --batch --fuzz=0 install-grub.pl < ${../modules/boot/minegrub/generations.patch}
    grep -F 'nrFromGen($b) <=> nrFromGen($a)' install-grub.pl
    grep -F 'addGeneration($label, "", $link, $subEntryOptions, 0)' install-grub.pl
    perl ${./test-grub.pl} ${../modules/boot/minegrub/generation-labels.pl} "$PWD/install-grub.pl"
    python ${./test-minegrub.py} ${../modules/boot/minegrub/theme.txt}
    touch "$out"
  '';

  installer = pkgs.runCommand "installer-fixtures" { nativeBuildInputs = [ pkgs.bash pkgs.jq pkgs.shellcheck pkgs.python3 ]; } ''
    cd ${../.}
    shellcheck -x install.sh installer/tests/{run,efi}.sh scripts/{verify-linux-esp,macbook-backlight,dms-defaults,test-laptop-power}.sh
    bash installer/tests/run.sh
    bash installer/tests/efi.sh
    python installer/tests/test_progress.py
    touch "$out"
  '';

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
