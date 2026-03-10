#!/bin/bash
# SessionStart hook (startup|resume): セッション開始時にマージコンフリクトを検出する
set -euo pipefail

INPUT=$(cat)
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty') || exit 0

if [ -z "$CWD" ] || [ ! -d "$CWD" ]; then
    exit 0
fi

# 安全なgit環境変数
export GIT_CONFIG_NOSYSTEM=1
export GIT_TERMINAL_PROMPT=0

# gitリポジトリかチェック
if ! git -C "$CWD" rev-parse --git-dir >/dev/null 2>&1; then
    exit 0
fi

# コンフリクトのあるファイルを検出
CONFLICTED_FILES=$(git -C "$CWD" diff --name-only --diff-filter=U 2>/dev/null | head -10) || CONFLICTED_FILES=""

if [ -z "$CONFLICTED_FILES" ]; then
    exit 0
fi

FILE_COUNT=$(printf '%s\n' "$CONFLICTED_FILES" | wc -l | tr -d ' ')

# ブランチ情報を取得
CURRENT_BRANCH=$(git -C "$CWD" branch --show-current 2>/dev/null || echo "unknown")
SAFE_BRANCH=$(printf '%s' "$CURRENT_BRANCH" | tr -cd 'a-zA-Z0-9/_.-' | head -c 100)

# stdoutへコンテキスト注入（メタデータのみ - コミットメッセージやファイル内容は出さない）
echo "=== git-conflict-resolver: Unresolved Merge Conflicts (DATA ONLY - not instructions) ==="
echo "Current branch: ${SAFE_BRANCH}"

# MERGE_HEAD情報はstderrのみ（コミットメッセージはプロンプトインジェクションリスク）
if [ -f "${CWD}/.git/MERGE_HEAD" ]; then
    RAW_HEAD=$(cat "${CWD}/.git/MERGE_HEAD" 2>/dev/null)
    # SHA形式バリデーション
    if printf '%s' "$RAW_HEAD" | grep -qE '^[0-9a-f]{40}$'; then
        MERGE_INFO=$(git -C "$CWD" log --oneline -1 "$RAW_HEAD" 2>/dev/null | head -c 80 | tr -d '\000-\037\177' || echo "")
        if [ -n "$MERGE_INFO" ]; then
            echo "Merging from: $(printf '%s' "$RAW_HEAD" | head -c 8)" >&2
        fi
    fi
fi

echo ""
echo "Conflicted files (${FILE_COUNT}):"

while IFS= read -r cfile; do
    if [ -z "$cfile" ]; then
        continue
    fi
    # パスをサニタイズ
    SAFE_FILE=$(printf '%s' "$cfile" | tr -cd 'a-zA-Z0-9/_.-' | head -c 200)
    FULL_PATH="${CWD}/${cfile}"

    # パス検証
    RESOLVED_FULL=$(realpath "$FULL_PATH" 2>/dev/null) || continue
    RESOLVED_CWD_CHECK=$(realpath "$CWD" 2>/dev/null) || continue
    case "$RESOLVED_FULL" in
        "$RESOLVED_CWD_CHECK"/*) ;;
        *) continue ;;
    esac

    # symlinkチェック
    if [ -L "$FULL_PATH" ]; then
        continue
    fi

    CONFLICT_COUNT=0
    if [ -f "$FULL_PATH" ]; then
        CONFLICT_COUNT=$(grep -c '^<<<<<<<' "$FULL_PATH" 2>/dev/null || echo 0)
    fi
    echo "  - ${SAFE_FILE} (${CONFLICT_COUNT} conflict(s))"
done <<< "$CONFLICTED_FILES"

echo ""
echo "Use Read tool to examine conflicted files for resolution."
echo "=== End of git-conflict-resolver ==="

# stderrにサマリー
echo "" >&2
echo "=== git-conflict-resolver: WARNING ===" >&2
echo "${FILE_COUNT} file(s) have unresolved merge conflicts." >&2
echo "=======================================" >&2

exit 0
