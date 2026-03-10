#!/usr/bin/env python3
"""
PostToolUse hook (Write|Edit): 変更されたファイルのimport/依存関係を分析し、
影響を受ける可能性のあるファイルをコンテキストに注入する。
"""

import json
import os
import re
import subprocess
import sys
from pathlib import Path

MAX_IMPACT_FILES = 10
MAX_OUTPUT_LINES = 40


def sanitize_output(text: str) -> str:
    """出力をサニタイズする。"""
    text = re.sub(r"<[^>]+>", "", text)
    text = re.sub(r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]", "", text)
    return text


def validate_path(file_path: str, cwd: str) -> str | None:
    """ファイルパスを検証し、解決済みパスを返す。"""
    if not file_path or not cwd:
        return None
    try:
        resolved = Path(file_path).resolve()
        resolved_cwd = Path(cwd).resolve()
        if not resolved.is_relative_to(resolved_cwd):
            return None
        if not resolved.is_file():
            return None
        return str(resolved)
    except (OSError, ValueError):
        return None


def get_module_name(file_path: str, cwd: str) -> str:
    """ファイルパスからモジュール名/インポートパスを推測する。"""
    try:
        rel = Path(file_path).resolve().relative_to(Path(cwd).resolve())
    except ValueError:
        return ""

    stem = rel.stem
    # 拡張子を除去したパス
    no_ext = str(rel.with_suffix(""))

    return no_ext


def extract_exports(file_path: str) -> list[str]:
    """ファイルからエクスポートされた名前を抽出する。"""
    exports = []
    try:
        with open(file_path, "r", encoding="utf-8", errors="ignore") as f:
            content = f.read(100_000)  # 100KB制限
    except OSError:
        return exports

    suffix = Path(file_path).suffix

    if suffix in (".ts", ".tsx", ".js", ".jsx", ".mjs"):
        # export function/class/const/type/interface
        patterns = [
            r'export\s+(?:default\s+)?(?:function|class|const|let|var|type|interface|enum)\s+(\w+)',
            r'export\s*\{\s*([^}]+)\}',
        ]
        for pattern in patterns:
            for match in re.finditer(pattern, content):
                if "{" in match.group(0):
                    names = match.group(1).split(",")
                    for name in names:
                        name = name.strip().split(" as ")[0].strip()
                        if name:
                            exports.append(name)
                else:
                    exports.append(match.group(1))

    elif suffix == ".py":
        # クラス定義、関数定義（トップレベル）
        for match in re.finditer(r'^(?:class|def)\s+(\w+)', content, re.MULTILINE):
            exports.append(match.group(1))
        # __all__ 定義
        all_match = re.search(r'__all__\s*=\s*\[([^\]]+)\]', content)
        if all_match:
            for name in re.findall(r'["\'](\w+)["\']', all_match.group(1)):
                exports.append(name)

    elif suffix == ".go":
        # 大文字始まりの関数/型/変数（エクスポート）
        for match in re.finditer(r'^(?:func|type|var|const)\s+([A-Z]\w*)', content, re.MULTILINE):
            exports.append(match.group(1))

    elif suffix in (".java", ".kt"):
        # public class/interface/enum
        for match in re.finditer(r'public\s+(?:class|interface|enum)\s+(\w+)', content):
            exports.append(match.group(1))

    return list(dict.fromkeys(exports))[:20]


def find_importers(file_path: str, exports: list[str], cwd: str) -> list[str]:
    """変更されたファイルをimportしている他のファイルを検索する。"""
    importers = set()

    module_name = get_module_name(file_path, cwd)
    stem = Path(file_path).stem

    # 検索パターン: モジュール名、ファイル名（拡張子なし）、エクスポート名
    search_terms = [stem]
    if module_name:
        # パス区切りを各言語のimportスタイルに変換
        search_terms.append(module_name.replace("/", "."))
        search_terms.append(module_name.replace("/", "::"))
        search_terms.append(module_name)

    # エクスポート名で検索（頻出のもののみ）
    for export_name in exports[:5]:
        if len(export_name) > 3:  # 短すぎる名前は除外
            search_terms.append(export_name)

    search_terms = list(dict.fromkeys(search_terms))

    for term in search_terms:
        try:
            result = subprocess.run(
                ["grep", "-rl", "--include=*.py", "--include=*.ts",
                 "--include=*.tsx", "--include=*.js", "--include=*.jsx",
                 "--include=*.go", "--include=*.rs", "--include=*.java",
                 "--include=*.rb", "--include=*.kt",
                 term],
                cwd=cwd,
                capture_output=True,
                text=True,
                timeout=10,
            )
            if result.returncode == 0:
                for line in result.stdout.strip().split("\n"):
                    line = line.strip()
                    if not line:
                        continue
                    # 自分自身は除外
                    full = str((Path(cwd) / line).resolve())
                    resolved_target = str(Path(file_path).resolve())
                    if full != resolved_target and ".." not in line:
                        importers.add(line)
        except (subprocess.TimeoutExpired, OSError):
            continue

    return sorted(importers)[:MAX_IMPACT_FILES]


