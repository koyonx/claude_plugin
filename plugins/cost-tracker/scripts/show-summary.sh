#!/bin/bash
# SessionStart hook: プロジェクトの累計コストサマリーを表示する
set -euo pipefail

INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty') || exit 0

if [ -z "$CWD" ]; then
    exit 0
fi

PROJECT_NAME=$(echo "$CWD" | sed 's|/|_|g' | sed 's|^_||' | tr -cd 'a-zA-Z0-9_.-')
DATA_DIR="$HOME/.claude/cost-tracker/${PROJECT_NAME}"

if [ ! -d "$DATA_DIR" ]; then
    exit 0
fi

# 使用量ログの集計
TOTAL_INPUT=0
TOTAL_OUTPUT=0
SESSION_COUNT=0

for f in "$DATA_DIR"/*.json; do
    [ -f "$f" ] || continue
    SESSION_COUNT=$((SESSION_COUNT + 1))
    INPUT_TOKENS=$(jq -r '.total_input_tokens // 0' "$f" 2>/dev/null || echo 0)
    OUTPUT_TOKENS=$(jq -r '.total_output_tokens // 0' "$f" 2>/dev/null || echo 0)
    TOTAL_INPUT=$((TOTAL_INPUT + INPUT_TOKENS))
    TOTAL_OUTPUT=$((TOTAL_OUTPUT + OUTPUT_TOKENS))
done

if [ "$SESSION_COUNT" -gt 0 ]; then
    echo "" >&2
    echo "=== cost-tracker ===" >&2
    echo "Project: ${CWD}" >&2
    echo "Sessions: ${SESSION_COUNT}" >&2
    echo "Total input tokens: ${TOTAL_INPUT}" >&2
    echo "Total output tokens: ${TOTAL_OUTPUT}" >&2
    echo "====================" >&2
    echo "" >&2
fi

exit 0
