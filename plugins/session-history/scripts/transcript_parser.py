#!/usr/bin/env python3
"""
トランスクリプトJSONLファイルをセッションごとの読みやすいMarkdownに変換する。
"""

import argparse
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path


def sanitize_filename(name: str) -> str:
    """ファイル名に安全な文字のみを残す。"""
    return re.sub(r"[^a-zA-Z0-9_.\-]", "", name)


def escape_markdown(text: str) -> str:
    """Markdownの特殊文字をエスケープする。"""
    return text.replace("`", "\\`").replace("<", "&lt;").replace(">", "&gt;")


def validate_transcript_path(path: str) -> bool:
    """トランスクリプトパスが~/.claude配下であることを検証する。"""
    claude_dir = Path.home() / ".claude"
    try:
        resolved = Path(path).resolve()
        return resolved.is_relative_to(claude_dir)
    except (OSError, ValueError):
        return False


MAX_TRANSCRIPT_SIZE = 100 * 1024 * 1024  # 100MB


def parse_transcript(transcript_path: str) -> list[dict]:
    """JSONLトランスクリプトファイルを読み込んでイベントリストを返す。"""
    file_size = Path(transcript_path).stat().st_size
    if file_size > MAX_TRANSCRIPT_SIZE:
        print(
            f"Transcript too large ({file_size} bytes, max {MAX_TRANSCRIPT_SIZE}). Skipping.",
            file=sys.stderr,
        )
        return []

    events = []
    with open(transcript_path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                event = json.loads(line)
                events.append(event)
            except json.JSONDecodeError:
                continue
    return events


def extract_text_content(content) -> str:
    """contentフィールドからテキストを抽出する。"""
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        texts = []
        for block in content:
            if isinstance(block, dict):
                if block.get("type") == "text":
                    texts.append(block.get("text", ""))
                elif block.get("type") == "tool_use":
                    tool_name = block.get("name", "unknown")
                    tool_input = block.get("input", {})
                    if tool_name == "Bash":
                        cmd = tool_input.get("command", "")
                        texts.append(f"[Tool: {tool_name}] `{cmd}`")
                    elif tool_name in ("Read", "Write", "Edit"):
                        path = tool_input.get("file_path", "")
                        texts.append(f"[Tool: {tool_name}] `{path}`")
                    elif tool_name in ("Grep", "Glob"):
                        pattern = tool_input.get("pattern", "")
                        texts.append(f"[Tool: {tool_name}] `{pattern}`")
                    else:
                        texts.append(f"[Tool: {tool_name}]")
                elif block.get("type") == "tool_result":
                    pass
            elif isinstance(block, str):
                texts.append(block)
        return "\n".join(texts)
    return str(content) if content else ""


def strip_system_tags(text: str) -> str:
    """system-reminderやその他のシステムタグを除去する。"""
    tag_patterns = [
        r"<system-reminder>.*?</system-reminder>",
        r"<available-deferred-tools>.*?</available-deferred-tools>",
        r"<env>.*?</env>",
    ]
    for pattern in tag_patterns:
        text = re.sub(pattern, "", text, flags=re.DOTALL)
    return text.strip()


def format_timestamp(ts) -> str:
    """タイムスタンプを読みやすい形式に変換する。"""
    if not ts:
        return ""
    try:
        if isinstance(ts, (int, float)):
            if ts > 1e12:
                ts = ts / 1000
            dt = datetime.fromtimestamp(ts, tz=timezone.utc).astimezone()
        elif isinstance(ts, str):
            dt = datetime.fromisoformat(ts.replace("Z", "+00:00")).astimezone()
        else:
            return ""
        return dt.strftime("%Y-%m-%d %H:%M:%S")
    except (ValueError, OSError):
        return ""


def events_to_markdown(events: list[dict], session_id: str, cwd: str) -> str:
    """イベントリストからMarkdown形式の会話ログを生成する。"""
    lines = []
    now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    safe_id = sanitize_filename(session_id)[:8] or "unknown"
    lines.append(f"# Session Log: {safe_id}")
    lines.append("")
    lines.append(f"- **Session ID**: `{safe_id}`")
    lines.append(f"- **Project**: `{escape_markdown(cwd)}`")
    lines.append(f"- **Saved at**: {now}")
    lines.append("")
    lines.append("---")
    lines.append("")

    msg_count = 0
    for event in events:
        role = event.get("role", "")
        event_type = event.get("type", "")
        content = event.get("content", "")
        timestamp = event.get("timestamp", "")

        if role == "user" or event_type == "user_message":
            text = extract_text_content(content)
            if not text or text.strip() == "":
                continue
            text = strip_system_tags(text)
            if not text:
                continue
            msg_count += 1
            ts = format_timestamp(timestamp)
            ts_str = f" ({ts})" if ts else ""
            lines.append(f"## User{ts_str}")
            lines.append("")
            lines.append(text)
            lines.append("")

        elif role == "assistant" or event_type == "assistant_message":
            text = extract_text_content(content)
            if not text or text.strip() == "":
                continue
            msg_count += 1
            ts = format_timestamp(timestamp)
            ts_str = f" ({ts})" if ts else ""
            lines.append(f"## Assistant{ts_str}")
            lines.append("")
            lines.append(text)
            lines.append("")

    if msg_count == 0:
        return ""

    lines.append("---")
    lines.append(f"*Total messages: {msg_count}*")
    return "\n".join(lines)


def save_session_log(
    transcript_path: str, session_id: str, cwd: str
) -> str | None:
    """トランスクリプトをパースしてセッションログとして保存する。"""
    if not validate_transcript_path(transcript_path):
        print(f"Invalid transcript path: {transcript_path}", file=sys.stderr)
        return None

    events = parse_transcript(transcript_path)
    if not events:
        return None

    markdown = events_to_markdown(events, session_id, cwd)
    if not markdown:
        return None

    # プロジェクトパスからディレクトリ名を生成（安全な文字のみ）
    project_name = sanitize_filename(cwd.replace("/", "_").lstrip("_"))
    if not project_name:
        project_name = "unknown_project"
    session_dir = Path.home() / ".claude" / "session-history" / "sessions" / project_name
    session_dir.mkdir(parents=True, exist_ok=True)

    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    safe_session_id = sanitize_filename(session_id)[:8] or "unknown"
    filename = f"{timestamp}_{safe_session_id}.md"
    output_path = session_dir / filename

    with open(output_path, "w", encoding="utf-8") as f:
        f.write(markdown)

    return str(output_path)


def generate_summary(events: list[dict], max_lines: int = 50) -> str:
    """会話イベントからコンパクトなサマリーを生成する。"""
    summary_parts = []
    user_topics = []
    assistant_actions = []

    for event in events:
        role = event.get("role", "")
        event_type = event.get("type", "")
        content = event.get("content", "")

        if role == "user" or event_type == "user_message":
            text = extract_text_content(content)
            if not text:
                continue
            text = strip_system_tags(text)
            if not text:
                continue
            # ユーザーのプロンプトを要約（先頭100文字）
            short = text[:100].replace("\n", " ").strip()
            if len(text) > 100:
                short += "..."
            user_topics.append(short)

        elif role == "assistant" or event_type == "assistant_message":
            text = extract_text_content(content)
            if not text:
                continue
            # ツール使用を抽出
            tools_used = []
            if isinstance(content, list):
                for block in content:
                    if isinstance(block, dict) and block.get("type") == "tool_use":
                        tool_name = block.get("name", "")
                        tool_input = block.get("input", {})
                        if tool_name == "Write":
                            tools_used.append(f"Write: {tool_input.get('file_path', '')}")
                        elif tool_name == "Edit":
                            tools_used.append(f"Edit: {tool_input.get('file_path', '')}")
                        elif tool_name == "Bash":
                            cmd = tool_input.get("command", "")[:60]
                            tools_used.append(f"Bash: {cmd}")
            if tools_used:
                assistant_actions.extend(tools_used)

    if not user_topics and not assistant_actions:
        return ""

    summary_parts.append("## Session History Summary")
    summary_parts.append("")

    if user_topics:
        summary_parts.append("### User Requests")
        for i, topic in enumerate(user_topics[-10:], 1):  # 直近10件
            summary_parts.append(f"{i}. {topic}")
        summary_parts.append("")

    if assistant_actions:
        summary_parts.append("### Key Actions")
        # ファイル操作を集約
        files_modified = set()
        commands_run = []
        for action in assistant_actions:
            if action.startswith("Write:") or action.startswith("Edit:"):
                files_modified.add(action.split(": ", 1)[1])
            elif action.startswith("Bash:"):
                commands_run.append(action.split(": ", 1)[1])

        if files_modified:
            summary_parts.append("**Files modified:**")
            for f in sorted(files_modified)[-15:]:  # 最大15件
                summary_parts.append(f"- `{f}`")
            summary_parts.append("")

        if commands_run:
            summary_parts.append("**Commands run (recent):**")
            for cmd in commands_run[-5:]:  # 直近5件
                summary_parts.append(f"- `{cmd}`")
            summary_parts.append("")

    # 行数制限
    lines = "\n".join(summary_parts).split("\n")
    if len(lines) > max_lines:
        lines = lines[:max_lines]
        lines.append("_(truncated)_")

    return "\n".join(lines)


def write_summary_to_memory(
    transcript_path: str, session_id: str, cwd: str
) -> str | None:
    """トランスクリプトからサマリーを生成してMEMORY.mdに書き込む。"""
    if not validate_transcript_path(transcript_path):
        print(f"Invalid transcript path: {transcript_path}", file=sys.stderr)
        return None

    events = parse_transcript(transcript_path)
    if not events:
        return None

    summary = generate_summary(events)
    if not summary:
        return None

    # プロジェクトのmemoryディレクトリを特定
    # transcript_pathから推測: ~/.claude/projects/<project-id>/...
    transcript_p = Path(transcript_path).resolve()
    claude_dir = Path.home() / ".claude"

    # プロジェクトのmemoryディレクトリを検索
    # cwdからプロジェクトIDを生成（Claude Codeと同じ方式）
    project_id = cwd.replace("/", "-").lstrip("-")
    memory_dir = claude_dir / "projects" / project_id / "memory"

    if not memory_dir.exists():
        # 別のパス形式を試行
        project_id = "-" + cwd.replace("/", "-")
        memory_dir = claude_dir / "projects" / project_id / "memory"

    memory_dir.mkdir(parents=True, exist_ok=True)
    memory_file = memory_dir / "MEMORY.md"

    now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    header = f"\n\n---\n_Pre-compact summary ({now})_\n\n"

    # 既存のMEMORY.mdの内容を読み込み
    existing_content = ""
    if memory_file.exists():
        existing_content = memory_file.read_text(encoding="utf-8")

    # 古いサマリーを削除（最新のみ保持）
    marker = "## Session History Summary"
    if marker in existing_content:
        # マーカー以前の内容を保持
        idx = existing_content.index(marker)
        # マーカーの前の区切り線も削除
        pre_summary = existing_content[:idx].rstrip()
        if pre_summary.endswith("---"):
            pre_summary = pre_summary[:-3].rstrip()
        if pre_summary.endswith(")_"):
            # タイムスタンプ行も削除
            lines = pre_summary.split("\n")
            while lines and ("Pre-compact summary" in lines[-1] or lines[-1].strip() == ""):
                lines.pop()
            pre_summary = "\n".join(lines)
        existing_content = pre_summary

    # 200行制限を意識してサマリーを追加
    existing_lines = existing_content.strip().split("\n") if existing_content.strip() else []
    summary_lines = (header + summary).split("\n")
    total_lines = len(existing_lines) + len(summary_lines)

    if total_lines > 180:  # 200行制限にマージンを持たせる
        # サマリーを短縮
        max_summary = 180 - len(existing_lines)
        if max_summary < 10:
            max_summary = 10
            # 既存コンテンツを短縮
            existing_lines = existing_lines[:170]
        summary_lines = summary_lines[:max_summary]

    new_content = "\n".join(existing_lines) + "\n" + "\n".join(summary_lines) + "\n"

    memory_file.write_text(new_content, encoding="utf-8")
    return str(memory_file)


def main():
    parser = argparse.ArgumentParser(description="Convert Claude transcript to readable Markdown")
    parser.add_argument("--transcript", required=True, help="Path to transcript JSONL file")
    parser.add_argument("--session-id", required=True, help="Session ID")
    parser.add_argument("--cwd", default="", help="Current working directory")
    parser.add_argument("--write-memory", action="store_true",
                        help="Write summary to MEMORY.md instead of session log")
    args = parser.parse_args()

    if args.write_memory:
        result = write_summary_to_memory(args.transcript, args.session_id, args.cwd)
        if result:
            print(f"Summary written to memory: {result}", file=sys.stderr)
    else:
        result = save_session_log(args.transcript, args.session_id, args.cwd)
        if result:
            print(f"Session log saved: {result}", file=sys.stderr)


if __name__ == "__main__":
    main()
