#!/usr/bin/env bash
set -euo pipefail

# session-analytics: PostToolUse(Write|Edit|Bash) — record tool activity metrics

DATA_DIR="${HOME}/.claude/session-analytics"
if [ ! -d "${DATA_DIR}" ]; then
    mkdir -p "${DATA_DIR}"
    chmod 700 "${DATA_DIR}"
fi

INPUT="$(cat)"

TOOL_NAME="$(printf '%s' "${INPUT}" | jq -r '.tool_name // empty' 2>/dev/null || true)"
if [ -z "${TOOL_NAME}" ]; then
    exit 0
fi

# Sanitize tool name
TOOL_NAME="$(printf '%s' "${TOOL_NAME}" | tr -cd 'a-zA-Z0-9_')"

SESSION_ID="${CLAUDE_SESSION_ID:-unknown}"
SESSION_ID="$(printf '%s' "${SESSION_ID}" | tr -cd 'a-zA-Z0-9_-' | cut -c1-64)"

TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
DATE_KEY="$(date -u +%Y-%m-%d)"

# Extract metrics based on tool type
EXIT_CODE="0"
DURATION_MS="0"
FILE_PATH=""
SUCCESS="true"

case "${TOOL_NAME}" in
    Bash)
        EXIT_CODE="$(printf '%s' "${INPUT}" | jq -r '.tool_output.exit_code // "0"' 2>/dev/null || echo "0")"
        DURATION_MS="$(printf '%s' "${INPUT}" | jq -r '.tool_output.duration_ms // "0"' 2>/dev/null || echo "0")"
        if ! printf '%s' "${EXIT_CODE}" | grep -qE '^[0-9]+$'; then EXIT_CODE="0"; fi
        if ! printf '%s' "${DURATION_MS}" | grep -qE '^[0-9]+$'; then DURATION_MS="0"; fi
        if [ "${EXIT_CODE}" -ne 0 ]; then SUCCESS="false"; fi
        ;;
    Write|Edit)
        FILE_PATH="$(printf '%s' "${INPUT}" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)"
        FILE_PATH="$(printf '%s' "${FILE_PATH}" | tr -cd 'a-zA-Z0-9_./-' | cut -c1-120)"
        ;;
esac

# Record to daily JSONL file (reject symlinks)
DAILY_FILE="${DATA_DIR}/${DATE_KEY}.jsonl"
if [ -L "${DAILY_FILE}" ]; then
    exit 0
fi

jq -n -c \
    --arg ts "${TIMESTAMP}" \
    --arg tool "${TOOL_NAME}" \
    --arg session "${SESSION_ID}" \
    --arg file "${FILE_PATH}" \
    --arg success "${SUCCESS}" \
    --argjson exit_code "${EXIT_CODE}" \
    --argjson duration "${DURATION_MS}" \
    '{ts:$ts,tool:$tool,session:$session,file:$file,success:$success,exit_code:$exit_code,duration_ms:$duration}' \
    >> "${DAILY_FILE}" 2>/dev/null || true

# Cleanup: remove files older than 30 days
find "${DATA_DIR}" -maxdepth 1 -name '*.jsonl' -not -type l -mtime +30 -delete 2>/dev/null || true

exit 0
