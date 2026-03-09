#!/bin/bash
# SessionStart hook (startup|resume): プロジェクトの未解決TODO一覧を表示する
# stderrに出力した内容がユーザーに表示される
set -euo pipefail

INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty') || exit 0

if [ -z "$CWD" ]; then
    exit 0
fi

DATA_DIR="$HOME/.claude/todo-tracker"
if [ ! -d "$DATA_DIR" ]; then
    exit 0
fi

# プロジェクト名をCWDから生成
PROJECT_NAME=$(echo "$CWD" | tr -cd 'a-zA-Z0-9/_.-' | sed 's|/|_|g' | sed 's|^_||')
if [ -z "$PROJECT_NAME" ]; then
    PROJECT_NAME="default"
fi

TODO_FILE="${DATA_DIR}/${PROJECT_NAME}.json"

if [ ! -f "$TODO_FILE" ]; then
    exit 0
fi

# JSONの妥当性チェック
if ! jq empty "$TODO_FILE" 2>/dev/null; then
    exit 0
fi

TOTAL=$(jq 'length' "$TODO_FILE" 2>/dev/null || echo 0)
if [ "$TOTAL" -eq 0 ]; then
    exit 0
fi

# マーカー種別ごとの集計
TODO_COUNT=$(jq '[.[] | select(.marker == "TODO")] | length' "$TODO_FILE" 2>/dev/null || echo 0)
FIXME_COUNT=$(jq '[.[] | select(.marker == "FIXME")] | length' "$TODO_FILE" 2>/dev/null || echo 0)
HACK_COUNT=$(jq '[.[] | select(.marker == "HACK")] | length' "$TODO_FILE" 2>/dev/null || echo 0)
XXX_COUNT=$(jq '[.[] | select(.marker == "XXX")] | length' "$TODO_FILE" 2>/dev/null || echo 0)

echo "" >&2
echo "=== todo-tracker ===" >&2
echo "Project TODOs: ${TOTAL} total" >&2

SUMMARY=""
[ "$TODO_COUNT" -gt 0 ] && SUMMARY="${SUMMARY} TODO:${TODO_COUNT}"
[ "$FIXME_COUNT" -gt 0 ] && SUMMARY="${SUMMARY} FIXME:${FIXME_COUNT}"
[ "$HACK_COUNT" -gt 0 ] && SUMMARY="${SUMMARY} HACK:${HACK_COUNT}"
[ "$XXX_COUNT" -gt 0 ] && SUMMARY="${SUMMARY} XXX:${XXX_COUNT}"
echo " ${SUMMARY}" >&2

# FIXMEがある場合は強調表示
if [ "$FIXME_COUNT" -gt 0 ]; then
    echo "" >&2
    echo "FIXME items (high priority):" >&2
    jq -r '.[] | select(.marker == "FIXME") | "  \(.file):\(.line) - \(.content)"' "$TODO_FILE" 2>/dev/null | head -5 >&2
    if [ "$FIXME_COUNT" -gt 5 ]; then
        echo "  ... and $((FIXME_COUNT - 5)) more" >&2
    fi
fi

# 存在しないファイルのエントリ数を表示（解決済みの可能性）
STALE_COUNT=0
while IFS= read -r filepath; do
    if [ ! -f "$filepath" ]; then
        STALE_COUNT=$((STALE_COUNT + 1))
    fi
done < <(jq -r '.[].file' "$TODO_FILE" 2>/dev/null | sort -u)

if [ "$STALE_COUNT" -gt 0 ]; then
    echo "" >&2
    echo "Note: ${STALE_COUNT} file(s) no longer exist (may have been resolved)" >&2
fi

echo "====================" >&2

exit 0
