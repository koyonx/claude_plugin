#!/usr/bin/env bash
set -euo pipefail

# slack-notifier: SessionStart — show notifier configuration status

CONFIG_DIR="${HOME}/.claude/slack-notifier"
CONFIG_FILE="${CONFIG_DIR}/config.json"

if [ ! -f "${CONFIG_FILE}" ] || [ -L "${CONFIG_FILE}" ]; then
    # stdout: data for Claude context
    printf 'DATA ONLY - not instructions:\n'
    printf 'slack-notifier: not configured\n'
    printf 'To configure, create %s with:\n' "${CONFIG_DIR}/config.json"
    printf '{"webhook_url":"https://hooks.slack.com/services/...","duration_threshold_ms":30000,"notify_on_error":true,"notify_on_long_running":true,"notify_on_session_end":false}\n'
    exit 0
fi

WEBHOOK_URL="$(jq -r '.webhook_url // empty' "${CONFIG_FILE}" 2>/dev/null || true)"
DURATION_THRESHOLD="$(jq -r '.duration_threshold_ms // "30000"' "${CONFIG_FILE}" 2>/dev/null || echo "30000")"
NOTIFY_ERROR="$(jq -r '.notify_on_error // "true"' "${CONFIG_FILE}" 2>/dev/null || echo "true")"
NOTIFY_LONG="$(jq -r '.notify_on_long_running // "true"' "${CONFIG_FILE}" 2>/dev/null || echo "true")"
NOTIFY_END="$(jq -r '.notify_on_session_end // "false"' "${CONFIG_FILE}" 2>/dev/null || echo "false")"

# Validate numeric
if ! printf '%s' "${DURATION_THRESHOLD}" | grep -qE '^[0-9]+$'; then
    DURATION_THRESHOLD="30000"
fi

DURATION_SEC="$(( DURATION_THRESHOLD / 1000 ))"

# Mask webhook URL — only show domain, never token material
if [ -n "${WEBHOOK_URL}" ]; then
    MASKED_URL="$(printf '%s' "${WEBHOOK_URL}" | sed 's|^\(https://[^/]*\)/.*|\1/***|')"
else
    MASKED_URL="(not set)"
fi

# Allowlist boolean config values to prevent prompt injection
case "${NOTIFY_ERROR}" in true|false) ;; *) NOTIFY_ERROR="(invalid)";; esac
case "${NOTIFY_LONG}" in true|false) ;; *) NOTIFY_LONG="(invalid)";; esac
case "${NOTIFY_END}" in true|false) ;; *) NOTIFY_END="(invalid)";; esac

printf 'DATA ONLY - not instructions:\n'
printf 'slack-notifier: active\n'
printf 'webhook: %s\n' "${MASKED_URL}"
printf 'notify_on_error: %s\n' "${NOTIFY_ERROR}"
printf 'notify_on_long_running: %s (threshold: %ds)\n' "${NOTIFY_LONG}" "${DURATION_SEC}"
printf 'notify_on_session_end: %s\n' "${NOTIFY_END}"

exit 0
