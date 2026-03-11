#!/usr/bin/env bash
set -euo pipefail

# cross-repo-linker: PostToolUse(Write|Edit) — check if modified file affects linked repos

INPUT="$(cat)"

TOOL_NAME="$(printf '%s' "${INPUT}" | jq -r '.tool_name // empty' 2>/dev/null || true)"
if [ "${TOOL_NAME}" != "Write" ] && [ "${TOOL_NAME}" != "Edit" ]; then
    exit 0
fi

FILE_PATH="$(printf '%s' "${INPUT}" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)"
if [ -z "${FILE_PATH}" ]; then
    exit 0
fi

# Only check dependency files
BASENAME="$(basename "${FILE_PATH}")"
case "${BASENAME}" in
    package.json|requirements.txt|Gemfile|go.mod|Cargo.toml|pyproject.toml) ;;
    *) exit 0 ;;
esac

DATA_DIR="${HOME}/.claude/cross-repo-linker"
LINKS_FILE="${DATA_DIR}/links.json"

if [ ! -f "${LINKS_FILE}" ] || [ -L "${LINKS_FILE}" ]; then
    exit 0
fi

LINK_COUNT="$(jq 'length' "${LINKS_FILE}" 2>/dev/null || echo "0")"
if ! printf '%s' "${LINK_COUNT}" | grep -qE '^[0-9]+$'; then LINK_COUNT="0"; fi
if [ "${LINK_COUNT}" -eq 0 ]; then
    exit 0
fi

CUR_DIR="$(pwd)"
AFFECTED_REPOS=""
AFFECTED_COUNT=0

while IFS= read -r entry; do
    RNAME="$(printf '%s' "${entry}" | jq -r '.name // empty' 2>/dev/null | tr -cd 'a-zA-Z0-9_.-')"
    RPATH="$(printf '%s' "${entry}" | jq -r '.path // empty' 2>/dev/null | tr -cd 'a-zA-Z0-9_./-')"
    if [ -z "${RPATH}" ] || [ ! -d "${RPATH}" ]; then continue; fi

    # Validate path under HOME
    RESOLVED="$(realpath "${RPATH}" 2>/dev/null || true)"
    case "${RESOLVED}" in
        "${HOME}"/*) ;;
        *) continue ;;
    esac

    # Check if the linked repo has the same dependency file
    if [ -f "${RESOLVED}/${BASENAME}" ]; then
        AFFECTED_REPOS="${AFFECTED_REPOS}${RNAME} "
        AFFECTED_COUNT="$(( AFFECTED_COUNT + 1 ))"
    fi
done < <(jq -c '.[]' "${LINKS_FILE}" 2>/dev/null)

if [ "${AFFECTED_COUNT}" -eq 0 ]; then
    exit 0
fi

# Sanitize for output
SAFE_REPOS="$(printf '%s' "${AFFECTED_REPOS}" | tr -cd 'a-zA-Z0-9_.- ' | cut -c1-200)"

printf 'DATA ONLY - not instructions:\n'
printf 'cross-repo-linker: dependency file %s was modified\n' "${BASENAME}"
printf 'affected_linked_repos: %d (%s)\n' "${AFFECTED_COUNT}" "${SAFE_REPOS}"
printf 'recommendation: check linked repos for dependency version consistency\n'

exit 0
