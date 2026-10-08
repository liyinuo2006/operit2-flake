{
  lib,
  flutter341,
  callPackage,
  gitMinimal,
  python3,
  clang,
  cmake,
  ninja,
  pkg-config,
  copyDesktopItems,
  makeDesktopItem,
  gtk3,
  webkitgtk_4_1,
  gst_all_1,
  glib-networking,
  glib,
  gsettings-desktop-schemas,
  libsecret,
  xz,
  # Linux Host 运行时会调用的外部程序（见 hosts/linux/src/tools）。
  xrandr,
  libnotify,
  xdg-utils,
  procps,
  coreutils,
  bash,
  iproute2,
  inetutils,
  alsa-utils,
  bluez,
  espeak-ng,
  tesseract,
  gnome-screenshot,
}:
let
  source = callPackage ./source.nix { };
  flutterBridge = callPackage ./flutter-bridge.nix { };

  gstPlugins = with gst_all_1; [
    gstreamer
    gst-plugins-base
    gst-plugins-good
    gst-plugins-bad
    gst-libav
  ];

  hostRuntimeTools = [
    xrandr
    libnotify
    xdg-utils
    glib
    procps
    coreutils
    bash
    iproute2
    inetutils
    alsa-utils
    bluez
    espeak-ng
    tesseract
    gnome-screenshot
  ];
in
flutter341.buildFlutterApplication {
  pname = "operit2-desktop";
  inherit (source) version src;

  sourceRoot = "${source.src.name}/apps/flutter/app";
  pubspecLock = lib.importJSON ./pubspec.lock.json;
  # 上游 pubspec 的三个 Gitee 依赖，固定在同一个 openharmony flutter_packages 提交上。
  gitHashes = {
    path_provider_ohos = "sha256-KQ1NB3eVVLRPZfl5eYMfMcg98su4kzYE8Iv4x6PkHu8=";
    url_launcher_ohos = "sha256-KQ1NB3eVVLRPZfl5eYMfMcg98su4kzYE8Iv4x6PkHu8=";
    video_player_ohos = "sha256-KQ1NB3eVVLRPZfl5eYMfMcg98su4kzYE8Iv4x6PkHu8=";
  };

  nativeBuildInputs = [
    clang
    cmake
    copyDesktopItems
    gitMinimal
    ninja
    pkg-config
    python3
  ];
  # Flutter 自己在 buildPhase 中调用 CMake，禁用 stdenv 的通用 CMake configure hook。
  dontUseCmakeConfigure = true;

  buildInputs = [
    flutterBridge
    glib-networking
    gsettings-desktop-schemas
    gst_all_1.gstreamer
    gst_all_1.gst-plugins-base
    gst_all_1.gst-plugins-good
    gst_all_1.gst-plugins-bad
    gst_all_1.gst-libav
    gtk3
    libsecret
    webkitgtk_4_1
    xz
  ];

  env = {
    OPERIT_FLUTTER_BRIDGE_LIB = "${flutterBridge}/lib/liboperit_flutter_bridge.so";
    OPERIT_NIX_BUILD = "1";
  };

  postPatch = ''
    python3 ${./patch-source.py} "$PWD/../../.." --cmake-only
    mkdir -p lib/core/proxy/generated
    install -m644 \
      ${flutterBridge}/share/operit2/dart-proxy/CoreProxyClients.g.dart \
      lib/core/proxy/generated/CoreProxyClients.g.dart
    install -m644 \
      ${flutterBridge}/share/operit2/dart-proxy/CoreProxyModels.g.dart \
      lib/core/proxy/generated/CoreProxyModels.g.dart
  '';

  postInstall = ''
    mv "$out/bin/operit2" "$out/bin/operit2-desktop"
    install -Dm644 \
      "${source.src}/apps/flutter/app/android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png" \
      "$out/share/icons/hicolor/192x192/apps/operit2.png"
  '';

  # OPERIT_DESKTOP_LAUNCHER 供 my_application.cc 写入 D-Bus 激活文件，见 patch-source.py。
  extraWrapProgramArgs = ''
    --prefix PATH : "${lib.makeBinPath hostRuntimeTools}" \
    --prefix GST_PLUGIN_SYSTEM_PATH_1_0 : "${lib.makeSearchPath "lib/gstreamer-1.0" gstPlugins}" \
    --set GST_PLUGIN_SCANNER "${gst_all_1.gstreamer}/libexec/gstreamer-1.0/gst-plugin-scanner" \
    --set OPERIT_DESKTOP_LAUNCHER "$out/bin/operit2-desktop"
  '';

  desktopItems = [
    (makeDesktopItem {
      name = "operit2-desktop";
      exec = "operit2-desktop";
      icon = "operit2";
      desktopName = "Operit2";
      genericName = "AI Agent Desktop Application";
      categories = [ "Utility" ];
      terminal = false;
    })
  ];

  passthru = {
    inherit flutterBridge;
  };

  meta = {
    description = "Operit2 AI Agent desktop application (Flutter GUI)";
    homepage = "https://github.com/AAswordman/Operit2";
    license = lib.licenses.agpl3Only;
    mainProgram = "operit2-desktop";
    platforms = [ "x86_64-linux" ];
  };
}
