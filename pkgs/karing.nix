{
  lib,
  stdenv,
  fetchurl,
  dpkg,
  autoPatchelfHook,
  wrapGAppsHook3,
  curl,
  fontconfig,
  gtk3,
  jdk_headless,
  libayatana-appindicator,
  libsecret,
  libepoxy,
  libx11,
  libxi,
  keybinder3,
  libsoup_3,
  sqlite,
  webkitgtk_4_1,
  zlib,
}:

stdenv.mkDerivation (final: {
  pname = "karing";
  version = "1.2.26.2934";

  src = fetchurl {
    url = "https://github.com/KaringX/karing/releases/download/v${final.version}/karing_${final.version}_linux_amd64.deb";
    hash = "sha256-nMSEEhVKMLnWSwduDvd7t+0p6NGROlF5d+XHBuOgzfE=";
  };

  nativeBuildInputs = [ dpkg autoPatchelfHook wrapGAppsHook3 ];
  buildInputs = [
    stdenv.cc.cc.lib
    curl
    fontconfig
    gtk3
    libayatana-appindicator
    libsecret
    libepoxy
    libx11
    libxi
    keybinder3
    libsoup_3
    sqlite
    webkitgtk_4_1
    zlib
  ];

  unpackPhase = ''
    runHook preUnpack
    dpkg-deb -x "$src" .
    runHook postUnpack
  '';

  runtimeDependencies = [ libayatana-appindicator ];

  preFixup = ''
    addAutoPatchelfSearchPath "$out/lib/karing/lib" "${jdk_headless}/lib/openjdk/lib/server"
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/bin" "$out/lib" "$out/share"
    cp -r opt/karing "$out/lib/karing"
    cp -r usr/share/. "$out/share/"
    ln -s ../lib/karing/karing "$out/bin/karing"
    runHook postInstall
  '';

  meta = {
    description = "Karing network client";
    homepage = "https://github.com/KaringX/karing";
    license = lib.licenses.gpl3Plus;
    mainProgram = "karing";
    platforms = [ "x86_64-linux" ];
  };
})
