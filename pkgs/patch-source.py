#!/usr/bin/env python3
"""Nix 构建专用的源码适配。

这里只放“让上游源码在 Nix 沙箱里按同样语义构建”所必需的替换：
用户 venv 换成 Nix 提供的工具、插件同步改由独立 derivation 完成、
bridge 动态库改由 Nix 注入路径、ZIP 时间戳满足 Nix store 的 1970 时间。
行为性修改（权限、Link 协议、UI）一律不在这里做，应当提交给上游。

用法：
  patch-source.py <仓库根目录>                 完整适配（bridge / CLI / 插件资源）
  patch-source.py <仓库根目录> --cmake-only    只适配 Flutter 应用侧（GUI derivation）

每个替换都要求旧文本恰好出现一次；上游改动导致锚点失效时直接失败，
不会静默跳过。
"""

from pathlib import Path
import sys


def replace_once(path: Path, old: str, new: str) -> None:
    content = path.read_text(encoding="utf-8")
    if old not in content and new in content:
        return
    if content.count(old) != 1:
        raise SystemExit(f"预期只找到一次待替换文本：{path}")
    path.write_text(content.replace(old, new), encoding="utf-8")


root = Path(sys.argv[1]).resolve()
cmake_only = "--cmake-only" in sys.argv[2:]

runner = root / "apps/flutter/app/linux/runner/CMakeLists.txt"
replace_once(
    runner,
    'set(OPERIT_PLUGIN_SYNC_PYTHON "${OPERIT_REPO_ROOT}/.venv/bin/python")',
    'set(OPERIT_PLUGIN_SYNC_PYTHON "python3")',
)
replace_once(
    runner,
    'COMMAND "${OPERIT_PLUGIN_SYNC_PYTHON}" "${OPERIT_PLUGIN_SYNC_SCRIPT}" --source buildin --no-hot-reload',
    'COMMAND "${CMAKE_COMMAND}" -E true',
)
replace_once(
    runner,
    'COMMAND cargo build --manifest-path "${OPERIT_FLUTTER_BRIDGE_CRATE}/Cargo.toml" $<$<NOT:$<CONFIG:Debug>>:--release>',
    'COMMAND "${CMAKE_COMMAND}" -E true',
)

install_cmake = root / "apps/flutter/app/linux/CMakeLists.txt"
replace_once(
    install_cmake,
    '"${OPERIT_FLUTTER_BRIDGE_CRATE}/target/$<IF:$<CONFIG:Debug>,debug,release>/liboperit_flutter_bridge.so"',
    '"$ENV{OPERIT_FLUTTER_BRIDGE_LIB}"',
)

# 上游在 GUI 启动时把 D-Bus 激活文件指向 /proc/self/exe。Nix 的 wrapper 会把真实二进制
# 放到 .operit2-desktop-wrapped，直接用它激活会丢掉 PATH 与 GStreamer 等包装环境。
# 包装器通过 OPERIT_DESKTOP_LAUNCHER 指向自己；未设置时保持上游行为。
runner_application = root / "apps/flutter/app/linux/runner/my_application.cc"
replace_once(
    runner_application,
    '  g_autofree gchar* executable = g_file_read_link("/proc/self/exe", &error);\n'
    '  if (executable == nullptr) {\n'
    '    g_error("Cannot resolve Operit activation executable: %s", error->message);\n'
    '  }\n',
    '  const gchar* launcher = g_getenv("OPERIT_DESKTOP_LAUNCHER");\n'
    '  g_autofree gchar* executable = nullptr;\n'
    '  if (launcher != nullptr && launcher[0] != \'\\0\') {\n'
    '    executable = g_strdup(launcher);\n'
    '  } else {\n'
    '    executable = g_file_read_link("/proc/self/exe", &error);\n'
    '  }\n'
    '  if (executable == nullptr) {\n'
    '    g_error("Cannot resolve Operit activation executable: %s",\n'
    '            error != nullptr ? error->message : "unknown error");\n'
    '  }\n',
)

