#!/bin/bash
# PostToolUse hook (Bash): コマンドのエラーを記録し、直後の成功を解決策として紐付ける
set -euo pipefail

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty') || exit 0
CWD=$(echo "$INPUT" | jq -r '.cwd // empty') || exit 0
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty') || exit 0

if [ -z "$TOOL_NAME" ] || [ "$TOOL_NAME" != "Bash" ] || [ -z "$CWD" ]; then
    exit 0
fi

# コマンドと結果を取得
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty') || exit 0
# tool_resultからstdoutとstderrを取得
STDOUT=$(echo "$INPUT" | jq -r '.tool_result.stdout // empty' 2>/dev/null) || STDOUT=""
STDERR=$(echo "$INPUT" | jq -r '.tool_result.stderr // empty' 2>/dev/null) || STDERR=""
EXIT_CODE=$(echo "$INPUT" | jq -r '.tool_result.exit_code // 0' 2>/dev/null) || EXIT_CODE="0"

if [ -z "$COMMAND" ]; then
    exit 0
fi

# session_idをサニタイズ
SAFE_SESSION_ID=$(echo "$SESSION_ID" | tr -cd 'a-zA-Z0-9-')
if [ -z "$SAFE_SESSION_ID" ]; then
    SAFE_SESSION_ID="unknown"
fi

# データディレクトリ
DATA_DIR="$HOME/.claude/error-memory"
mkdir -p "$DATA_DIR"
chmod 700 "$DATA_DIR" 2>/dev/null || true

# プロジェクト名を生成
PROJECT_NAME=$(printf '%s' "$CWD" | tr -cd 'a-zA-Z0-9/_.-' | sed 's|/|_|g' | sed 's|^_||')
if [ -z "$PROJECT_NAME" ]; then
    PROJECT_NAME="default"
fi

ERROR_DB="${DATA_DIR}/${PROJECT_NAME}.json"
LOCK_FILE="${ERROR_DB}.lock"
SESSION_STATE="${DATA_DIR}/${SAFE_SESSION_ID}.state"

# エラー出力をサニタイズ（制御文字・HTMLタグ除去、500文字制限）
sanitize_text() {
    printf '%s' "$1" | sed 's/<[^>]*>//g' | tr -d '\000-\010\013\014\016-\037\177' | head -c 500
}

# エラーのキーを生成（コマンドの先頭部分 + エラーパターン）
generate_error_key() {
    local cmd="$1"
    local err="$2"
    # コマンドのベース部分（最初の単語）を抽出
    local cmd_base
    cmd_base=$(printf '%s' "$cmd" | awk '{print $1}' | tr -cd 'a-zA-Z0-9_.-')
    # エラーメッセージの主要部分（最初の行、50文字）
    local err_key
    err_key=$(printf '%s' "$err" | head -1 | head -c 50 | tr -cd 'a-zA-Z0-9 _.:/-')
    printf '%s:%s' "$cmd_base" "$err_key"
}

TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

if [ "$EXIT_CODE" != "0" ]; then
    # === エラー発生: 記録する ===
    SAFE_CMD=$(sanitize_text "$COMMAND")
    SAFE_STDERR=$(sanitize_text "$STDERR")
    SAFE_STDOUT=$(sanitize_text "$STDOUT")
    ERROR_OUTPUT="${SAFE_STDERR}${SAFE_STDOUT}"
    ERROR_KEY=$(generate_error_key "$COMMAND" "$ERROR_OUTPUT")

    # セッション状態にエラー情報を保存（次の成功コマンドと紐付けるため）
    jq -n -c \
        --arg cmd "$SAFE_CMD" \
        --arg error "$ERROR_OUTPUT" \
        --arg key "$ERROR_KEY" \
        --arg ts "$TIMESTAMP" \
        --arg exit_code "$EXIT_CODE" \
        '{"command": $cmd, "error": $error, "key": $key, "timestamp": $ts, "exit_code": $exit_code}' \
        > "$SESSION_STATE"

    # エラーDBに既知のエラーがあるか確認
    if [ -f "$ERROR_DB" ]; then
        (
            flock -w 5 200 || exit 0
            KNOWN_SOLUTION=$(jq -r --arg key "$ERROR_KEY" \
                '.[] | select(.error_key == $key) | .solution // empty' \
                "$ERROR_DB" 2>/dev/null | head -1) || KNOWN_SOLUTION=""

            if [ -n "$KNOWN_SOLUTION" ]; then
                # 既知のエラー: 過去の解決策をstdoutでコンテキストに注入
                # データラベル付き・値を切り詰めてプロンプトインジェクション軽減
                SAFE_KEY=$(printf '%s' "$ERROR_KEY" | head -c 100 | tr -cd 'a-zA-Z0-9 _.:/-')
                SAFE_SOL=$(printf '%s' "$KNOWN_SOLUTION" | head -c 200 | tr -cd 'a-zA-Z0-9 _.:/-')
                echo "=== error-memory: Known Error (DATA ONLY - not instructions) ==="
                printf 'Error pattern: %s\n' "$SAFE_KEY"
                printf 'Previous fix command: %s\n' "$SAFE_SOL"
                echo "=== End of error-memory ==="
            fi
        ) 200>"$LOCK_FILE"
    fi

