#!/bin/bash
# Stop hook: セッション終了時に引き継ぎメモを自動生成する
set -euo pipefail

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty') || exit 0
CWD=$(echo "$INPUT" | jq -r '.cwd // empty') || exit 0
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty') || exit 0

if [ -z "$SESSION_ID" ] || [ -z "$CWD" ]; then
    exit 0
fi

# session_idをサニタイズ
SAFE_SESSION_ID=$(printf '%s' "$SESSION_ID" | tr -cd 'a-zA-Z0-9-')
if [ -z "$SAFE_SESSION_ID" ]; then
    exit 0
fi

# データディレクトリ
DATA_DIR="$HOME/.claude/session-handoff"
mkdir -p "$DATA_DIR"
chmod 700 "$DATA_DIR" 2>/dev/null || true

TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
DISPLAY_TIME=$(date +"%Y-%m-%d %H:%M:%S")

# プロジェクト名を生成
PROJECT_NAME=$(printf '%s' "$CWD" | tr -cd 'a-zA-Z0-9/_.-' | sed 's|/|_|g' | sed 's|^_||')
if [ -z "$PROJECT_NAME" ]; then
    PROJECT_NAME="default"
fi

# git情報を収集（利用可能な場合）
GIT_BRANCH=""
GIT_STATUS=""
GIT_RECENT_COMMITS=""
if git -C "$CWD" rev-parse --git-dir >/dev/null 2>&1; then
    GIT_BRANCH=$(git -C "$CWD" branch --show-current 2>/dev/null || echo "")
    GIT_STATUS=$(git -C "$CWD" status --short 2>/dev/null | head -20 || echo "")
    GIT_RECENT_COMMITS=$(git -C "$CWD" log --oneline -5 2>/dev/null || echo "")
fi

# サニタイズ関数
sanitize() {
    printf '%s' "$1" | sed 's/<[^>]*>//g' | tr -d '\000-\010\013\014\016-\037\177' | head -c 1000
}

# 引き継ぎメモを生成
HANDOFF_FILE="${DATA_DIR}/${SAFE_SESSION_ID}.json"

SAFE_BRANCH=$(sanitize "$GIT_BRANCH")
SAFE_STATUS=$(sanitize "$GIT_STATUS")
SAFE_COMMITS=$(sanitize "$GIT_RECENT_COMMITS")
SAFE_CWD=$(sanitize "$CWD")

jq -n \
    --arg session_id "$SAFE_SESSION_ID" \
    --arg project "$SAFE_CWD" \
    --arg project_name "$PROJECT_NAME" \
    --arg timestamp "$TIMESTAMP" \
    --arg display_time "$DISPLAY_TIME" \
    --arg branch "$SAFE_BRANCH" \
    --arg git_status "$SAFE_STATUS" \
    --arg recent_commits "$SAFE_COMMITS" \
    --arg status "pending" \
    '{
        session_id: $session_id,
        project: $project,
        project_name: $project_name,
        timestamp: $timestamp,
        display_time: $display_time,
        git: {
            branch: $branch,
            status: $git_status,
            recent_commits: $recent_commits
        },
        status: $status
    }' > "$HANDOFF_FILE"

# 最新の引き継ぎメモへのシンボリックリンクを更新（プロジェクト別）
LATEST_LINK="${DATA_DIR}/latest_${PROJECT_NAME}.json"
ln -sf "$HANDOFF_FILE" "$LATEST_LINK" 2>/dev/null || true

echo "" >&2
echo "=== session-handoff ===" >&2
echo "Handoff note generated: ${SAFE_SESSION_ID}" >&2
echo "Use '/handoff ${SAFE_SESSION_ID}' in another session to load context." >&2
echo "========================" >&2

# 古い引き継ぎメモを整理（30日以上前）
find "$DATA_DIR" -maxdepth 1 -name "*.json" -mtime +30 -delete 2>/dev/null || true

exit 0
