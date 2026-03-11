#!/usr/bin/env bash
set -euo pipefail

# slack-notifier: PostToolUse(Bash) — notify on long-running commands or errors
# Sends webhook notifications to Slack/Discord

CONFIG_DIR="${HOME}/.claude/slack-notifier"
CONFIG_FILE="${CONFIG_DIR}/config.json"

# Ensure config directory exists
if [ ! -d "${CONFIG_DIR}" ]; then
    mkdir -p "${CONFIG_DIR}"
    chmod 700 "${CONFIG_DIR}"
fi

# Check if config exists
if [ ! -f "${CONFIG_FILE}" ]; then
    exit 0
fi

# Validate config file is not a symlink
if [ -L "${CONFIG_FILE}" ]; then
    exit 0
fi

# Read webhook URL from config
WEBHOOK_URL="$(jq -r '.webhook_url // empty' "${CONFIG_FILE}" 2>/dev/null || true)"
if [ -z "${WEBHOOK_URL}" ]; then
    exit 0
fi

# Validate webhook URL format (must start with https://)
if ! printf '%s' "${WEBHOOK_URL}" | grep -qE '^https://[a-zA-Z0-9._/-]+$'; then
    exit 0
fi

# Read thresholds from config
DURATION_THRESHOLD="$(jq -r '.duration_threshold_ms // "30000"' "${CONFIG_FILE}" 2>/dev/null || echo "30000")"
NOTIFY_ON_ERROR="$(jq -r '.notify_on_error // "true"' "${CONFIG_FILE}" 2>/dev/null || echo "true")"
NOTIFY_ON_LONG="$(jq -r '.notify_on_long_running // "true"' "${CONFIG_FILE}" 2>/dev/null || echo "true")"

# Validate thresholds are numeric
if ! printf '%s' "${DURATION_THRESHOLD}" | grep -qE '^[0-9]+$'; then
    DURATION_THRESHOLD="30000"
fi

# Read tool use input from stdin
INPUT="$(cat)"

TOOL_NAME="$(printf '%s' "${INPUT}" | jq -r '.tool_name // empty' 2>/dev/null || true)"
if [ "${TOOL_NAME}" != "Bash" ]; then
    exit 0
fi

# Extract relevant fields
EXIT_CODE="$(printf '%s' "${INPUT}" | jq -r '.tool_output.exit_code // "0"' 2>/dev/null || echo "0")"
DURATION_MS="$(printf '%s' "${INPUT}" | jq -r '.tool_output.duration_ms // "0"' 2>/dev/null || echo "0")"

# Validate numeric fields
if ! printf '%s' "${EXIT_CODE}" | grep -qE '^[0-9]+$'; then
    EXIT_CODE="0"
fi
if ! printf '%s' "${DURATION_MS}" | grep -qE '^[0-9]+$'; then
    DURATION_MS="0"
fi

# Extract command (sanitize for display)
RAW_CMD="$(printf '%s' "${INPUT}" | jq -r '.tool_input.command // "unknown"' 2>/dev/null || echo "unknown")"
# Sanitize: remove control chars, limit length, strip HTML-like tags
SAFE_CMD="$(printf '%s' "${RAW_CMD}" | tr -d '\000-\037\177' | sed 's/<[^>]*>//g' | cut -c1-100)"

SHOULD_NOTIFY="false"
NOTIFY_TYPE=""
EMOJI=""

# Check for error
if [ "${EXIT_CODE}" -ne 0 ] && [ "${NOTIFY_ON_ERROR}" = "true" ]; then
    SHOULD_NOTIFY="true"
    NOTIFY_TYPE="error"
    EMOJI="🚨"
fi

# Check for long-running command
if [ "${DURATION_MS}" -ge "${DURATION_THRESHOLD}" ] && [ "${NOTIFY_ON_LONG}" = "true" ]; then
    SHOULD_NOTIFY="true"
    NOTIFY_TYPE="long-running"
    EMOJI="⏱️"
fi

if [ "${SHOULD_NOTIFY}" != "true" ]; then
    exit 0
fi

# Get project context
PROJECT_DIR="$(pwd)"
PROJECT_NAME="$(basename "${PROJECT_DIR}" | tr -cd 'a-zA-Z0-9_.-')"
BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null | tr -cd 'a-zA-Z0-9_./-' || echo "unknown")"

# Calculate duration in seconds
DURATION_SEC="$(( DURATION_MS / 1000 ))"

# Build notification payload
if [ "${NOTIFY_TYPE}" = "error" ]; then
    MESSAGE="${EMOJI} Command failed (exit ${EXIT_CODE}) in *${PROJECT_NAME}* (${BRANCH})\n\`\`\`${SAFE_CMD}\`\`\`"
else
    MESSAGE="${EMOJI} Long-running command completed (${DURATION_SEC}s) in *${PROJECT_NAME}* (${BRANCH})\n\`\`\`${SAFE_CMD}\`\`\`"
fi

# Build JSON payload safely using jq
PAYLOAD="$(jq -n --arg text "${MESSAGE}" '{text: $text}')"

# Send webhook (fire and forget, don't block Claude)
curl -s -o /dev/null -m 5 \
    -H "Content-Type: application/json" \
    -d "${PAYLOAD}" \
    "${WEBHOOK_URL}" 2>/dev/null || true

# Log notification to file (reject symlinks)
TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
LOG_FILE="${CONFIG_DIR}/notification.log"
if [ ! -L "${LOG_FILE}" ]; then
    printf '%s\t%s\t%s\t%s\n' "${TIMESTAMP}" "${NOTIFY_TYPE}" "${PROJECT_NAME}" "${SAFE_CMD}" >> "${LOG_FILE}" 2>/dev/null || true
fi

# Limit log size (keep last 200 lines)
if [ -f "${LOG_FILE}" ] && [ ! -L "${LOG_FILE}" ]; then
    LINES="$(wc -l < "${LOG_FILE}" | tr -d ' ')"
    if [ "${LINES}" -gt 200 ]; then
        TEMP="$(mktemp)"
        tail -100 "${LOG_FILE}" > "${TEMP}" && mv "${TEMP}" "${LOG_FILE}"
    fi
fi

exit 0
