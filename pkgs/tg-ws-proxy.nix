{
  lib,
  fetchurl,
  python3Packages,
  wrapGAppsHook3,
  gobject-introspection,
  gtk3,
  libayatana-appindicator,
  xkeyboard_config,
  wl-clipboard,
  xclip,
  xdg-utils,
  xvfb-run,
  copyDesktopItems,
  makeDesktopItem,
}:

python3Packages.buildPythonApplication (final: {
  pname = "tg-ws-proxy";
  version = "1.12.0";
  pyproject = true;

  src = fetchurl {
    name = "tg-ws-proxy-${final.version}.tar.gz";
    url = "https://codeload.github.com/Flowseal/tg-ws-proxy/tar.gz/refs/tags/v${final.version}";
    hash = "sha256-lOyCTJrvgq1Qm4gT8CjlQQ8YHPN/NQTVdaRhfiE/ocY=";
  };
  patches = [ ./tg-ws-proxy-native-smoke.patch ];

  nativeBuildInputs = with python3Packages; [
    pythonRelaxDepsHook
    wrapGAppsHook3
    gobject-introspection
    copyDesktopItems
  ];
  build-system = [ python3Packages.hatchling ];

  # Use one Python/GLib stack from the project's locked Nixpkgs.
  pythonRelaxDeps = [ "cryptography" "pillow" "psutil" "pyperclip" ];
  dependencies = with python3Packages; [
    certifi
    cryptography
    customtkinter
    h2 # httpx[http2]
    httpx
    pillow
    psutil
    pygobject3
    pyperclip
    pystray
    tkinter
  ];
  buildInputs = [ gtk3 libayatana-appindicator ];

  postPatch = ''
    substituteInPlace pyproject.toml \
      --replace-fail '"linux.py" = "linux.py"' $'"linux.py" = "linux.py"\n"icon.ico" = "icon.ico"'
  '';

  postInstall = ''
    # Keep the former package entry point for desktop and command-line launches.
    mv "$out/bin/tg-ws-proxy" "$out/bin/tg-ws-proxy-cli"
    ln -s tg-ws-proxy-tray-linux "$out/bin/tg-ws-proxy"
    mkdir -p "$out/share/pixmaps"
    ${python3Packages.python.interpreter} -c 'from PIL import Image; import sys; Image.open("icon.ico").save(sys.argv[1])' \
      "$out/share/pixmaps/tg-ws-proxy.png"
  '';

  dontWrapGApps = true;
  preFixup = ''
    makeWrapperArgs+=("''${gappsWrapperArgs[@]}"
      --set-default PYSTRAY_BACKEND appindicator
      --set-default XKB_CONFIG_ROOT "${xkeyboard_config}/share/X11/xkb"
      --prefix PATH : "${lib.makeBinPath [ wl-clipboard xclip xdg-utils ]}")
  '';

  desktopItems = [
    (makeDesktopItem {
      name = "tg-ws-proxy";
      desktopName = "TG WS Proxy";
      exec = "tg-ws-proxy";
      icon = "tg-ws-proxy";
      categories = [ "Network" ];
    })
  ];

  nativeInstallCheckInputs = [ xvfb-run ];
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    export HOME="$(mktemp -d)"
    "$out/bin/tg-ws-proxy-cli" --help
    xvfb-run -a "$out/bin/tg-ws-proxy" --smoke-test
    runHook postInstallCheck
  '';

  meta = {
    description = "Telegram Desktop WebSocket bridge proxy";
    homepage = "https://github.com/Flowseal/tg-ws-proxy";
    license = lib.licenses.mit;
    mainProgram = "tg-ws-proxy";
    platforms = lib.platforms.linux;
  };
})
