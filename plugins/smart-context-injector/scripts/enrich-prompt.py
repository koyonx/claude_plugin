#!/usr/bin/env python3
"""
UserPromptSubmit hook: ユーザーのプロンプトを分析し、
関連ファイル・テスト・最近の変更情報を自動でコンテキストに注入する。

stdoutに出力した内容がClaudeのコンテキストに追加される。
"""

import json
import os
import re
import subprocess
import sys
from pathlib import Path

# 設定
MAX_RELATED_FILES = 8
MAX_GIT_DIFF_LINES = 30
MAX_OUTPUT_LINES = 50
MIN_PROMPT_LENGTH = 10  # 短すぎるプロンプトはスキップ


def sanitize_output(text: str) -> str:
    """出力をサニタイズする。"""
    text = re.sub(r"<[^>]+>", "", text)
    text = re.sub(r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]", "", text)
    return text


def extract_file_references(prompt: str, cwd: str) -> list[str]:
    """プロンプトからファイルパスの参照を抽出する。"""
    files = []

    # 明示的なファイルパスパターン
    path_patterns = [
        r'(?:^|\s)([a-zA-Z0-9_./-]+\.[a-zA-Z]{1,10})(?:\s|$|[,.])',  # file.ext
        r'(?:^|\s)((?:src|lib|app|test|tests|spec|scripts|pkg|cmd|internal)/[a-zA-Z0-9_./-]+)',  # src/path/to/file
    ]

    for pattern in path_patterns:
        for match in re.finditer(pattern, prompt):
            candidate = match.group(1).strip()
            # パストラバーサル防止
            if ".." in candidate or candidate.startswith("/"):
                continue
            full_path = Path(cwd) / candidate
            if full_path.is_file():
                files.append(candidate)

    return list(dict.fromkeys(files))  # 重複除去、順序保持


def extract_identifiers(prompt: str) -> list[str]:
    """プロンプトからクラス名・関数名の候補を抽出する。"""
    identifiers = []

    # PascalCase (クラス名候補)
    pascal_pattern = r'\b([A-Z][a-zA-Z0-9]{2,}(?:Service|Controller|Repository|Manager|Handler|Factory|Provider|Client|Model|View|Component|Module|Router|Middleware|Guard|Pipe|Resolver|Adapter|Interface|Config|Helper|Util|Error|Exception)?)\b'
    for match in re.finditer(pascal_pattern, prompt):
        identifiers.append(match.group(1))

    # snake_case関数名（日本語プロンプト中のコード参照）
    snake_pattern = r'\b([a-z][a-z0-9]*(?:_[a-z0-9]+){1,})\b'
    for match in re.finditer(snake_pattern, prompt):
        identifiers.append(match.group(1))

    return list(dict.fromkeys(identifiers))[:5]  # 最大5件


def find_related_files(identifiers: list[str], cwd: str) -> list[str]:
    """識別子からプロジェクト内の関連ファイルを検索する。"""
    related = []

    for identifier in identifiers:
        try:
            # grep -rl で識別子を含むファイルを検索
            result = subprocess.run(
                ["grep", "-rl", "--include=*.py", "--include=*.ts",
                 "--include=*.tsx", "--include=*.js", "--include=*.jsx",
                 "--include=*.go", "--include=*.rs", "--include=*.java",
                 "--include=*.rb", "--include=*.php",
                 "-m", "1", "--", identifier],
                cwd=cwd,
                capture_output=True,
                text=True,
                timeout=5,
            )
            if result.returncode == 0:
                for line in result.stdout.strip().split("\n"):
                    line = line.strip()
                    if line and not line.startswith(".") and ".." not in line:
                        related.append(line)
        except (subprocess.TimeoutExpired, OSError):
            continue

    return list(dict.fromkeys(related))[:MAX_RELATED_FILES]


