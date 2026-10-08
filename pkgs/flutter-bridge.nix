{
  lib,
  rustPlatform,
  python3,
  callPackage,
}:
let
  source = callPackage ./source.nix { };
  pluginAssets = callPackage ./plugin-assets.nix { };
in
rustPlatform.buildRustPackage {
  pname = "operit2-flutter-bridge";
  inherit (source) version src;

  cargoRoot = "apps/flutter/native/operit-flutter-bridge";
  buildAndTestSubdir = "apps/flutter/native/operit-flutter-bridge";
  cargoLock.lockFile = "${source.src}/apps/flutter/native/operit-flutter-bridge/Cargo.lock";
  cargoBuildFlags = [ "--lib" ];
  doCheck = false;

  nativeBuildInputs = [
    python3
    rustPlatform.bindgenHook
  ];

  postPatch = ''
    python3 ${./patch-source.py} "$PWD"
    mkdir -p core/crates/runtime/application/assets/plugins
    cp -a ${pluginAssets}/plugins/buildin core/crates/runtime/application/assets/plugins/buildin
  '';

  # core/crates/proxy/local 的 build.rs 会把 Dart 代理写进 apps/flutter/app/lib/core/proxy/generated，
  # Flutter 构建需要这两个文件，因此随 bridge 一起导出。
  postInstall = ''
    mkdir -p "$out/share/operit2/dart-proxy"
    install -m644 \
      apps/flutter/app/lib/core/proxy/generated/CoreProxyClients.g.dart \
      "$out/share/operit2/dart-proxy/CoreProxyClients.g.dart"
    install -m644 \
      apps/flutter/app/lib/core/proxy/generated/CoreProxyModels.g.dart \
      "$out/share/operit2/dart-proxy/CoreProxyModels.g.dart"
  '';

  meta = {
    description = "Operit2 Flutter native bridge (liboperit_flutter_bridge.so)";
    homepage = "https://github.com/AAswordman/Operit2";
    license = lib.licenses.agpl3Only;
    platforms = [ "x86_64-linux" "aarch64-linux" ];
  };
}
