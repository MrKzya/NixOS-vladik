{ inputs, lib, nixosConfig, pkgs, ... }:

let
  cfg = nixosConfig.mySystem;
in
{
  home.packages = with pkgs; [
    # Браузеры, обмен сообщениями, заметки и файлы.
    firefox
    inputs.zen.packages.${stdenv.hostPlatform.system}.beta
    nautilus
    obsidian
    telegram-desktop

    # Сеанс Niri и функциональность DMS.
    kitty
    qt6.qtwayland
    nodejs # Runtime for Vicinae extensions.
    tmux
  ] ++ lib.optionals cfg.development.enable [
    vscode
    gcc
    gnumake
    binutils
    bison
    fakeroot
    file
    findutils
    flex
    gettext
    gawk
    diffutils
    m4
    patch
    pkg-config
    autoconf
    automake
    libtool
    which
  ] ++ lib.optionals cfg.networkApps.enable [
    (callPackage ../pkgs/karing.nix { })
    (callPackage ../pkgs/tg-ws-proxy.nix { })
  ];
}
