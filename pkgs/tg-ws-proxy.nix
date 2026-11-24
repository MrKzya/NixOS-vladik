{
  lib,
  stdenv,
  fetchurl,
  dpkg,
  autoPatchelfHook,
  wrapGAppsHook3,
  gobject-introspection,
  gtk3,
  libayatana-appindicator,
  tcl,
  tk,
  zlib,
}:

stdenv.mkDerivation (final: {
  pname = "tg-ws-proxy";
  version = "1.12.0";

  src = fetchurl {
    url = "https://github.com/Flowseal/tg-ws-proxy/releases/download/v${final.version}/TgWsProxy_linux_amd64.deb";
    hash = "sha256-LTQKFVxxDzw533WD7YiSLgcLudTEs2LU4/2Jtfmy9t0=";
  };

  nativeBuildInputs = [ dpkg autoPatchelfHook wrapGAppsHook3 gobject-introspection ];
  buildInputs = [ stdenv.cc.cc.lib gtk3 libayatana-appindicator tcl tk zlib ];

  # The PyInstaller payload loads the tray libraries dynamically.
  runtimeDependencies = [ gtk3 libayatana-appindicator stdenv.cc.cc.lib zlib ];
  dontStrip = true;

  unpackPhase = ''
    runHook preUnpack
    dpkg-deb -x "$src" .
    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p "$out"
    cp -r usr/bin usr/share "$out/"
    runHook postInstall
  '';

  meta = {
    description = "Telegram Desktop WebSocket bridge proxy";
    homepage = "https://github.com/Flowseal/tg-ws-proxy";
    license = lib.licenses.mit;
    mainProgram = "tg-ws-proxy";
    platforms = [ "x86_64-linux" ];
  };
})
