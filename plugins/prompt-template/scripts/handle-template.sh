#!/bin/bash
# UserPromptSubmit hook: /template コマンドを検出してテンプレートを展開する
set -euo pipefail

INPUT=$(cat)
PROMPT=$(echo "$INPUT" | jq -r '.prompt // empty') || exit 0

if [ -z "$PROMPT" ]; then
    exit 0
fi

# /template で始まるかチェック
if ! echo "$PROMPT" | grep -q '^/template '; then
    exit 0
fi

# テンプレート名を抽出（英数字とハイフンのみ許可）
TEMPLATE_NAME=$(echo "$PROMPT" | sed 's|^/template ||' | tr -cd 'a-zA-Z0-9-' | head -c 64)

if [ -z "$TEMPLATE_NAME" ]; then
    echo '{"decision": "block", "reason": "Usage: /template <name>. Available: review, refactor, test"}'
    exit 0
fi

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"

# ユーザーカスタムテンプレートを優先
USER_TEMPLATE_DIR="$HOME/.claude/prompt-templates"
BUILTIN_TEMPLATE_DIR="${PLUGIN_ROOT}/templates"

TEMPLATE_FILE=""
if [ -f "${USER_TEMPLATE_DIR}/${TEMPLATE_NAME}.md" ]; then
    TEMPLATE_FILE="${USER_TEMPLATE_DIR}/${TEMPLATE_NAME}.md"
elif [ -f "${BUILTIN_TEMPLATE_DIR}/${TEMPLATE_NAME}.md" ]; then
    TEMPLATE_FILE="${BUILTIN_TEMPLATE_DIR}/${TEMPLATE_NAME}.md"
fi

if [ -z "$TEMPLATE_FILE" ]; then
    # 利用可能なテンプレート一覧
    AVAILABLE=""
    for f in "$BUILTIN_TEMPLATE_DIR"/*.md "$USER_TEMPLATE_DIR"/*.md 2>/dev/null; do
        [ -f "$f" ] || continue
        name=$(basename "$f" .md)
        AVAILABLE="${AVAILABLE} ${name}"
    done
    echo "{\"decision\": \"block\", \"reason\": \"Template '${TEMPLATE_NAME}' not found. Available:${AVAILABLE}\"}"
    exit 0
fi

# テンプレート内容を読み込み（サイズ制限: 1MB）
FILE_SIZE=$(stat -f%z "$TEMPLATE_FILE" 2>/dev/null || stat -c%s "$TEMPLATE_FILE" 2>/dev/null || echo 0)
if [ "$FILE_SIZE" -gt 1048576 ]; then
    echo '{"decision": "block", "reason": "Template file too large (max 1MB)"}'
    exit 0
fi

TEMPLATE_CONTENT=$(cat "$TEMPLATE_FILE")

# プロンプトをテンプレート内容に置換
echo "{\"prompt\": $(echo "$TEMPLATE_CONTENT" | jq -Rs .)}"

exit 0
