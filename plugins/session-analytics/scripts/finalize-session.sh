#!/usr/bin/env bash
set -euo pipefail

# session-analytics: Stop — compute and store session summary

DATA_DIR="${HOME}/.claude/session-analytics"
if [ ! -d "${DATA_DIR}" ]; then
    exit 0
fi

SESSION_ID="${CLAUDE_SESSION_ID:-unknown}"
SESSION_ID="$(printf '%s' "${SESSION_ID}" | tr -cd 'a-zA-Z0-9_-' | cut -c1-64)"
DATE_KEY="$(date -u +%Y-%m-%d)"
DAILY_FILE="${DATA_DIR}/${DATE_KEY}.jsonl"

if [ ! -f "${DAILY_FILE}" ] || [ -L "${DAILY_FILE}" ]; then
    exit 0
fi

# Compute session metrics using jq
SUMMARY="$(jq -s --arg sid "${SESSION_ID}" '
    [.[] | select(.session == $sid)] |
    {
        session: $sid,
        total_actions: length,
        writes: [.[] | select(.tool == "Write")] | length,
        edits: [.[] | select(.tool == "Edit")] | length,
        commands: [.[] | select(.tool == "Bash")] | length,
        successes: [.[] | select(.success == "true")] | length,
        failures: [.[] | select(.success == "false")] | length,
        unique_files: ([.[] | select(.file != "") | .file] | unique | length),
        total_cmd_duration_ms: ([.[] | select(.tool == "Bash") | .duration_ms] | add // 0)
    } |
    .success_rate = (if .total_actions > 0 then ((.successes / .total_actions * 100) | floor) else 0 end) |
    .avg_cmd_duration_ms = (if .commands > 0 then ((.total_cmd_duration_ms / .commands) | floor) else 0 end)
' "${DAILY_FILE}" 2>/dev/null || true)"

if [ -z "${SUMMARY}" ]; then
    exit 0
fi

# Store session summary
SUMMARY_FILE="${DATA_DIR}/summaries.jsonl"
if [ -L "${SUMMARY_FILE}" ]; then
    exit 0
fi

TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
printf '%s' "${SUMMARY}" | jq -c --arg ts "${TIMESTAMP}" --arg date "${DATE_KEY}" '. + {date: $date, ended_at: $ts}' \
    >> "${SUMMARY_FILE}" 2>/dev/null || true

# Limit summary file size
if [ -f "${SUMMARY_FILE}" ]; then
    LINES="$(wc -l < "${SUMMARY_FILE}" | tr -d ' ')"
    if [ "${LINES}" -gt 500 ]; then
        TEMP="$(mktemp)"
        tail -300 "${SUMMARY_FILE}" > "${TEMP}" && mv "${TEMP}" "${SUMMARY_FILE}"
    fi
fi

# Print session summary to stderr (visible to user)
TOTAL="$(printf '%s' "${SUMMARY}" | jq -r '.total_actions // 0')"
WRITES="$(printf '%s' "${SUMMARY}" | jq -r '.writes // 0')"
EDITS="$(printf '%s' "${SUMMARY}" | jq -r '.edits // 0')"
CMDS="$(printf '%s' "${SUMMARY}" | jq -r '.commands // 0')"
RATE="$(printf '%s' "${SUMMARY}" | jq -r '.success_rate // 0')"
FILES="$(printf '%s' "${SUMMARY}" | jq -r '.unique_files // 0')"

>&2 printf '[session-analytics] Session summary: %s actions (%s writes, %s edits, %s commands), %s files, %s%% success rate\n' \
    "${TOTAL}" "${WRITES}" "${EDITS}" "${CMDS}" "${FILES}" "${RATE}"

exit 0
