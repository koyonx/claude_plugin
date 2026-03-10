#!/bin/bash
# SessionStart hook (startup|resume): プロジェクトの既知エラーパターンをコンテキストに注入する
# stdoutへの出力はClaudeのコンテキストに追加される
set -euo pipefail

INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty') || exit 0

if [ -z "$CWD" ]; then
    exit 0
fi

DATA_DIR="$HOME/.claude/error-memory"
if [ ! -d "$DATA_DIR" ]; then
    exit 0
fi

# プロジェクト名を生成
PROJECT_NAME=$(printf '%s' "$CWD" | tr -cd 'a-zA-Z0-9/_.-' | sed 's|/|_|g' | sed 's|^_||')
if [ -z "$PROJECT_NAME" ]; then
    PROJECT_NAME="default"
fi

ERROR_DB="${DATA_DIR}/${PROJECT_NAME}.json"

if [ ! -f "$ERROR_DB" ]; then
    exit 0
fi

# JSONの妥当性チェック
if ! jq empty "$ERROR_DB" 2>/dev/null; then
    exit 0
fi

TOTAL=$(jq 'length' "$ERROR_DB" 2>/dev/null || echo 0)
if [ "$TOTAL" -eq 0 ]; then
    exit 0
fi

# 頻出エラー（resolved_count上位5件）をstdoutでコンテキストに注入
echo "=== error-memory: Known Error Patterns for This Project ==="
echo "The following error patterns have been encountered and resolved before."
echo "Use these solutions if similar errors occur:"
echo ""

jq -r 'sort_by(-.resolved_count) | .[0:5] | .[] |
    "- Error: \(.error_key)\n  Solution: \(.solution)\n  Resolved: \(.resolved_count) time(s)\n"' \
    "$ERROR_DB" 2>/dev/null \
    | sed 's/<[^>]*>//g' \
    | tr -d '\000-\010\013\014\016-\037\177'

echo "=== End of error-memory ==="

# stderrにサマリーを表示
echo "" >&2
echo "=== error-memory ===" >&2
echo "Known error patterns: ${TOTAL}" >&2
# 頻出トップ3を表示
jq -r 'sort_by(-.resolved_count) | .[0:3] | .[] |
    "  \(.error_key) (resolved \(.resolved_count)x)"' \
    "$ERROR_DB" 2>/dev/null >&2 || true
echo "====================" >&2

exit 0
