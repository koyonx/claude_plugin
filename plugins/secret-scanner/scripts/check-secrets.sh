#!/bin/bash
# PreToolUse hook (Write|Edit): ファイル書き込み前にシークレットをスキャンしてブロックする
set -euo pipefail

INPUT=$(cat)
TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty') || exit 0
TOOL_INPUT=$(printf '%s' "$INPUT" | jq -r '.tool_input // empty') || exit 0

if [ -z "$TOOL_NAME" ]; then
    exit 0
fi

# ファイルパスを取得
FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty') || exit 0
if [ -z "$FILE_PATH" ]; then
    exit 0
fi

# スキャン対象外の拡張子
BASENAME=$(basename "$FILE_PATH")
EXT="${BASENAME##*.}"
case "$EXT" in
    md|txt|lock|sum|png|jpg|jpeg|gif|svg|ico|woff|woff2|ttf|eot|pdf)
        exit 0
        ;;
esac

# テスト・モックファイルをスキップ
case "$BASENAME" in
    *test*|*mock*|*fixture*|*fake*|*stub*|*example*|*sample*)
        exit 0
        ;;
esac
case "$FILE_PATH" in
    *test/*|*tests/*|*__tests__/*|*mock/*|*mocks/*|*fixture*/*|*testdata/*)
        exit 0
        ;;
esac

# スキャン対象のコンテンツを取得
CONTENT=""
if [ "$TOOL_NAME" = "Write" ]; then
    CONTENT=$(printf '%s' "$INPUT" | jq -r '.tool_input.content // empty') || exit 0
elif [ "$TOOL_NAME" = "Edit" ]; then
    CONTENT=$(printf '%s' "$INPUT" | jq -r '.tool_input.new_string // empty') || exit 0
fi

if [ -z "$CONTENT" ]; then
    exit 0
fi

# 一時ファイルにコンテンツを書き出してスキャン
TMPFILE=$(mktemp)
trap 'rm -f "$TMPFILE"' EXIT

printf '%s' "$CONTENT" > "$TMPFILE"

DETECTED=""

# AWS Access Key
if grep -qE 'AKIA[0-9A-Z]{16}' "$TMPFILE" 2>/dev/null; then
    DETECTED="AWS Access Key (AKIA...)"
fi

# GitHub Token
if [ -z "$DETECTED" ] && grep -qE 'gh[pousr]_[A-Za-z0-9_]{36,}' "$TMPFILE" 2>/dev/null; then
    DETECTED="GitHub Token (ghp_/gho_/ghu_/ghs_/ghr_)"
fi

# Private Key
if [ -z "$DETECTED" ] && grep -qE -- '-----BEGIN (RSA |EC |DSA |OPENSSH )?PRIVATE KEY-----' "$TMPFILE" 2>/dev/null; then
    DETECTED="Private Key"
fi

# Generic API Key/Secret assignment
if [ -z "$DETECTED" ] && grep -qiE '(api[_-]?key|apikey|api[_-]?secret)\s*[:=]\s*['"'"'"][^'"'"'"]{8,}' "$TMPFILE" 2>/dev/null; then
    DETECTED="API Key/Secret assignment"
fi

# Generic token/password/secret assignment
if [ -z "$DETECTED" ] && grep -qiE '(secret_key|private_key|access_token|auth_token)\s*[:=]\s*['"'"'"][^'"'"'"]{8,}' "$TMPFILE" 2>/dev/null; then
    DETECTED="Secret/Token assignment"
fi

# Password assignment
if [ -z "$DETECTED" ] && grep -qiE '(password|passwd|pwd)\s*[:=]\s*['"'"'"][^'"'"'"]{8,}' "$TMPFILE" 2>/dev/null; then
    # パスワードバリデーションやプレースホルダーを除外
    if ! grep -qiE '(password|passwd|pwd)\s*[:=]\s*['"'"'"](your_|change_me|placeholder|example|xxx|\\$\{|process\.env|os\.environ)' "$TMPFILE" 2>/dev/null; then
        DETECTED="Password assignment"
    fi
fi

# Bearer/Basic auth tokens
if [ -z "$DETECTED" ] && grep -qiE '(basic|bearer)\s+[A-Za-z0-9+/=]{20,}' "$TMPFILE" 2>/dev/null; then
    DETECTED="Authorization token (Basic/Bearer)"
fi

# Long hex strings that look like secrets (32+ chars in quotes)
if [ -z "$DETECTED" ] && grep -qE '['"'"'"][0-9a-fA-F]{40,}['"'"'"]' "$TMPFILE" 2>/dev/null; then
    # gitコミットハッシュなどを除外（コメント内の場合）
    if ! grep -qE '(commit|sha|hash|checksum|fingerprint)\s*[:=]?\s*['"'"'"][0-9a-fA-F]{40,}' "$TMPFILE" 2>/dev/null; then
        DETECTED="Long hex string (potential secret)"
    fi
fi

if [ -n "$DETECTED" ]; then
    echo "" >&2
    echo "=== secret-scanner: WARNING ===" >&2
    echo "Potential secret detected: ${DETECTED}" >&2
    echo "File: ${FILE_PATH}" >&2
    echo "Use environment variables instead of hardcoding secrets." >&2
    echo "================================" >&2
    jq -n --arg reason "secret-scanner: Potential secret detected - ${DETECTED}. Use environment variables or a secrets manager instead of hardcoding secrets." \
        '{"decision":"block","reason":$reason}'
fi

exit 0
