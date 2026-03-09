#!/bin/bash
# PreToolUse hook (Bash): 危険なコマンドを検出して警告し、全コマンドをログに記録する
set -euo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty') || exit 0
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty') || exit 0
CWD=$(echo "$INPUT" | jq -r '.cwd // empty') || exit 0

if [ -z "$COMMAND" ]; then
    exit 0
fi

# session_idをサニタイズ
SAFE_SESSION_ID=$(echo "$SESSION_ID" | tr -cd 'a-zA-Z0-9-')
if [ -z "$SAFE_SESSION_ID" ]; then
    SAFE_SESSION_ID="unknown"
fi

# ログディレクトリ
LOG_DIR="$HOME/.claude/command-audit"
mkdir -p "$LOG_DIR"

SESSION_LOG="${LOG_DIR}/${SAFE_SESSION_ID}.jsonl"

# コマンドをログに記録（jqで安全なJSON生成）
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
jq -n -c \
    --arg cmd "$COMMAND" \
    --arg ts "$TIMESTAMP" \
    --arg cwd "$CWD" \
    --arg status "executed" \
    '{"command": $cmd, "timestamp": $ts, "cwd": $cwd, "status": $status}' >> "$SESSION_LOG"

# ログファイルサイズ制限 (10MB)
MAX_LOG_SIZE=$((10 * 1024 * 1024))
LOG_SIZE=$(stat -f%z "$SESSION_LOG" 2>/dev/null || stat -c%s "$SESSION_LOG" 2>/dev/null || echo 0)
if [ "$LOG_SIZE" -gt "$MAX_LOG_SIZE" ]; then
    # 古いエントリを削除（後半のみ保持）
    tail -n 1000 "$SESSION_LOG" > "${SESSION_LOG}.tmp"
    mv "${SESSION_LOG}.tmp" "$SESSION_LOG"
fi

# === 危険コマンド検出 ===

# 危険パターンの定義
DANGEROUS_PATTERNS=(
    # ファイル削除系
    'rm\s+-[a-zA-Z]*r[a-zA-Z]*f|rm\s+-[a-zA-Z]*f[a-zA-Z]*r'
    'rm\s+-rf\s+/'
    'rm\s+-rf\s+\*'
    'rm\s+-rf\s+~'
    # Git破壊操作
    'git\s+push\s+.*--force'
    'git\s+push\s+-f\b'
    'git\s+reset\s+--hard'
    'git\s+clean\s+-[a-zA-Z]*f'
    'git\s+checkout\s+--\s+\.'
    'git\s+branch\s+-D'
    # データベース破壊操作
    'DROP\s+(TABLE|DATABASE|SCHEMA)'
    'TRUNCATE\s+TABLE'
    'DELETE\s+FROM\s+\S+\s*;?\s*$'
    # システム操作
    'chmod\s+-R\s+777'
    'chmod\s+777'
    'chown\s+-R'
    # 危険なリダイレクト
    '>\s*/dev/sd'
    'dd\s+.*of=/dev/'
    'mkfs\.'
    # プロセス操作
    'kill\s+-9\s+-1'
    'killall'
    # 環境破壊
    'pip\s+install\s+--break-system-packages'
    'npm\s+cache\s+clean\s+--force'
)

MATCHED_PATTERN=""
for pattern in "${DANGEROUS_PATTERNS[@]}"; do
    if echo "$COMMAND" | grep -qiE "$pattern"; then
        MATCHED_PATTERN="$pattern"
        break
    fi
done

if [ -z "$MATCHED_PATTERN" ]; then
    # 危険でなければそのまま通す
    exit 0
fi

# 危険コマンドをログに記録（ステータスを更新）
jq -n -c \
    --arg cmd "$COMMAND" \
    --arg ts "$TIMESTAMP" \
    --arg cwd "$CWD" \
    --arg status "warned" \
    --arg pattern "$MATCHED_PATTERN" \
    '{"command": $cmd, "timestamp": $ts, "cwd": $cwd, "status": $status, "matched_pattern": $pattern}' >> "$SESSION_LOG"

# 警告を表示（stderrはユーザーに表示される）
echo "" >&2
echo "⚠ === command-audit: DANGEROUS COMMAND DETECTED ===" >&2
echo "Command: ${COMMAND}" >&2
echo "Pattern: ${MATCHED_PATTERN}" >&2
echo "===================================================" >&2

# ブロックはせず警告のみ（ユーザーの承認フローに委ねる）
# ブロックしたい場合はコメントを外す:
# jq -n --arg cmd "$COMMAND" \
#     '{"decision": "block", "reason": ("Dangerous command detected: " + $cmd + ". Please confirm this is intentional.")}'

exit 0
