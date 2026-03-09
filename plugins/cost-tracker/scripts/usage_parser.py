#!/usr/bin/env python3
"""トランスクリプトからトークン使用量を抽出・記録する。"""

import argparse
import json
import re
import sys
from datetime import datetime
from pathlib import Path

MAX_TRANSCRIPT_SIZE = 100 * 1024 * 1024  # 100MB


def sanitize_filename(name: str) -> str:
    return re.sub(r"[^a-zA-Z0-9_.\-]", "", name)


def validate_path(path: str) -> bool:
    claude_dir = Path.home() / ".claude"
    try:
        resolved = Path(path).resolve()
        return resolved.is_relative_to(claude_dir)
    except (OSError, ValueError):
        return False


def parse_usage(transcript_path: str) -> dict:
    """トランスクリプトからトークン使用量を集計する。"""
    file_size = Path(transcript_path).stat().st_size
    if file_size > MAX_TRANSCRIPT_SIZE:
        print(f"Transcript too large ({file_size} bytes). Skipping.", file=sys.stderr)
        return {}

    total_input = 0
    total_output = 0
    total_cache_read = 0
    total_cache_create = 0
    request_count = 0

    with open(transcript_path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                event = json.loads(line)
            except json.JSONDecodeError:
                continue

            # assistantメッセージからusage情報を抽出
            message = event.get("message", event)
            usage = message.get("usage", {})
            if not usage:
                continue

            input_tokens = usage.get("input_tokens", 0)
            output_tokens = usage.get("output_tokens", 0)
            cache_read = usage.get("cache_read_input_tokens", 0)
            cache_create = usage.get("cache_creation_input_tokens", 0)

            if input_tokens or output_tokens:
                total_input += input_tokens
                total_output += output_tokens
                total_cache_read += cache_read
                total_cache_create += cache_create
                request_count += 1

    return {
        "total_input_tokens": total_input,
        "total_output_tokens": total_output,
        "total_cache_read_tokens": total_cache_read,
        "total_cache_create_tokens": total_cache_create,
        "request_count": request_count,
    }


def save_usage(transcript_path: str, session_id: str, cwd: str) -> str | None:
    if not validate_path(transcript_path):
        print(f"Invalid transcript path: {transcript_path}", file=sys.stderr)
        return None

    usage = parse_usage(transcript_path)
    if not usage or usage.get("request_count", 0) == 0:
        return None

    usage["session_id"] = session_id
    usage["cwd"] = cwd
    usage["timestamp"] = datetime.now().isoformat()

    project_name = sanitize_filename(cwd.replace("/", "_").lstrip("_"))
    if not project_name:
        project_name = "unknown_project"

    data_dir = Path.home() / ".claude" / "cost-tracker" / project_name
    data_dir.mkdir(parents=True, exist_ok=True)

    safe_session_id = sanitize_filename(session_id)[:16] or "unknown"
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    filename = f"{timestamp}_{safe_session_id}.json"
    output_path = data_dir / filename

    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(usage, f, indent=2, ensure_ascii=False)

    return str(output_path)


def main():
    parser = argparse.ArgumentParser(description="Extract token usage from transcript")
    parser.add_argument("--transcript", required=True)
    parser.add_argument("--session-id", required=True)
    parser.add_argument("--cwd", default="")
    args = parser.parse_args()

    result = save_usage(args.transcript, args.session_id, args.cwd)
    if result:
        print(f"Usage recorded: {result}", file=sys.stderr)


if __name__ == "__main__":
    main()
