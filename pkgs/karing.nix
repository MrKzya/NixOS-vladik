{
  lib,
  stdenv,
  fetchurl,
  dpkg,
  autoPatchelfHook,
  wrapGAppsHook3,
  curl,
  fontconfig,
  glib,
  gsettings-desktop-schemas,
  gtk3,
  jdk_headless,
  kdePackages,
  libayatana-appindicator,
  libsecret,
  libepoxy,
  libx11,
  libxi,
  keybinder3,
  libsoup_3,
  sqlite,
  webkitgtk_4_1,
  xdg-utils,
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
    glib
    gsettings-desktop-schemas
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
    # Flutter loads libcnativeapi.so via dlopen; it has no DT_NEEDED entry.
    gappsWrapperArgs+=(--prefix LD_LIBRARY_PATH : "$out/lib/karing/lib:$out/lib/karing"
      --prefix PATH : "$out/libexec/karing:${lib.makeBinPath [ glib xdg-utils ]}")
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/bin" "$out/lib" "$out/share"
    cp -r opt/karing "$out/lib/karing"
    cp -r usr/share/. "$out/share/"
    ln -s ../lib/karing/karing "$out/bin/karing"
    # The pinned app still invokes the KDE 5 tool name for the KIO proxy settings.
    mkdir -p "$out/libexec/karing"
    ln -s ${kdePackages.kconfig}/bin/kwriteconfig6 "$out/libexec/karing/kwriteconfig5"
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
