#!/usr/bin/env bash
set -euo pipefail

# pair-programming-log: Stop — finalize active ADR on session end

DATA_DIR="${HOME}/.claude/pair-programming-log"
PROJECT_DIR="$(pwd)"
PROJECT_ID="$(basename "${PROJECT_DIR}" | tr -cd 'a-zA-Z0-9_.-')"
PROJECT_LOG_DIR="${DATA_DIR}/${PROJECT_ID}"

ACTIVE_FILE="${PROJECT_LOG_DIR}/.active-decision"
if [ ! -f "${ACTIVE_FILE}" ] || [ -L "${ACTIVE_FILE}" ]; then
    exit 0
fi

DECISION_ID="$(cat "${ACTIVE_FILE}" | tr -cd 'a-zA-Z0-9_-' | cut -c1-30)"
if [ -z "${DECISION_ID}" ]; then
    exit 0
fi

ADR_FILE="${PROJECT_LOG_DIR}/adr-${DECISION_ID}.md"
if [ ! -f "${ADR_FILE}" ] || [ -L "${ADR_FILE}" ]; then
    rm -f -- "${ACTIVE_FILE}"
    exit 0
fi

# Validate ADR path
RESOLVED="$(realpath "${ADR_FILE}" 2>/dev/null || true)"
case "${RESOLVED}" in
    "${PROJECT_LOG_DIR}"/*) ;;
    *) rm -f -- "${ACTIVE_FILE}"; exit 0 ;;
esac

# Update status from "Proposed" to "Accepted"
if grep -q '^Proposed$' "${ADR_FILE}" 2>/dev/null; then
    TEMP="$(mktemp)"
    sed 's/^Proposed$/Accepted/' "${ADR_FILE}" > "${TEMP}" && mv "${TEMP}" "${ADR_FILE}"
fi

# Add session end timestamp
printf '\n## Session Ended\n\n%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "${ADR_FILE}" 2>/dev/null || true

# Update index entry status
INDEX_FILE="${PROJECT_LOG_DIR}/decisions.jsonl"
if [ -f "${INDEX_FILE}" ] && [ ! -L "${INDEX_FILE}" ]; then
    TEMP="$(mktemp)"
    jq --arg id "${DECISION_ID}" \
       'if .id == $id then .status = "accepted" else . end' \
       "${INDEX_FILE}" > "${TEMP}" && mv "${TEMP}" "${INDEX_FILE}" 2>/dev/null || true
fi

# Clear active decision
rm -f -- "${ACTIVE_FILE}"

# Show summary to user via stderr
FILE_COUNT="$(grep -c '^- ' "${ADR_FILE}" 2>/dev/null || echo "0")"
if ! printf '%s' "${FILE_COUNT}" | grep -qE '^[0-9]+$'; then FILE_COUNT="0"; fi
>&2 printf '[pair-programming-log] ADR-%s finalized (%s files tracked)\n' "${DECISION_ID}" "${FILE_COUNT}"

exit 0