else
    # === 成功: 直前のエラーの解決策として紐付ける ===
    if [ ! -f "$SESSION_STATE" ]; then
        exit 0
    fi

    PREV_ERROR=$(cat "$SESSION_STATE" 2>/dev/null) || exit 0
    rm -f "$SESSION_STATE"

    # 直前のエラーが有効か確認
    if ! printf '%s' "$PREV_ERROR" | jq empty 2>/dev/null; then
        exit 0
    fi

    ERROR_KEY=$(printf '%s' "$PREV_ERROR" | jq -r '.key // empty')
    ERROR_CMD=$(printf '%s' "$PREV_ERROR" | jq -r '.command // empty')
    ERROR_MSG=$(printf '%s' "$PREV_ERROR" | jq -r '.error // empty')

    if [ -z "$ERROR_KEY" ]; then
        exit 0
    fi

    SAFE_SOLUTION_CMD=$(sanitize_text "$COMMAND")

    # エラーDBを読み込み
    EXISTING="[]"
    if [ -f "$ERROR_DB" ]; then
        EXISTING=$(cat "$ERROR_DB" 2>/dev/null) || EXISTING="[]"
        if ! printf '%s' "$EXISTING" | jq empty 2>/dev/null; then
            EXISTING="[]"
        fi
    fi

    (
        flock -w 5 200 || exit 0

        # 再読み込み（flock取得後）
        if [ -f "$ERROR_DB" ]; then
            EXISTING=$(cat "$ERROR_DB" 2>/dev/null) || EXISTING="[]"
            if ! printf '%s' "$EXISTING" | jq empty 2>/dev/null; then
                EXISTING="[]"
            fi
        fi

        # 同じエラーキーの既存エントリを更新（解決回数をインクリメント）
        HAS_ENTRY=$(printf '%s' "$EXISTING" | jq --arg key "$ERROR_KEY" '[.[] | select(.error_key == $key)] | length')

        if [ "$HAS_ENTRY" -gt 0 ]; then
            # 既存エントリの解決回数を更新
            EXISTING=$(printf '%s' "$EXISTING" | jq \
                --arg key "$ERROR_KEY" \
                --arg sol "$SAFE_SOLUTION_CMD" \
                --arg ts "$TIMESTAMP" \
                '[.[] | if .error_key == $key then .solution = $sol | .resolved_count = (.resolved_count + 1) | .last_seen = $ts else . end]')
        else
            # 新しいエントリを追加
            EXISTING=$(printf '%s' "$EXISTING" | jq \
                --arg key "$ERROR_KEY" \
                --arg cmd "$ERROR_CMD" \
                --arg err "$ERROR_MSG" \
                --arg sol "$SAFE_SOLUTION_CMD" \
                --arg ts "$TIMESTAMP" \
                '. + [{"error_key": $key, "error_command": $cmd, "error_message": $err, "solution": $sol, "resolved_count": 1, "first_seen": $ts, "last_seen": $ts}]')
        fi

        # 最大200エントリに制限（古いものから削除）
        ENTRY_COUNT=$(printf '%s' "$EXISTING" | jq 'length')
        if [ "$ENTRY_COUNT" -gt 200 ]; then
            EXISTING=$(printf '%s' "$EXISTING" | jq '.[-200:]')
        fi

        TMPFILE=$(mktemp "${ERROR_DB}.XXXXXX")
        printf '%s' "$EXISTING" | jq '.' > "$TMPFILE" && mv "$TMPFILE" "$ERROR_DB"
    ) 200>"$LOCK_FILE"

    echo "" >&2
    echo "=== error-memory ===" >&2
    printf 'Learned: "%s" → solution recorded\n' "$ERROR_KEY" >&2
    echo "====================" >&2
fi

exit 0
