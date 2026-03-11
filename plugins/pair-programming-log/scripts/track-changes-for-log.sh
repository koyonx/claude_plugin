#!/usr/bin/env bash
set -euo pipefail

# pair-programming-log: PostToolUse(Write|Edit) — track file changes for active ADR

INPUT="$(cat)"

TOOL_NAME="$(printf '%s' "${INPUT}" | jq -r '.tool_name // empty' 2>/dev/null || true)"
if [ "${TOOL_NAME}" != "Write" ] && [ "${TOOL_NAME}" != "Edit" ]; then
    exit 0
fi

FILE_PATH="$(printf '%s' "${INPUT}" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)"
if [ -z "${FILE_PATH}" ]; then
    exit 0
fi

# Sanitize file path
SAFE_PATH="$(printf '%s' "${FILE_PATH}" | tr -cd 'a-zA-Z0-9_./-' | cut -c1-120)"

DATA_DIR="${HOME}/.claude/pair-programming-log"
PROJECT_DIR="$(pwd)"
PROJECT_ID="$(basename "${PROJECT_DIR}" | tr -cd 'a-zA-Z0-9_.-')"
PROJECT_LOG_DIR="${DATA_DIR}/${PROJECT_ID}"

# Check for active decision
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
    exit 0
fi

# Validate ADR path
RESOLVED="$(realpath "${ADR_FILE}" 2>/dev/null || true)"
case "${RESOLVED}" in
    "${PROJECT_LOG_DIR}"/*) ;;
    *) exit 0 ;;
esac

# Append file to the "Files Changed" section if not already listed
if ! grep -qF -- "${SAFE_PATH}" "${ADR_FILE}" 2>/dev/null; then
    printf '- %s (%s at %s)\n' "${SAFE_PATH}" "${TOOL_NAME}" "$(date -u +%H:%M:%S)" >> "${ADR_FILE}" 2>/dev/null || true
fi

exit 0