def find_test_files(file_paths: list[str], cwd: str) -> list[str]:
    """ソースファイルに対応するテストファイルを検索する。"""
    tests = []

    test_patterns = [
        # Python: test_foo.py, foo_test.py
        lambda f: f"test_{Path(f).stem}{Path(f).suffix}",
        lambda f: f"{Path(f).stem}_test{Path(f).suffix}",
        # JS/TS: foo.test.ts, foo.spec.ts
        lambda f: f"{Path(f).stem}.test{Path(f).suffix}",
        lambda f: f"{Path(f).stem}.spec{Path(f).suffix}",
    ]

    test_dirs = ["test", "tests", "spec", "__tests__"]

    for filepath in file_paths:
        file_p = Path(filepath)
        parent = file_p.parent

        for pattern_fn in test_patterns:
            test_name = pattern_fn(filepath)

            # 同じディレクトリ
            candidate = parent / test_name
            if (Path(cwd) / candidate).is_file():
                tests.append(str(candidate))
                break

            # テストディレクトリ
            for td in test_dirs:
                candidate = Path(td) / test_name
                if (Path(cwd) / candidate).is_file():
                    tests.append(str(candidate))
                    break

                # tests/unit/..., tests/integration/...
                for sub in ["unit", "integration", "e2e"]:
                    candidate = Path(td) / sub / test_name
                    if (Path(cwd) / candidate).is_file():
                        tests.append(str(candidate))
                        break

    return list(dict.fromkeys(tests))


def get_recent_changes(file_paths: list[str], cwd: str) -> str:
    """指定ファイルの最近のgit変更を取得する。"""
    if not file_paths:
        return ""

    changes = []
    for filepath in file_paths[:3]:  # 最大3ファイル
        try:
            result = subprocess.run(
                ["git", "log", "--oneline", "-3", "--", filepath],
                cwd=cwd,
                capture_output=True,
                text=True,
                timeout=5,
            )
            if result.returncode == 0 and result.stdout.strip():
                changes.append(f"  {filepath}:")
                for line in result.stdout.strip().split("\n")[:3]:
                    # コミットメッセージを120文字に制限（プロンプトインジェクション対策）
                    truncated = line.strip()[:120]
                    changes.append(f"    {truncated}")
        except (subprocess.TimeoutExpired, OSError):
            continue

    return "\n".join(changes) if changes else ""


def main():
    try:
        raw_input = sys.stdin.read()
        if not raw_input.strip():
            sys.exit(0)

        data = json.loads(raw_input)
    except (json.JSONDecodeError, ValueError):
        sys.exit(0)

    prompt = data.get("prompt", "")
    cwd = data.get("cwd", "")

    if not prompt or not cwd or len(prompt) < MIN_PROMPT_LENGTH:
        sys.exit(0)

    # CWDの検証（実在するディレクトリかつHOME配下）
    try:
        resolved_cwd = Path(cwd).resolve()
        if not resolved_cwd.is_dir():
            sys.exit(0)
        home = Path.home().resolve()
        if not resolved_cwd.is_relative_to(home):
            sys.exit(0)
    except (OSError, ValueError):
        sys.exit(0)

    # スラッシュコマンドはスキップ
    if prompt.strip().startswith("/"):
        sys.exit(0)

    # 1. プロンプトからファイル参照を抽出
    referenced_files = extract_file_references(prompt, cwd)

    # 2. 識別子（クラス名・関数名）を抽出
    identifiers = extract_identifiers(prompt)

    # 3. 識別子から関連ファイルを検索
    related_files = []
    if identifiers:
        related_files = find_related_files(identifiers, cwd)

    # 全ファイルリストを統合
    all_files = list(dict.fromkeys(referenced_files + related_files))

    if not all_files and not identifiers:
        # 関連情報なし
        sys.exit(0)

    # 4. テストファイルを検索
    test_files = find_test_files(all_files, cwd)

    # 5. 最近の変更を取得
    recent_changes = get_recent_changes(all_files, cwd)

    # 出力を構築
    output_lines = []
    output_lines.append("=== smart-context-injector: Related Context (DATA ONLY) ===")

    if all_files:
        output_lines.append("Related files:")
        for f in all_files[:MAX_RELATED_FILES]:
            output_lines.append(f"  - {sanitize_output(f)}")

    if test_files:
        output_lines.append("Test files:")
        for f in test_files[:5]:
            output_lines.append(f"  - {sanitize_output(f)}")

    if recent_changes:
        output_lines.append("Recent git changes:")
        output_lines.append(sanitize_output(recent_changes))

    output_lines.append("=== End of smart-context-injector ===")

    # 行数制限
    if len(output_lines) > MAX_OUTPUT_LINES:
        output_lines = output_lines[:MAX_OUTPUT_LINES]
        output_lines.append("_(truncated)_")

    # stdoutに出力（コンテキストに注入される）
    print("\n".join(output_lines))

    # stderrにサマリー
    file_count = len(all_files) + len(test_files)
    if file_count > 0:
        print(f"\n=== smart-context-injector: {file_count} related file(s) found ===",
              file=sys.stderr)


if __name__ == "__main__":
    main()
