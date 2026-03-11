#!/usr/bin/env bash
set -euo pipefail

# slack-notifier: Stop — notify when session ends
# Sends a summary notification when Claude session is completed

CONFIG_DIR="${HOME}/.claude/slack-notifier"
CONFIG_FILE="${CONFIG_DIR}/config.json"

# Check config
if [ ! -f "${CONFIG_FILE}" ] || [ -L "${CONFIG_FILE}" ]; then
    exit 0
fi

WEBHOOK_URL="$(jq -r '.webhook_url // empty' "${CONFIG_FILE}" 2>/dev/null || true)"
if [ -z "${WEBHOOK_URL}" ]; then
    exit 0
fi

# Validate webhook URL format
if ! printf '%s' "${WEBHOOK_URL}" | grep -qE '^https://[a-zA-Z0-9._/-]+$'; then
    exit 0
fi

NOTIFY_ON_SESSION_END="$(jq -r '.notify_on_session_end // "false"' "${CONFIG_FILE}" 2>/dev/null || echo "false")"
if [ "${NOTIFY_ON_SESSION_END}" != "true" ]; then
    exit 0
fi

# Get project context
PROJECT_DIR="$(pwd)"
PROJECT_NAME="$(basename "${PROJECT_DIR}" | tr -cd 'a-zA-Z0-9_.-')"
BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null | tr -cd 'a-zA-Z0-9_./-' || echo "unknown")"

# Count today's notifications from log
LOG_FILE="${CONFIG_DIR}/notification.log"
TODAY="$(date -u +%Y-%m-%d)"
ERROR_COUNT=0
LONG_COUNT=0
if [ -f "${LOG_FILE}" ] && [ ! -L "${LOG_FILE}" ]; then
    ERROR_COUNT="$(grep -c "^${TODAY}.*error" "${LOG_FILE}" 2>/dev/null || echo "0")"
    LONG_COUNT="$(grep -c "^${TODAY}.*long-running" "${LOG_FILE}" 2>/dev/null || echo "0")"
fi

# Validate counts
if ! printf '%s' "${ERROR_COUNT}" | grep -qE '^[0-9]+$'; then ERROR_COUNT="0"; fi
if ! printf '%s' "${LONG_COUNT}" | grep -qE '^[0-9]+$'; then LONG_COUNT="0"; fi

MESSAGE="📋 Session ended in *${PROJECT_NAME}* (${BRANCH})\nToday: ${ERROR_COUNT} error(s), ${LONG_COUNT} long-running notification(s)"

PAYLOAD="$(jq -n --arg text "${MESSAGE}" '{text: $text}')"

curl -s -o /dev/null -m 5 \
    -H "Content-Type: application/json" \
    -d "${PAYLOAD}" \
    "${WEBHOOK_URL}" 2>/dev/null || true

exit 0