def find_test_file(file_path: str, cwd: str) -> str | None:
    """対応するテストファイルを検索する。"""
    stem = Path(file_path).stem
    suffix = Path(file_path).suffix

    test_candidates = [
        f"test_{stem}{suffix}",
        f"{stem}_test{suffix}",
        f"{stem}.test{suffix}",
        f"{stem}.spec{suffix}",
    ]

    test_dirs = ["test", "tests", "spec", "__tests__", "."]
    parent = str(Path(file_path).resolve().relative_to(Path(cwd).resolve()).parent)

    for td in test_dirs:
        for candidate in test_candidates:
            # テストディレクトリ直下
            path = Path(cwd) / td / candidate
            if path.is_file():
                return str(path.relative_to(Path(cwd)))
            # 同階層のテストディレクトリ
            path = Path(cwd) / parent / td / candidate
            if path.is_file():
                return str(path.relative_to(Path(cwd)))
            # 同階層
            path = Path(cwd) / parent / candidate
            if path.is_file():
                return str(path.relative_to(Path(cwd)))

    return None


def find_type_definitions(file_path: str, cwd: str) -> str | None:
    """対応する型定義ファイルを検索する（.d.ts等）。"""
    suffix = Path(file_path).suffix
    stem = Path(file_path).stem

    if suffix in (".ts", ".tsx", ".js", ".jsx"):
        dts = Path(file_path).with_suffix(".d.ts")
        if dts.is_file():
            try:
                return str(dts.relative_to(Path(cwd)))
            except ValueError:
                pass

    return None


def main():
    try:
        raw_input = sys.stdin.read()
        data = json.loads(raw_input)
    except (json.JSONDecodeError, ValueError):
        sys.exit(0)

    tool_name = data.get("tool_name", "")
    file_path = data.get("tool_input", {}).get("file_path", "")
    cwd = data.get("cwd", "")

    if tool_name not in ("Write", "Edit"):
        sys.exit(0)

    resolved = validate_path(file_path, cwd)
    if not resolved:
        sys.exit(0)

    # バイナリファイルはスキップ
    suffix = Path(resolved).suffix
    code_extensions = {
        ".py", ".ts", ".tsx", ".js", ".jsx", ".mjs",
        ".go", ".rs", ".java", ".kt", ".rb", ".php",
        ".c", ".cpp", ".h", ".hpp", ".cs", ".swift",
    }
    if suffix not in code_extensions:
        sys.exit(0)

    # 1. エクスポートされた名前を抽出
    exports = extract_exports(resolved)

    # 2. このファイルをimportしている他のファイルを検索
    importers = find_importers(resolved, exports, cwd)

    # 3. テストファイルを検索
    test_file = find_test_file(resolved, cwd)

    # 4. 型定義ファイルを検索
    type_def = find_type_definitions(resolved, cwd)

    if not importers and not test_file and not type_def:
        sys.exit(0)

    # 出力構築
    output_lines = []
    output_lines.append("=== change-impact-analyzer ===")

    rel_path = sanitize_output(str(Path(resolved).relative_to(Path(cwd).resolve())))
    output_lines.append(f"Changed: {rel_path}")

    if importers:
        output_lines.append(f"Affected files ({len(importers)}):")
        for imp in importers:
            output_lines.append(f"  - {sanitize_output(imp)}")
        output_lines.append("Consider reviewing these files for breaking changes.")

    if test_file:
        output_lines.append(f"Test file: {sanitize_output(test_file)}")
        output_lines.append("Consider running tests to verify changes.")

    if type_def:
        output_lines.append(f"Type definition: {sanitize_output(type_def)}")
        output_lines.append("Type definitions may need updating.")

    output_lines.append("=== End of change-impact-analyzer ===")

    # 行数制限
    if len(output_lines) > MAX_OUTPUT_LINES:
        output_lines = output_lines[:MAX_OUTPUT_LINES]

    # stdoutに出力（コンテキスト注入）
    print("\n".join(output_lines))

    # stderrにサマリー
    impact_count = len(importers) + (1 if test_file else 0) + (1 if type_def else 0)
    print(f"\n=== change-impact-analyzer: {impact_count} related file(s) ===",
          file=sys.stderr)


if __name__ == "__main__":
    main()
