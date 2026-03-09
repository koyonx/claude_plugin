#!/usr/bin/env python3
"""
トランスクリプトJSONLファイルをセッションごとの読みやすいMarkdownに変換する。
"""

import argparse
import json
import os
import sys
from datetime import datetime
from pathlib import Path


def parse_transcript(transcript_path: str) -> list[dict]:
    """JSONLトランスクリプトファイルを読み込んでイベントリストを返す。"""
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
                    # ツール結果は省略（長くなりすぎるため）
                    pass
            elif isinstance(block, str):
                texts.append(block)
        return "\n".join(texts)
    return str(content) if content else ""


def format_timestamp(ts) -> str:
    """タイムスタンプを読みやすい形式に変換する。"""
    if not ts:
        return ""
    try:
        if isinstance(ts, (int, float)):
            # ミリ秒の場合
            if ts > 1e12:
                ts = ts / 1000
            dt = datetime.fromtimestamp(ts)
        elif isinstance(ts, str):
            dt = datetime.fromisoformat(ts.replace("Z", "+00:00"))
        else:
            return ""
        return dt.strftime("%Y-%m-%d %H:%M:%S")
    except (ValueError, OSError):
        return ""


def events_to_markdown(events: list[dict], session_id: str, cwd: str) -> str:
    """イベントリストからMarkdown形式の会話ログを生成する。"""
    lines = []
    now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    lines.append(f"# Session Log: {session_id[:8]}")
    lines.append("")
    lines.append(f"- **Session ID**: `{session_id}`")
    lines.append(f"- **Project**: `{cwd}`")
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

        # メッセージイベントのみ処理
        if role == "user" or event_type == "user_message":
            text = extract_text_content(content)
            if not text or text.strip() == "":
                continue
            # system-reminder等のタグを除去
            if "<system-reminder>" in text and "</system-reminder>" in text:
                import re
                text = re.sub(
                    r"<system-reminder>.*?</system-reminder>", "", text, flags=re.DOTALL
                ).strip()
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
    events = parse_transcript(transcript_path)
    if not events:
        return None

    markdown = events_to_markdown(events, session_id, cwd)
    if not markdown:
        return None

    # プロジェクトパスからディレクトリ名を生成
    project_name = cwd.replace("/", "_").lstrip("_")
    session_dir = Path.home() / ".claude" / "session-history" / "sessions" / project_name
    session_dir.mkdir(parents=True, exist_ok=True)

    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    filename = f"{timestamp}_{session_id[:8]}.md"
    output_path = session_dir / filename

    with open(output_path, "w", encoding="utf-8") as f:
        f.write(markdown)

    return str(output_path)


def main():
    parser = argparse.ArgumentParser(description="Convert Claude transcript to readable Markdown")
    parser.add_argument("--transcript", required=True, help="Path to transcript JSONL file")
    parser.add_argument("--session-id", required=True, help="Session ID")
    parser.add_argument("--cwd", default="", help="Current working directory")
    args = parser.parse_args()

    result = save_session_log(args.transcript, args.session_id, args.cwd)
    if result:
        print(f"Session log saved: {result}", file=sys.stderr)


if __name__ == "__main__":
    main()
