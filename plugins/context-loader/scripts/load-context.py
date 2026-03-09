#!/usr/bin/env python3
"""セッション開始時にプロジェクト固有の重要ファイルを自動読み込みする。"""

import glob
import json
import sys
from pathlib import Path

MAX_FILE_SIZE = 5 * 1024 * 1024  # 5MB per file
MAX_TOTAL_SIZE = 20 * 1024 * 1024  # 20MB total
CONFIG_FILENAME = ".context-loader.json"


def validate_path(file_path: Path, project_root: Path) -> bool:
    """ファイルパスがプロジェクトルート配下であることを検証する。"""
    try:
        resolved = file_path.resolve()
        return resolved.is_relative_to(project_root.resolve())
    except (OSError, ValueError):
        return False


def load_config(project_root: Path) -> dict | None:
    """プロジェクトルートから設定ファイルを読み込む。"""
    config_path = project_root / CONFIG_FILENAME
    if not config_path.is_file():
        return None

    try:
        with open(config_path, "r", encoding="utf-8") as f:
            config = json.load(f)
        if not isinstance(config, dict):
            return None
        return config
    except (json.JSONDecodeError, OSError):
        return None


def resolve_files(config: dict, project_root: Path) -> list[Path]:
    """設定からファイルリストを解決する。"""
    files = []
    seen = set()

    # 明示的なファイルパス
    for file_entry in config.get("files", []):
        if not isinstance(file_entry, str):
            continue
        file_path = project_root / file_entry
        if not validate_path(file_path, project_root):
            print(f"Skipping (outside project): {file_entry}", file=sys.stderr)
            continue
        resolved = file_path.resolve()
        if resolved.is_file() and str(resolved) not in seen:
            seen.add(str(resolved))
            files.append(resolved)

    # globパターン
    for pattern in config.get("globs", []):
        if not isinstance(pattern, str):
            continue
        # パターンの安全性チェック: 相対パスのみ許可、パストラバーサル禁止
        if ".." in pattern or pattern.startswith("/") or pattern.startswith("~"):
            print(f"Skipping glob (unsafe pattern): {pattern}", file=sys.stderr)
            continue
        # pathlibの結合で絶対パスが右辺にあると左辺が無視されるため、明示的に結合
        glob_target = str(project_root) + "/" + pattern
        matched = glob.glob(glob_target, recursive=True)
        for match in sorted(matched):
            match_path = Path(match)
            if not validate_path(match_path, project_root):
                continue
            resolved = match_path.resolve()
            if resolved.is_file() and str(resolved) not in seen:
                seen.add(str(resolved))
                files.append(resolved)

    return files


def load_files(files: list[Path], project_root: Path) -> None:
    """ファイルを読み込んで内容を表示する。"""
    total_size = 0
    loaded_count = 0

    for file_path in files:
        try:
            file_size = file_path.stat().st_size
        except OSError:
            continue

        if file_size > MAX_FILE_SIZE:
            print(f"Skipping (too large: {file_size}B): {file_path}", file=sys.stderr)
            continue

        if total_size + file_size > MAX_TOTAL_SIZE:
            print(f"Total size limit reached. Stopping.", file=sys.stderr)
            break

        try:
            rel_path = file_path.relative_to(project_root.resolve())
        except ValueError:
            rel_path = file_path

        print(f"Loaded: {rel_path}", file=sys.stderr)
        total_size += file_size
        loaded_count += 1

    if loaded_count > 0:
        print(f"", file=sys.stderr)
        print(f"=== context-loader ===", file=sys.stderr)
        print(f"Loaded {loaded_count} file(s), {total_size} bytes total", file=sys.stderr)
        print(f"======================", file=sys.stderr)
    else:
        print(f"No files loaded by context-loader.", file=sys.stderr)


def main():
    hook_input = json.loads(sys.stdin.read())
    cwd = hook_input.get("cwd", "")

    if not cwd:
        sys.exit(0)

    project_root = Path(cwd)
    if not project_root.is_dir():
        sys.exit(0)

    config = load_config(project_root)
    if config is None:
        sys.exit(0)

    files = resolve_files(config, project_root)
    if not files:
        print("context-loader: No matching files found.", file=sys.stderr)
        sys.exit(0)

    load_files(files, project_root)


if __name__ == "__main__":
    main()
