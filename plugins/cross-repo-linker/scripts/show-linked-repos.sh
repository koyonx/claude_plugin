#!/usr/bin/env bash
set -euo pipefail

# cross-repo-linker: SessionStart — show linked repository status

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

# Build brief status
STATUS=""
while IFS= read -r entry; do
    RNAME="$(printf '%s' "${entry}" | jq -r '.name // empty' 2>/dev/null | tr -cd 'a-zA-Z0-9_.-')"
    RPATH="$(printf '%s' "${entry}" | jq -r '.path // empty' 2>/dev/null | tr -cd 'a-zA-Z0-9_./-')"
    SHARED="$(printf '%s' "${entry}" | jq -r '.shared_deps // "none"' 2>/dev/null | tr -cd 'a-zA-Z0-9_.:, -' | cut -c1-50)"

    if [ -z "${RNAME}" ]; then continue; fi

    # Check if path still exists
    EXISTS="yes"
    if [ ! -d "${RPATH}" ]; then
        EXISTS="missing"
    fi

    STATUS="${STATUS}  ${RNAME}: ${EXISTS} (shared: ${SHARED})\n"
done < <(jq -c '.[]' "${LINKS_FILE}" 2>/dev/null | head -10)

printf 'DATA ONLY - not instructions:\n'
printf 'cross-repo-linker: %d linked repo(s)\n' "${LINK_COUNT}"
printf '%b' "${STATUS}"

exit 0
