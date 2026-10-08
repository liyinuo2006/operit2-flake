#!/usr/bin/env python3
"""升级 Operit2 上游版本，并验证 Nix 源码补丁仍然适用。

用法（在仓库根目录执行）：
  python3 update.py                 跟随 main 最新提交
  python3 update.py --rev <sha>     固定到指定提交

会做的事：
  1. 下载该提交的源码归档，用 nix-hash 计算 fetchFromGitHub 使用的 NAR 哈希；
  2. 更新 source.nix 中的 rev / hash / version；
  3. 从 apps/flutter/app/pubspec.lock 重新生成 pubspec.lock.json；
  4. 在临时目录里完整运行 patch-source.py，确认所有替换锚点仍然存在。

依赖：gh（已认证）、nix-hash、以及带 PyYAML 的 Python，例如：
  nix shell nixpkgs#python3.withPackages (p: [ p.pyyaml ]) -c python3 update.py

脚本不运行 nix build / nix eval。构建验证由你执行：
  nix build --no-link .#nixosConfigurations.aliyun.config.system.build.toplevel
  sudo nixos-rebuild switch --flake .#<host>
"""

import argparse
import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path

OWNER_REPO = "AAswordman/Operit2"
REPO_ROOT = Path(__file__).resolve().parent
PKG_DIR = REPO_ROOT / "pkgs"


def run(command: list[str], **kwargs) -> str:
    completed = subprocess.run(command, check=True, text=True, capture_output=True, **kwargs)
    return completed.stdout.strip()


def resolve_rev(rev: str | None) -> str:
    if rev:
        return rev
    return run(["gh", "api", f"repos/{OWNER_REPO}/commits/main", "--jq", ".sha"])


def fetch_source(rev: str, workdir: Path) -> Path:
    archive = workdir / "source.tar.gz"
    with archive.open("wb") as output:
        subprocess.run(
            ["gh", "api", f"repos/{OWNER_REPO}/tarball/{rev}"],
            check=True,
            stdout=output,
        )
    tree = workdir / "tree"
    tree.mkdir()
    subprocess.run(
        ["tar", "-xzf", str(archive), "--strip-components=1", "-C", str(tree)],
        check=True,
    )
    return tree


def replace_single(text: str, pattern: str, replacement: str, label: str) -> str:
    updated, count = re.subn(pattern, replacement, text, count=1, flags=re.MULTILINE)
    if count != 1:
        raise SystemExit(f"source.nix 中找不到 {label}，请手动检查")
    return updated


def update_source_nix(rev: str, version: str, sri_hash: str) -> None:
    path = PKG_DIR / "source.nix"
    text = path.read_text(encoding="utf-8")
    text = replace_single(text, r'rev = "[0-9a-f]{40}";', f'rev = "{rev}";', "rev")
    text = replace_single(text, r'version = "[^"]+";', f'version = "{version}";', "version")
    text = replace_single(text, r'hash = "sha256-[^"]+";', f'hash = "{sri_hash}";', "hash")
    path.write_text(text, encoding="utf-8")


def write_pubspec_lock(tree: Path) -> list[tuple[str, str, str]]:
    try:
        import yaml
    except ImportError as error:
        raise SystemExit("缺少 PyYAML，请参考脚本头部的 nix shell 命令") from error

    lock = yaml.safe_load((tree / "apps/flutter/app/pubspec.lock").read_text(encoding="utf-8"))
    output = {"packages": lock["packages"], "sdks": lock["sdks"]}
    (PKG_DIR / "pubspec.lock.json").write_text(
        json.dumps(output, indent=2, ensure_ascii=False, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    git_deps = []
    for name, package in sorted(lock["packages"].items()):
        if package.get("source") == "git":
            description = package["description"]
            git_deps.append((name, description["url"], description["resolved-ref"]))
    return git_deps


def read_version(tree: Path) -> str:
    cargo = (tree / "apps/cli/Cargo.toml").read_text(encoding="utf-8")
    match = re.search(r'^version = "([^"]+)"', cargo, flags=re.MULTILINE)
    if match is None:
        raise SystemExit("apps/cli/Cargo.toml 中找不到 version")
    return match.group(1)


def verify_patches(tree: Path) -> None:
    completed = subprocess.run(
        [sys.executable, str(PKG_DIR / "patch-source.py"), str(tree)],
        text=True,
        capture_output=True,
    )
    if completed.returncode != 0:
        sys.stderr.write(completed.stdout + completed.stderr)
        raise SystemExit("patch-source.py 无法适用于新版本，需要更新锚点")


def main() -> int:
    parser = argparse.ArgumentParser(description="Update the pinned Operit2 upstream revision.")
    parser.add_argument("--rev", help="upstream commit SHA; defaults to the current main HEAD")
    args = parser.parse_args()

    rev = resolve_rev(args.rev)
    print(f"upstream rev: {rev}")

    with tempfile.TemporaryDirectory(prefix="operit2-update-") as tmp:
        tree = fetch_source(rev, Path(tmp))
        sri_hash = run(["nix-hash", "--type", "sha256", "--sri", str(tree)])
        version = read_version(tree)
        print(f"version: {version}")
        print(f"hash: {sri_hash}")

        update_source_nix(rev, version, sri_hash)
        git_deps = write_pubspec_lock(tree)
        verify_patches(tree)

    print("\n已更新 source.nix 与 pubspec.lock.json；补丁锚点校验通过。")
    if git_deps:
        print("pubspec 中的 git 依赖（若 ref 变化，需要同步更新 desktop.nix 的 gitHashes）：")
        for name, url, ref in git_deps:
            print(f"  {name}: {url} @ {ref}")
    print("\n下一步：git diff pkgs，然后由你执行构建验证。")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except subprocess.CalledProcessError as error:
        sys.stderr.write(error.stderr or str(error))
        raise SystemExit(1)