flutter_hook = root / "apps/flutter/app/hook/build.dart"
replace_once(
    flutter_hook,
    "    final syncScript = File.fromUri(\n"
    "      input.packageRoot.resolve(\n"
    "        '../../../plugins/tools/sync_plugin_packages.py',\n"
    "      ),\n"
    "    );",
    "    // 内置插件资源已由 Nix 的独立 derivation 同步。",
)
replace_once(
    flutter_hook,
    "    await _run(_pythonExecutable(repoRoot), [\n"
    "      syncScript.path,\n"
    "      '--source',\n"
    "      'buildin',\n"
    "      '--no-hot-reload',\n"
    "    ], workingDirectory: repoRoot.path);",
    "    // 内置插件资源已由 Nix 的独立 derivation 同步。",
)
replace_once(
    flutter_hook,
    "String _pythonExecutable(Directory repoRoot) {\n"
    "  if (Platform.isWindows) {\n"
    "    return File.fromUri(repoRoot.uri.resolve('.venv/Scripts/python.exe')).path;\n"
    "  }\n"
    "  return File.fromUri(repoRoot.uri.resolve('.venv/bin/python')).path;\n"
    "}",
    "// Nix 构建的插件同步由独立 derivation 完成，不走用户 venv。",
)

if cmake_only:
    raise SystemExit(0)

linux_system = root / "hosts/linux/src/tools/system/mod.rs"
replace_once(
    linux_system,
    r'''fn linux_screen_resolution() -> HostResult<String> {
    let output = command_stdout("sh", &["-lc", "xrandr --current | sed -n 's/.* current \\([0-9][0-9]*\\) x \\([0-9][0-9]*\\).*/\\1x\\2/p' | head -n 1"], "read Linux screen resolution")?;
    if output.trim().is_empty() {
        return Err(HostError::new(
            "xrandr did not return a current screen resolution",
        ));
    }
    Ok(output)
}''',
    r'''fn linux_screen_resolution() -> HostResult<String> {
    let output = match Command::new("xrandr").arg("--current").output() {
        Ok(output) if output.status.success() => {
            String::from_utf8_lossy(&output.stdout).into_owned()
        }
        Ok(output) => {
            eprintln!(
                "xrandr could not query a display: {}",
                String::from_utf8_lossy(&output.stderr).trim()
            );
            return Ok("unknown".to_string());
        }
        Err(error) => {
            eprintln!("xrandr is unavailable: {error}");
            return Ok("unknown".to_string());
        }
    };
    let resolution = Regex::new(r"current\s+([0-9]+)\s+x\s+([0-9]+)")
        .expect("static screen resolution regex");
    if let Some(captures) = resolution.captures(&output) {
        let width = captures.get(1).and_then(|value| value.as_str().parse::<u32>().ok());
        let height = captures.get(2).and_then(|value| value.as_str().parse::<u32>().ok());
        if let (Some(width), Some(height)) = (width, height) {
            if width > 0 && height > 0 {
                return Ok(format!("{width}x{height}"));
            }
        }
    }
    eprintln!("xrandr did not report a current resolution; using unknown");
    Ok("unknown".to_string())
}''',
)

sync_script = root / "plugins/tools/sync_plugin_packages.py"
replace_once(
    sync_script,
    'def _is_script_packed_toolpkg(folder: Path) -> bool:\n',
    'def _is_script_packed_toolpkg(folder: Path) -> bool:\n'
    '    if os.environ.get("OPERIT_NIX_BUILD") == "1":\n'
    '        return False\n',
)
replace_once(
    sync_script,
    '    _generate_plugin_sdk_types(repo_root, dry_run=bool(args.dry_run))',
    '    if os.environ.get("OPERIT_NIX_BUILD") != "1":\n'
    '        _generate_plugin_sdk_types(repo_root, dry_run=bool(args.dry_run))',
)
replace_once(
    sync_script,
    '            archive.write(file_path, file_path.relative_to(source_folder).as_posix())',
    '            zip_info = zipfile.ZipInfo(\n'
    '                file_path.relative_to(source_folder).as_posix(),\n'
    '                date_time=(1980, 1, 1, 0, 0, 0),\n'
    '            )\n'
    '            zip_info.compress_type = zipfile.ZIP_DEFLATED\n'
    '            zip_info.external_attr = (file_path.stat().st_mode & 0xFFFF) << 16\n'
    '            with file_path.open("rb") as source_file:\n'
    '                archive.writestr(zip_info, source_file.read())',
)
