#!/bin/bash
# SessionStart hook: 現在のブランチ情報と保護状態を表示する
set -euo pipefail

INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty') || exit 0

if [ -z "$CWD" ] || [ ! -d "$CWD" ]; then
    exit 0
fi

# gitリポジトリかチェック
if ! git -C "$CWD" rev-parse --git-dir >/dev/null 2>&1; then
    exit 0
fi

CURRENT_BRANCH=$(git -C "$CWD" branch --show-current 2>/dev/null || echo "")
if [ -z "$CURRENT_BRANCH" ]; then
    exit 0
fi

# 保護ブランチの設定を読み込み
PROTECTED_BRANCHES="main master"
CONFIG_FILE="${CWD}/.branch-guard.json"
if [ -f "$CONFIG_FILE" ]; then
    CUSTOM_BRANCHES=$(jq -r '.protected_branches[]? // empty' "$CONFIG_FILE" 2>/dev/null || echo "")
    if [ -n "$CUSTOM_BRANCHES" ]; then
        PROTECTED_BRANCHES="$CUSTOM_BRANCHES"
    fi
fi

IS_PROTECTED=false
for branch in $PROTECTED_BRANCHES; do
    if [ "$CURRENT_BRANCH" = "$branch" ]; then
        IS_PROTECTED=true
        break
    fi
done

echo "" >&2
echo "=== branch-guard ===" >&2
echo "Current branch: ${CURRENT_BRANCH}" >&2
if [ "$IS_PROTECTED" = true ]; then
    echo "WARNING: You are on a PROTECTED branch. Direct commits/pushes will be blocked." >&2
    echo "Create a feature branch before making changes." >&2
else
    echo "Status: OK (not a protected branch)" >&2
fi
echo "====================" >&2
echo "" >&2

exit 0
