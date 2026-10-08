{
  stdenvNoCC,
  gitMinimal,
  nodejs,
  python3,
  typescript_5,
  callPackage,
}:
let
  source = callPackage ./source.nix { };
in
# 内置插件资源（buildin）由上游同步脚本生成，CLI 与 GUI 都要把它编译进二进制：
# core/crates/runtime/application/build.rs 会读取 assets/plugins/buildin。
stdenvNoCC.mkDerivation {
  pname = "operit2-builtin-plugin-assets";
  inherit (source) version src;

  nativeBuildInputs = [
    gitMinimal
    nodejs
    python3
    # 同步脚本通过 PATH 上的 tsc 编译插件；nixpkgs 默认 typescript 7 与上游不兼容。
    typescript_5
  ];

  postPatch = ''
    python3 ${./patch-source.py} "$PWD"
  '';

  buildPhase = ''
    runHook preBuild

    # 同步脚本的 ZIP 与 git ls-files 依赖一个 git 工作区。
    git init --quiet
    git add --force --all
    export OPERIT_NIX_BUILD=1
    python3 plugins/tools/sync_plugin_packages.py --source buildin --no-hot-reload

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/plugins"
    cp -a core/crates/runtime/application/assets/plugins/buildin "$out/plugins/buildin"

    runHook postInstall
  '';
}
