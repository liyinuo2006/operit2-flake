{
  lib,
  rustPlatform,
  callPackage,
  python3,
  makeWrapper,
  coreutils,
  bash,
  iproute2,
  inetutils,
  procps,
  xdg-utils,
}:
let
  source = callPackage ./source.nix { };
  pluginAssets = callPackage ./plugin-assets.nix { };

  # Linux Host 运行时调用的外部程序（设备信息、打开链接、进程管理）。
  hostRuntimeTools = [
    coreutils
    bash
    iproute2
    inetutils
    procps
    xdg-utils
  ];
in
rustPlatform.buildRustPackage {
  pname = "operit2-cli";
  inherit (source) version src;

  cargoRoot = "apps/cli";
  buildAndTestSubdir = "apps/cli";
  cargoLock.lockFile = "${source.src}/apps/cli/Cargo.lock";
  cargoBuildFlags = [
    "--bin"
    "operit2"
  ];
  # 上游 Linux 发布流程构建 CLI，但不运行 cargo test。
  doCheck = false;

  nativeBuildInputs = [
    makeWrapper
    python3
    rustPlatform.bindgenHook
  ];

  # 内置插件在编译期嵌入二进制，缺少这一步 CLI 将没有任何 buildin 插件。
  postPatch = ''
    python3 ${./patch-source.py} "$PWD"
    mkdir -p core/crates/runtime/application/assets/plugins
    cp -a ${pluginAssets}/plugins/buildin core/crates/runtime/application/assets/plugins/buildin
  '';

  postInstall = ''
    wrapProgram "$out/bin/operit2" --prefix PATH : "${lib.makeBinPath hostRuntimeTools}"
    ln -s operit2 "$out/bin/operit"
  '';

  passthru = {
    inherit pluginAssets;
  };

  meta = {
    description = "Operit2 Agent CLI, TUI and headless Link node";
    homepage = "https://github.com/AAswordman/Operit2";
    license = lib.licenses.agpl3Only;
    mainProgram = "operit2";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
  };
}
