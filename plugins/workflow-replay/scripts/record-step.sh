#!/bin/bash
# PostToolUse hook (Write|Edit|Bash): 操作をワークフローステップとして記録する
set -euo pipefail

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty') || exit 0
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty') || exit 0
CWD=$(echo "$INPUT" | jq -r '.cwd // empty') || exit 0

if [ -z "$TOOL_NAME" ] || [ -z "$SESSION_ID" ] || [ -z "$CWD" ]; then
    exit 0
fi

# Write|Edit|Bash以外はスキップ
case "$TOOL_NAME" in
    Write|Edit|Bash) ;;
    *) exit 0 ;;
esac

# session_idをサニタイズ
SAFE_SESSION_ID=$(printf '%s' "$SESSION_ID" | tr -cd 'a-zA-Z0-9-')
if [ -z "$SAFE_SESSION_ID" ]; then
    SAFE_SESSION_ID="unknown"
fi

# データディレクトリ
DATA_DIR="$HOME/.claude/workflow-replay"
RECORDING_DIR="${DATA_DIR}/recording"
mkdir -p "$RECORDING_DIR"
chmod 700 "$DATA_DIR" 2>/dev/null || true

# 録画ファイル・フラグ
RECORDING_FLAG="${RECORDING_DIR}/${SAFE_SESSION_ID}.recording"
RECORDING_FILE="${RECORDING_DIR}/${SAFE_SESSION_ID}.jsonl"
LOCK_FILE="${RECORDING_FILE}.lock"

# 録画中フラグの事前チェック（ロック外で高速パス）
if [ ! -f "$RECORDING_FLAG" ]; then
    exit 0
fi

TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# ツール入力を取得・サニタイズ
case "$TOOL_NAME" in
    Write)
        FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty') || FILE_PATH=""
        # ファイルパスのみ記録（内容は記録しない - セキュリティ上）
        STEP=$(jq -n -c \
            --arg tool "$TOOL_NAME" \
            --arg file "$FILE_PATH" \
            --arg ts "$TIMESTAMP" \
            --arg desc "Write file" \
            '{"tool": $tool, "file_path": $file, "timestamp": $ts, "description": $desc}')
        ;;
    Edit)
        FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty') || FILE_PATH=""
        STEP=$(jq -n -c \
            --arg tool "$TOOL_NAME" \
            --arg file "$FILE_PATH" \
            --arg ts "$TIMESTAMP" \
            --arg desc "Edit file" \
            '{"tool": $tool, "file_path": $file, "timestamp": $ts, "description": $desc}')
        ;;
    Bash)
        COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty') || COMMAND=""
        # コマンドを500文字に制限
        SAFE_CMD=$(printf '%s' "$COMMAND" | sed 's/<[^>]*>//g' | tr -d '\000-\010\013\014\016-\037\177' | head -c 500)
        STEP=$(jq -n -c \
            --arg tool "$TOOL_NAME" \
            --arg cmd "$SAFE_CMD" \
            --arg ts "$TIMESTAMP" \
            --arg desc "Run command" \
            '{"tool": $tool, "command": $cmd, "timestamp": $ts, "description": $desc}')
        ;;
    *)
        exit 0
        ;;
esac

# ステップを記録（flock排他制御、フラグの再チェック付き）
(
    flock -w 5 200 || exit 0
    # ロック内でフラグを再チェック（TOCTOU防止）
    if [ ! -f "$RECORDING_FLAG" ]; then
        exit 0
    fi
    printf '%s\n' "$STEP" >> "$RECORDING_FILE"

    # ステップ数制限（最大500ステップ）
    STEP_COUNT=$(wc -l < "$RECORDING_FILE" 2>/dev/null || echo 0)
    if [ "$STEP_COUNT" -gt 500 ]; then
        echo "" >&2
        echo "=== workflow-replay: Recording limit reached (500 steps) ===" >&2
        echo "Use '/replay save <name>' to save the current recording." >&2
        echo "============================================================" >&2
    fi
) 200>"$LOCK_FILE"

exit 0
