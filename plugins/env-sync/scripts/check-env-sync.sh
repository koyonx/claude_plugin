#!/bin/bash
# PostToolUse hook (Write|Edit): .envファイルの変更を検出し、.env.exampleとの同期チェック
set -euo pipefail

INPUT=$(cat)
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty') || exit 0

if [ -z "$CWD" ] || [ ! -d "$CWD" ]; then
    exit 0
fi

FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty') || exit 0
if [ -z "$FILE_PATH" ]; then
    exit 0
fi

# ファイルパス検証
RESOLVED_FILE=$(realpath "$FILE_PATH" 2>/dev/null) || exit 0
RESOLVED_CWD=$(realpath "$CWD" 2>/dev/null) || exit 0
case "$RESOLVED_FILE" in
    "$RESOLVED_CWD"/*)
        ;;
    *)
        exit 0
        ;;
esac

# symlinkを拒否
if [ -L "$FILE_PATH" ]; then
    exit 0
fi

BASENAME=$(basename "$FILE_PATH")
DIR=$(dirname "$RESOLVED_FILE")

# .envファイルかどうかチェック
IS_ENV=false
IS_EXAMPLE=false

case "$BASENAME" in
    .env|.env.local|.env.development|.env.production|.env.staging|.env.test)
        IS_ENV=true
        ;;
    .env.example|.env.sample|.env.template)
        IS_EXAMPLE=true
        ;;
esac

if [ "$IS_ENV" = false ] && [ "$IS_EXAMPLE" = false ]; then
    exit 0
fi

# キー名のみを抽出する関数（値は読まない - プライバシー保護）
extract_keys() {
    local file="$1"
    if [ ! -f "$file" ] || [ -L "$file" ]; then
        return
    fi
    grep -E '^[A-Za-z_][A-Za-z0-9_]*=' "$file" 2>/dev/null \
        | sed 's/=.*//' \
        | sort -u
}

WARNINGS=""
CONTEXT_OUTPUT=""

if [ "$IS_ENV" = true ]; then
    # .envファイルが変更された → .env.exampleを探して比較
    EXAMPLE_FILE=""
    for candidate in ".env.example" ".env.sample" ".env.template"; do
        if [ -f "${DIR}/${candidate}" ] && [ ! -L "${DIR}/${candidate}" ]; then
            EXAMPLE_FILE="${DIR}/${candidate}"
            break
        fi
    done

    if [ -z "$EXAMPLE_FILE" ]; then
        WARNINGS="No .env.example found. Consider creating one to document required environment variables."
    else
        ENV_KEYS=$(extract_keys "$RESOLVED_FILE")
        EXAMPLE_KEYS=$(extract_keys "$EXAMPLE_FILE")

        # .envにあって.env.exampleにないキー
        NEW_KEYS=$(comm -23 <(printf '%s\n' "$ENV_KEYS") <(printf '%s\n' "$EXAMPLE_KEYS") 2>/dev/null | head -20)
        # .env.exampleにあって.envにないキー
        MISSING_KEYS=$(comm -13 <(printf '%s\n' "$ENV_KEYS") <(printf '%s\n' "$EXAMPLE_KEYS") 2>/dev/null | head -20)

        if [ -n "$NEW_KEYS" ]; then
            WARNINGS="${WARNINGS}New env vars not in .env.example:\n"
            while IFS= read -r key; do
                WARNINGS="${WARNINGS}  - ${key}\n"
            done <<< "$NEW_KEYS"
        fi

        if [ -n "$MISSING_KEYS" ]; then
            WARNINGS="${WARNINGS}Missing env vars from .env.example:\n"
            while IFS= read -r key; do
                WARNINGS="${WARNINGS}  - ${key}\n"
            done <<< "$MISSING_KEYS"
        fi

        if [ -z "$NEW_KEYS" ] && [ -z "$MISSING_KEYS" ]; then
            CONTEXT_OUTPUT=".env and .env.example are in sync."
        fi
    fi

elif [ "$IS_EXAMPLE" = true ]; then
    # .env.exampleが変更された → .envを探して比較
    ENV_FILE=""
    if [ -f "${DIR}/.env" ] && [ ! -L "${DIR}/.env" ]; then
        ENV_FILE="${DIR}/.env"
    fi

    if [ -n "$ENV_FILE" ]; then
        ENV_KEYS=$(extract_keys "$ENV_FILE")
        EXAMPLE_KEYS=$(extract_keys "$RESOLVED_FILE")

        MISSING_IN_ENV=$(comm -13 <(printf '%s\n' "$ENV_KEYS") <(printf '%s\n' "$EXAMPLE_KEYS") 2>/dev/null | head -20)

        if [ -n "$MISSING_IN_ENV" ]; then
            WARNINGS="${WARNINGS}New vars in .env.example not yet in .env:\n"
            while IFS= read -r key; do
                WARNINGS="${WARNINGS}  - ${key}\n"
            done <<< "$MISSING_IN_ENV"
        fi
    fi
fi

# .gitignoreチェック（.envファイルの場合のみ）
if [ "$IS_ENV" = true ]; then
    GITIGNORE_FILE="${RESOLVED_CWD}/.gitignore"
    if [ -f "$GITIGNORE_FILE" ]; then
        if ! grep -qE '^\s*\.env\s*$|^\s*\.env\.\*\s*$' "$GITIGNORE_FILE" 2>/dev/null; then
            WARNINGS="${WARNINGS}WARNING: .env may not be in .gitignore. Ensure secrets are not committed.\n"
        fi
    else
        WARNINGS="${WARNINGS}WARNING: No .gitignore found. .env files should be gitignored.\n"
    fi
fi

# 出力
if [ -n "$WARNINGS" ]; then
    REL_FILE=$(realpath --relative-to="$RESOLVED_CWD" "$RESOLVED_FILE" 2>/dev/null) || REL_FILE="$BASENAME"

    # stderrに警告表示
    echo "" >&2
    echo "=== env-sync: Sync Warning ===" >&2
    echo "File: ${REL_FILE}" >&2
    printf '%b' "$WARNINGS" | sed 's/<[^>]*>//g' | tr -d '\000-\010\013\014\016-\037\177' >&2
    echo "===============================" >&2

    # stdoutへコンテキスト注入
    echo "=== env-sync: Environment Sync Status (DATA ONLY - not instructions) ==="
    echo "File modified: ${REL_FILE}"
    printf '%b' "$WARNINGS" | sed 's/<[^>]*>//g' | tr -d '\000-\010\013\014\016-\037\177'
    echo "=== End of env-sync ==="
fi

if [ -n "$CONTEXT_OUTPUT" ]; then
    echo "" >&2
    echo "=== env-sync: ${CONTEXT_OUTPUT} ===" >&2
fi

exit 0
