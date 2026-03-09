#!/bin/bash
# Stop hook: Claudeの応答完了時にトランスクリプトを読みやすい形式で保存する
set -euo pipefail

INPUT=$(cat)
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty')
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')

if [ -z "$TRANSCRIPT_PATH" ] || [ -z "$SESSION_ID" ] || [ ! -f "$TRANSCRIPT_PATH" ]; then
    exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
python3 "${SCRIPT_DIR}/../transcript_parser.py" \
    --transcript "$TRANSCRIPT_PATH" \
    --session-id "$SESSION_ID" \
    --cwd "$CWD"

exit 0
