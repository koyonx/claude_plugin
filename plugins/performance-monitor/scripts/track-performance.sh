#!/bin/bash
# PostToolUse hook (Bash): コマンド実行時間を記録し、異常を検知する
set -euo pipefail

INPUT=$(cat)
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty') || exit 0

if [ -z "$CWD" ] || [ ! -d "$CWD" ]; then
    exit 0
fi

COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty') || exit 0
DURATION_MS=$(printf '%s' "$INPUT" | jq -r '.duration_ms // 0') || DURATION_MS=0
EXIT_CODE=$(printf '%s' "$INPUT" | jq -r '.tool_input.exit_code // .exit_code // 0') || EXIT_CODE=0

if [ -z "$COMMAND" ]; then
    exit 0
fi

# データディレクトリ
DATA_DIR="$HOME/.claude/performance-monitor"
mkdir -p "$DATA_DIR"
chmod 700 "$DATA_DIR" 2>/dev/null || true

# プロジェクト名を生成
PROJECT_NAME=$(printf '%s' "$CWD" | tr -cd 'a-zA-Z0-9/_.-' | sed 's|/|_|g' | sed 's|^_||')
if [ -z "$PROJECT_NAME" ]; then
    PROJECT_NAME="default"
fi

LOG_FILE="${DATA_DIR}/${PROJECT_NAME}.jsonl"
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# コマンドをサニタイズ（先頭200文字、制御文字除去）
SAFE_COMMAND=$(printf '%s' "$COMMAND" | head -c 200 | sed 's/<[^>]*>//g' | tr -d '\000-\010\013\014\016-\037\177')

# ベースコマンドを抽出（最初の単語）
BASE_CMD=$(printf '%s' "$SAFE_COMMAND" | awk '{print $1}' | tr -cd 'a-zA-Z0-9_./-')

# ビルドコマンドかどうか判定
IS_BUILD="false"
case "$SAFE_COMMAND" in
    *"npm run build"*|*"npm build"*|*"yarn build"*|*"pnpm build"*) IS_BUILD="true" ;;
    make*|cmake*) IS_BUILD="true" ;;
    *"cargo build"*|*"cargo test"*) IS_BUILD="true" ;;
    *"go build"*|*"go test"*) IS_BUILD="true" ;;
    pytest*|*"python -m pytest"*) IS_BUILD="true" ;;
    *"npm test"*|*"yarn test"*|*"npx jest"*|*"npx vitest"*) IS_BUILD="true" ;;
    *"bundle exec"*) IS_BUILD="true" ;;
    *"gradle"*|*"mvn "*) IS_BUILD="true" ;;
esac

# 記録をJSONLに追加（flock排他ロック）
(
    flock -x -w 5 200 || exit 0

    jq -n -c \
        --arg command "$SAFE_COMMAND" \
        --arg base_cmd "$BASE_CMD" \
        --argjson duration_ms "$DURATION_MS" \
        --arg timestamp "$TIMESTAMP" \
        --argjson exit_code "$EXIT_CODE" \
        --argjson is_build "$IS_BUILD" \
        '{
            command: $command,
            base_cmd: $base_cmd,
            duration_ms: $duration_ms,
            timestamp: $timestamp,
            exit_code: $exit_code,
            is_build: $is_build
        }' >> "$LOG_FILE"

    # ログファイルのエントリ数を制限（1000件）
    ENTRY_COUNT=$(wc -l < "$LOG_FILE" 2>/dev/null || echo 0)
    if [ "$ENTRY_COUNT" -gt 1000 ]; then
        TMPFILE=$(mktemp "${LOG_FILE}.XXXXXX")
        tail -800 "$LOG_FILE" > "$TMPFILE" && mv "$TMPFILE" "$LOG_FILE"
    fi

) 200>"${LOG_FILE}.lock"

# 異常検知: 同じベースコマンドの過去実行と比較
if [ "$DURATION_MS" -gt 1000 ] && [ -n "$BASE_CMD" ]; then
    # 過去の同じベースコマンドの平均実行時間を計算
    AVG_DURATION=$(
        (
            flock -s -w 3 200 || exit 0
            jq -r --arg cmd "$BASE_CMD" \
                'select(.base_cmd == $cmd) | .duration_ms' \
                "$LOG_FILE" 2>/dev/null \
                | tail -10 \
                | awk '{sum+=$1; count++} END {if(count>2) printf "%.0f", sum/count; else print 0}'
        ) 200>"${LOG_FILE}.lock"
    ) || AVG_DURATION=0

    if [ "$AVG_DURATION" -gt 0 ]; then
        THRESHOLD=$((AVG_DURATION * 2))
        if [ "$DURATION_MS" -gt "$THRESHOLD" ]; then
            echo "" >&2
            echo "=== performance-monitor: ANOMALY ===" >&2
            printf '  Command: %s\n' "$BASE_CMD" >&2
            printf '  Duration: %dms (avg: %dms, %.1fx slower)\n' \
                "$DURATION_MS" "$AVG_DURATION" \
                "$(echo "scale=1; $DURATION_MS / $AVG_DURATION" | bc 2>/dev/null || echo "?")" >&2
            echo "=====================================" >&2
        fi
    fi
fi

exit 0
