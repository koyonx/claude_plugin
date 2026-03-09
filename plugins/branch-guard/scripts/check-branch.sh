#!/bin/bash
# PreToolUse hook: 保護ブランチへの直接コミット/プッシュをブロックする
set -euo pipefail

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty') || exit 0
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty') || exit 0
CWD=$(echo "$INPUT" | jq -r '.cwd // empty') || exit 0

if [ -z "$COMMAND" ]; then
    exit 0
fi

# gitコマンドでなければスキップ
if ! echo "$COMMAND" | grep -qE '^\s*(git\s|git$)'; then
    exit 0
fi

# git commit または git push かチェック
IS_COMMIT=false
IS_PUSH=false
if echo "$COMMAND" | grep -qE 'git\s+commit'; then
    IS_COMMIT=true
fi
if echo "$COMMAND" | grep -qE 'git\s+push'; then
    IS_PUSH=true
fi

if [ "$IS_COMMIT" = false ] && [ "$IS_PUSH" = false ]; then
    exit 0
fi

# 現在のブランチを取得
CURRENT_BRANCH=""
if [ -n "$CWD" ] && [ -d "$CWD/.git" ] || git -C "${CWD:-.}" rev-parse --git-dir >/dev/null 2>&1; then
    CURRENT_BRANCH=$(git -C "${CWD:-.}" branch --show-current 2>/dev/null || echo "")
fi

if [ -z "$CURRENT_BRANCH" ]; then
    exit 0
fi

# 保護ブランチの設定を読み込み
PROTECTED_BRANCHES="main master"
CONFIG_FILE="${CWD:-.}/.branch-guard.json"
if [ -f "$CONFIG_FILE" ]; then
    CUSTOM_BRANCHES=$(jq -r '.protected_branches[]? // empty' "$CONFIG_FILE" 2>/dev/null || echo "")
    if [ -n "$CUSTOM_BRANCHES" ]; then
        PROTECTED_BRANCHES="$CUSTOM_BRANCHES"
    fi
fi

# 現在のブランチが保護対象かチェック
IS_PROTECTED=false
for branch in $PROTECTED_BRANCHES; do
    if [ "$CURRENT_BRANCH" = "$branch" ]; then
        IS_PROTECTED=true
        break
    fi
done

if [ "$IS_PROTECTED" = false ]; then
    exit 0
fi

# ブロック
if [ "$IS_COMMIT" = true ]; then
    echo "{\"decision\": \"block\", \"reason\": \"Direct commit to protected branch '${CURRENT_BRANCH}' is not allowed. Create a feature branch first.\"}"
elif [ "$IS_PUSH" = true ]; then
    echo "{\"decision\": \"block\", \"reason\": \"Direct push to protected branch '${CURRENT_BRANCH}' is not allowed. Use a PR workflow.\"}"
fi

exit 0
