# AGENTS.md — operit2-flake

[Operit2](https://github.com/AAswordman/Operit2) 的 Nix 打包仓库。纯 flake 构建，源码由
`fetchFromGitHub` 固定到具体提交。**本文件是维护入口**：结构、版本策略、补丁、升级流程、
已知边界都在这。用户向说明见 [README.md](./README.md)。

## 硬性规则

- 不要在本仓库手动运行 `nix build` / `nix flake check` / `nix eval` / `nix develop`
  做构建验证：改动后由用户在自己机器上构建，`nixos-rebuild` 也由用户执行。
- 访问 GitHub 用 `gh`/`git`，禁止裸 `curl` 请求 GitHub API/raw。
- 注释用中文；保持现有结构（`pkgs/` 打包 + `flake.nix` 模块 + `modules/` 模块文件）。
- 行为性改动（权限、Link 协议、UI）不要打进补丁，应提交上游；这里只做“让上游在 Nix
  沙箱里按同样语义构建”的替换。

## 仓库结构

```
flake.nix              # 输出：packages / overlays / nixosModules / homeModules / checks / formatter
pkgs/source.nix        # 唯一版本 pin：rev / hash / version
pkgs/plugin-assets.nix # 内置插件（buildin）资源 derivation，CLI 与 GUI 共用
pkgs/flutter-bridge.nix# Rust bridge + Dart 代理导出
pkgs/desktop.nix       # GUI
pkgs/cli.nix           # CLI
pkgs/patch-source.py   # Nix 专用源码适配
pkgs/pubspec.lock.json # 由上游 pubspec.lock 生成
pkgs/update.py         # 升级：更新 pin / 重生成 lock / 校验补丁锚点
modules/nixos-link.nix    # services.operit2-link
modules/nixos-desktop.nix # programs.operit2-desktop（系统级）
modules/home-desktop.nix  # programs.operit2-desktop（Home Manager）
```

`packages.${system}` 用 `nixpkgs.legacyPackages`；模块用 `pkgs.callPackage ../pkgs/*.nix`
取默认包，用户可用选项 `package` 覆盖。

## 版本策略

- CLI、GUI、bridge、插件资源都绑定 `pkgs/source.nix` 的同一个提交。
- 手机 APK（上游 release）与服务器 CLI、桌面端必须来自同一提交，否则 Link 协议可能不匹配。
- Flutter 用 nixpkgs 的 `flutter341`（3.41.9）。上游 FVM 固定 `3.41.10-ohos` 分支；
  差异是否影响 Linux 构建以实际构建为准，若出现 Dart SDK/引擎错误优先查这一项。
- nixpkgs 只 follow `nixos-unstable`，不锁旧版。

## 升级流程

```sh
python3 pkgs/update.py                  # 跟随 main 最新提交
python3 pkgs/update.py --rev <sha>      # 固定到指定提交
git diff
```

脚本会：下载源码归档 → `nix-hash` 计算 NAR 哈希 → 更新 `pkgs/source.nix` → 重新生成
`pkgs/pubspec.lock.json` → 在临时目录完整运行 `pkgs/patch-source.py` 校验锚点。
需要 `gh`（已认证）、`nix-hash`、带 PyYAML 的 Python：

```sh
nix shell nixpkgs#python3.withPackages\ \(p:\ \[\ p.pyyaml\ \]\) -c python3 pkgs/update.py
```

若 pubspec 里 git 依赖的 `ref` 变化，还要同步 `pkgs/desktop.nix` 的 `gitHashes`。
补丁锚点失效时脚本会失败并指出原因，需人工更新 `pkgs/patch-source.py`。

## Nix 专用源码适配（pkgs/patch-source.py）

| 替换 | 原因 |
| --- | --- |
| CMake 里的 `.venv/bin/python` 换成 `python3`，插件同步与 `cargo build` 改为空操作 | 沙箱无用户 venv；资源与 bridge 由独立 derivation 提供 |
| `hook/build.dart` 去掉插件同步调用 | Flutter native hook 不能在构建时访问 venv/网络 |
| bridge 安装路径改用 `OPERIT_FLUTTER_BRIDGE_LIB` | bridge 由 Nix 单独构建 |
| `sync_plugin_packages.py`：`OPERIT_NIX_BUILD=1` 时跳过 SDK types 生成、不走 pnpm | 沙箱无网络；script 式 ToolPkg 按普通目录打包 |
| ZIP 条目时间戳固定 1980 | Nix store 文件 mtime 为 1970，zipfile 不接受 |
| `xrandr` 直接调用，失败返回 `unknown` | 纯 Wayland 下查不到分辨率，不应阻止 Core 启动 |
| `my_application.cc` 读 `OPERIT_DESKTOP_LAUNCHER` 写 D-Bus 激活文件 | 原实现指向 `/proc/self/exe`（未包装二进制），D-Bus 激活会丢 PATH |

每个替换都要求旧文本恰好出现一次；上游改动导致锚点失效时补丁直接失败，不会静默跳过。

## 已知边界

- 桌面 GUI 单进程，关窗即退出；常驻在线能力由 `services.operit2-link` 提供。
- 节点之间的网络可达性（局域网/公网/overlay）不在本仓范围；`services.operit2-link`
  只负责监听与放行接口，怎么让设备互通由使用者决定。
- 没有验证过两个进程同时打开同一 Operit2 数据目录的行为，管理命令前先停服务。

## 验证（由用户执行）

```sh
nix build .#operit2-cli .#operit2-desktop
nix flake check
```

桌面启动后确认 `~/.local/share/dbus-1/services/org.operit.PluginSdk.service` 的 `Exec`
指向包装器；服务器上确认 `systemctl status operit2-link`、`journalctl -u operit2-link`。
