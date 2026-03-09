#!/bin/bash
# SessionStart hook (compact): コンパクト後に会話サマリーをコンテキストに注入する
# stdoutに出力した内容がClaudeのコンテキストに追加される
set -euo pipefail

INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty') || exit 0

if [ -z "$CWD" ]; then
    exit 0
fi

# プロジェクトのmemoryディレクトリからMEMORY.mdを検索
CLAUDE_DIR="$HOME/.claude"
PROJECT_ID=$(echo "$CWD" | sed 's|/|-|g')
MEMORY_FILE="${CLAUDE_DIR}/projects/${PROJECT_ID}/memory/MEMORY.md"

# 別のパス形式も試行
if [ ! -f "$MEMORY_FILE" ]; then
    PROJECT_ID="-$(echo "$CWD" | sed 's|/|-|g')"
    MEMORY_FILE="${CLAUDE_DIR}/projects/${PROJECT_ID}/memory/MEMORY.md"
fi

if [ ! -f "$MEMORY_FILE" ]; then
    exit 0
fi

# MEMORY.mdからSession History Summaryセクションを抽出してstdoutに出力
# stdoutへの出力はClaudeのコンテキストに注入される
if grep -q "## Session History Summary" "$MEMORY_FILE" 2>/dev/null; then
    echo "=== Previous Session Context (restored after compaction) ==="
    # サマリーセクションのみ抽出し、HTMLタグ・制御文字を除去してから出力
    sed -n '/## Session History Summary/,$p' "$MEMORY_FILE" \
        | sed 's/<[^>]*>//g' \
        | tr -d '\000-\010\013\014\016-\037\177'
    echo "=== End of Previous Session Context ==="
fi

exit 0
