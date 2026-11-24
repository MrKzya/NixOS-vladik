{ pkgs, hosts }:

let
  inherit (pkgs) lib;
  home = cfg: cfg.home-manager.users.${cfg.mySystem.user};

  checkHost = name: host:
    let
      default = host.config;
      gaming = default.specialisation.Gaming.configuration;
      minimal = default.specialisation.Minimal.configuration;
      profiles = [ default gaming minimal ];
      packages = cfg: map lib.getName (cfg.environment.systemPackages ++ (home cfg).home.packages);
      has = cfg: wanted: lib.all (p: builtins.elem p (packages cfg)) wanted;
      lacks = cfg: wanted: lib.all (p: !(builtins.elem p (packages cfg))) wanted;
      noNiri = cfg:
        !cfg.programs.niri.enable
        && !cfg.programs.dux-shell.enable
        && !cfg.programs.dux-search.enable
        && !(cfg.systemd.user.services ? vicinae)
        && !((home cfg).xdg.configFile ? "niri/config.kdl");
    in
    assert lib.assertMsg (
      default.programs.niri.enable
      && default.programs.dux-shell.enable
      && default.services.displayManager.ly.enable
      && default.services.displayManager.defaultSession == "niri"
      && default.systemd.user.services.vicinae.wantedBy == [ "niri.service" ]
      && default.systemd.user.services.dms.wantedBy == [ "niri.service" ]
      && has default [ "kitty" "nautilus" "vicinae" "dux-shell" "dux-gop" "dux-search" "zen-beta" ]
      && !default.services.desktopManager.plasma6.enable
      && !default.programs.steam.enable
    ) "${name}: неверный состав Default";
    assert lib.assertMsg (
      noNiri gaming
      && gaming.services.desktopManager.plasma6.enable
      && gaming.services.displayManager.ly.enable
      && gaming.services.displayManager.defaultSession == "plasma"
      && gaming.programs.steam.enable
      && gaming.programs.gamemode.enable
      && has gaming [ "kitty" "mangohud" ]
      && lacks gaming [ "niri" "vicinae" "dux-shell" ]
    ) "${name}: неверный состав Gaming";
    assert lib.assertMsg (
      noNiri minimal
      && !minimal.services.desktopManager.plasma6.enable
      && !minimal.services.displayManager.enable
      && !minimal.programs.steam.enable
      && !minimal.services.pipewire.enable
      && minimal.systemd.defaultUnit == "multi-user.target"
      && has minimal [ "fish" "starship" "fastfetch" "git" "pwgen" ]
      && lacks minimal [ "niri" "vicinae" "dux-shell" "kitty" "firefox" "zen-beta" "ly" ]
    ) "${name}: неверный состав Minimal";
    assert lib.assertMsg (
      lib.all (cfg:
        cfg.mySystem.user == default.mySystem.user
        && (home cfg).home.homeDirectory == (home default).home.homeDirectory
        && cfg.networking.hostName == default.networking.hostName
        && cfg.fileSystems == default.fileSystems
      ) [ gaming minimal ]
      && lib.all (cfg: lacks cfg [ "noctalia" "noctalia-shell" ]) profiles
    ) "${name}: общие данные или зависимости профилей различаются";
    assert lib.assertMsg (
      lib.all (cfg: (cfg.users.users.${cfg.mySystem.user}.initialPassword == "vm-only") == (name == "vm")) profiles
    ) "${name}: тестовый пароль QEMU вышел за пределы тестового хоста";
    assert lib.assertMsg (
      name != "vmware" || lib.all (cfg:
        cfg.virtualisation.vmware.guest.enable
        && cfg.virtualisation.vmware.guest.headless
        && cfg.systemd.services.vmware.unitConfig.ConditionVirtualization == "vmware"
        && !(cfg.security.wrappers ? vmware-user-suid-wrapper)
        && !cfg.services.xserver.enable
        && !cfg.services.qemuGuest.enable
        && !(cfg.virtualisation ? fileSystems)
      ) profiles
    ) "VMware: проверьте изоляцию гостевой службы и отсутствие X11-компонентов и параметров QEMU";
    true;

  validateNiri = name: host:
    let
      files = lib.filterAttrs (path: _: lib.hasPrefix "niri/" path) (home host.config).xdg.configFile;
      stage = path: file: ''install -Dm644 ${file.source} ${lib.escapeShellArg path}'';
    in
    pkgs.runCommand "niri-${name}-validate" { nativeBuildInputs = [ pkgs.niri ]; } ''
      ${lib.concatStringsSep "\n" (lib.mapAttrsToList stage files)}
      niri validate --config "$PWD/niri/config.kdl"
      touch "$out"
    '';
in
{
  profiles =
    assert lib.all (name: checkHost name hosts.${name}) (builtins.attrNames hosts);
    pkgs.runCommand "profile-invariants" { } ''touch "$out"'';
  shell-config = pkgs.runCommand "shell-config" { nativeBuildInputs = [ pkgs.fish ]; } ''
    fish --no-config --no-execute ${../configs/fish/config.fish}
    bash -n ${./seed-config.sh}
    target="$PWD/config/settings.json"
    bash ${./seed-config.sh} ${../configs/dms/settings.json} "$target"
    cmp ${../configs/dms/settings.json} "$target"
    printf '%s\n' local-change > "$target"
    bash ${./seed-config.sh} ${../configs/dms/settings.json} "$target"
    grep -Fx local-change "$target"
    touch "$out"
  '';
}
// lib.mapAttrs' (name: host: lib.nameValuePair "niri-${name}" (validateNiri name host)) hosts
