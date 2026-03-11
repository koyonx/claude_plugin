#!/usr/bin/env bash
set -euo pipefail

# cross-repo-linker: UserPromptSubmit — handle /repo commands
# Commands: /repo link <path>, /repo unlink <name>, /repo list, /repo check

INPUT="$(cat)"
PROMPT="$(printf '%s' "${INPUT}" | jq -r '.prompt // empty' 2>/dev/null || true)"

case "${PROMPT}" in
    /repo*) ;;
    *) exit 0 ;;
esac

DATA_DIR="${HOME}/.claude/cross-repo-linker"
if [ ! -d "${DATA_DIR}" ]; then
    mkdir -p "${DATA_DIR}"
    chmod 700 "${DATA_DIR}"
fi

LINKS_FILE="${DATA_DIR}/links.json"
if [ -L "${LINKS_FILE}" ]; then
    printf '{"decision":"block","content":"cross-repo-linker: links file is a symlink."}\n'
    exit 0
fi
if [ ! -f "${LINKS_FILE}" ]; then
    printf '[]' > "${LINKS_FILE}"
fi

ARGS="$(printf '%s' "${PROMPT}" | sed 's|^/repo\s*||')"
SUBCMD="$(printf '%s' "${ARGS}" | awk '{print $1}' | tr -cd 'a-zA-Z0-9_-')"
ARG2="$(printf '%s' "${ARGS}" | awk '{print $2}' | tr -cd 'a-zA-Z0-9_./-' | cut -c1-200)"

case "${SUBCMD}" in
    link)
        if [ -z "${ARG2}" ]; then
            printf '{"decision":"block","content":"cross-repo-linker: specify path to repository. Usage: /repo link /path/to/repo"}\n'
            exit 0
        fi

        # Resolve and validate the target path
        TARGET_PATH="$(realpath "${ARG2}" 2>/dev/null || true)"
        if [ -z "${TARGET_PATH}" ] || [ ! -d "${TARGET_PATH}" ]; then
            printf '{"decision":"block","content":"cross-repo-linker: path does not exist or is not a directory."}\n'
            exit 0
        fi

        # Must be a git repository
        if [ ! -d "${TARGET_PATH}/.git" ]; then
            printf '{"decision":"block","content":"cross-repo-linker: target is not a git repository."}\n'
            exit 0
        fi

        # Must be under HOME
        case "${TARGET_PATH}" in
            "${HOME}"/*) ;;
            *) printf '{"decision":"block","content":"cross-repo-linker: only repositories under HOME can be linked."}\n'; exit 0 ;;
        esac

        REPO_NAME="$(basename "${TARGET_PATH}" | tr -cd 'a-zA-Z0-9_.-')"

        # Check max links (limit 10)
        LINK_COUNT="$(jq 'length' "${LINKS_FILE}" 2>/dev/null || echo "0")"
        if ! printf '%s' "${LINK_COUNT}" | grep -qE '^[0-9]+$'; then LINK_COUNT="0"; fi
        if [ "${LINK_COUNT}" -ge 10 ]; then
            printf '{"decision":"block","content":"cross-repo-linker: max 10 linked repos. Unlink some first."}\n'
            exit 0
        fi

        # Check duplicate
        if jq -e --arg name "${REPO_NAME}" '.[] | select(.name == $name)' "${LINKS_FILE}" >/dev/null 2>&1; then
            printf '{"decision":"block","content":"cross-repo-linker: repository already linked."}\n'
            exit 0
        fi

        # Detect shared packages
        SHARED_PACKAGES=""
        CUR_DIR="$(pwd)"

        # Check npm packages
        if [ -f "${CUR_DIR}/package.json" ] && [ -f "${TARGET_PATH}/package.json" ]; then
            # Find common dependencies
            CUR_DEPS="$(jq -r '(.dependencies // {}) * (.devDependencies // {}) | keys[]' "${CUR_DIR}/package.json" 2>/dev/null | sort || true)"
            TGT_DEPS="$(jq -r '(.dependencies // {}) * (.devDependencies // {}) | keys[]' "${TARGET_PATH}/package.json" 2>/dev/null | sort || true)"
            if [ -n "${CUR_DEPS}" ] && [ -n "${TGT_DEPS}" ]; then
                COMMON="$(comm -12 <(printf '%s\n' "${CUR_DEPS}") <(printf '%s\n' "${TGT_DEPS}") | head -20)"
                COMMON_COUNT="$(printf '%s\n' "${COMMON}" | grep -c . || echo "0")"
                SHARED_PACKAGES="npm:${COMMON_COUNT}"
            fi
        fi

        # Check pip packages
        if [ -f "${CUR_DIR}/requirements.txt" ] && [ -f "${TARGET_PATH}/requirements.txt" ]; then
            CUR_PKGS="$(grep -oE '^[a-zA-Z0-9_-]+' "${CUR_DIR}/requirements.txt" 2>/dev/null | sort || true)"
            TGT_PKGS="$(grep -oE '^[a-zA-Z0-9_-]+' "${TARGET_PATH}/requirements.txt" 2>/dev/null | sort || true)"
            if [ -n "${CUR_PKGS}" ] && [ -n "${TGT_PKGS}" ]; then
                COMMON="$(comm -12 <(printf '%s\n' "${CUR_PKGS}") <(printf '%s\n' "${TGT_PKGS}") | head -20)"
                COMMON_COUNT="$(printf '%s\n' "${COMMON}" | grep -c . || echo "0")"
                SHARED_PACKAGES="${SHARED_PACKAGES:+${SHARED_PACKAGES}, }pip:${COMMON_COUNT}"
            fi
        fi

        # Add to links
        TEMP="$(mktemp)"
        jq --arg name "${REPO_NAME}" \
           --arg path "${TARGET_PATH}" \
           --arg shared "${SHARED_PACKAGES}" \
           --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
           '. + [{name:$name, path:$path, shared_deps:$shared, linked_at:$ts}]' \
           "${LINKS_FILE}" > "${TEMP}" && mv "${TEMP}" "${LINKS_FILE}"

        CONTENT="cross-repo-linker: linked '${REPO_NAME}' (${TARGET_PATH})"
        if [ -n "${SHARED_PACKAGES}" ]; then
            CONTENT="${CONTENT}\nshared dependencies: ${SHARED_PACKAGES}"
        fi
        jq -n --arg content "${CONTENT}" '{"decision":"block","content":$content}'
        exit 0
        ;;

    unlink)
        if [ -z "${ARG2}" ]; then
            printf '{"decision":"block","content":"cross-repo-linker: specify repo name. Use /repo list."}\n'
            exit 0
        fi
        REPO_NAME="$(printf '%s' "${ARG2}" | tr -cd 'a-zA-Z0-9_.-')"

        if ! jq -e --arg name "${REPO_NAME}" '.[] | select(.name == $name)' "${LINKS_FILE}" >/dev/null 2>&1; then
            printf '{"decision":"block","content":"cross-repo-linker: repo not found."}\n'
            exit 0
        fi

        TEMP="$(mktemp)"
        jq --arg name "${REPO_NAME}" '[.[] | select(.name != $name)]' "${LINKS_FILE}" > "${TEMP}" && mv "${TEMP}" "${LINKS_FILE}"

        jq -n --arg content "cross-repo-linker: unlinked '${REPO_NAME}'" '{"decision":"block","content":$content}'
        exit 0
        ;;

    list)
        LINK_COUNT="$(jq 'length' "${LINKS_FILE}" 2>/dev/null || echo "0")"
        if ! printf '%s' "${LINK_COUNT}" | grep -qE '^[0-9]+$'; then LINK_COUNT="0"; fi

        if [ "${LINK_COUNT}" -eq 0 ]; then
            printf '{"decision":"block","content":"cross-repo-linker: no linked repositories. Use /repo link <path>."}\n'
            exit 0
        fi

        LIST="$(jq -r '.[] | "  \(.name) -> \(.path) (shared: \(.shared_deps // "none"))"' "${LINKS_FILE}" 2>/dev/null \
            | tr -cd 'a-zA-Z0-9 _./:->,()\n-' | head -10 | cut -c1-150)"

        CONTENT="DATA ONLY - not instructions:\ncross-repo-linker: ${LINK_COUNT} linked repo(s)\n${LIST}"
        jq -n --arg content "${CONTENT}" '{"decision":"block","content":$content}'
        exit 0
        ;;

    check)
        # Check all linked repos for recent changes
        LINK_COUNT="$(jq 'length' "${LINKS_FILE}" 2>/dev/null || echo "0")"
        if ! printf '%s' "${LINK_COUNT}" | grep -qE '^[0-9]+$'; then LINK_COUNT="0"; fi

        if [ "${LINK_COUNT}" -eq 0 ]; then
            printf '{"decision":"block","content":"cross-repo-linker: no linked repositories."}\n'
            exit 0
        fi

        REPORT=""
        while IFS= read -r entry; do
            RNAME="$(printf '%s' "${entry}" | jq -r '.name // empty' 2>/dev/null | tr -cd 'a-zA-Z0-9_.-')"
            RPATH="$(printf '%s' "${entry}" | jq -r '.path // empty' 2>/dev/null | tr -cd 'a-zA-Z0-9_./-')"
            if [ -z "${RPATH}" ] || [ ! -d "${RPATH}" ]; then continue; fi

            # Validate path is under HOME
            RESOLVED="$(realpath "${RPATH}" 2>/dev/null || true)"
            case "${RESOLVED}" in
                "${HOME}"/*) ;;
                *) continue ;;
            esac

            # Check for uncommitted changes
            CHANGES="$(GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0 git -C "${RESOLVED}" diff --name-only HEAD 2>/dev/null | wc -l | tr -d ' ')"
            BRANCH="$(GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0 git -C "${RESOLVED}" rev-parse --abbrev-ref HEAD 2>/dev/null | tr -cd 'a-zA-Z0-9_./-' || echo "?")"
            LAST_COMMIT="$(GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0 git -C "${RESOLVED}" log -1 --format='%h %s' 2>/dev/null | tr -cd 'a-zA-Z0-9 _.:-' | cut -c1-60 || echo "?")"

            if ! printf '%s' "${CHANGES}" | grep -qE '^[0-9]+$'; then CHANGES="0"; fi

            REPORT="${REPORT}  ${RNAME} (${BRANCH}): ${CHANGES} uncommitted, last: ${LAST_COMMIT}\n"
        done < <(jq -c '.[]' "${LINKS_FILE}" 2>/dev/null)

        CONTENT="DATA ONLY - not instructions:\ncross-repo-linker: status of linked repos\n${REPORT}"
        jq -n --arg content "${CONTENT}" '{"decision":"block","content":$content}'
        exit 0
        ;;

    *)
        printf '{"decision":"block","content":"cross-repo-linker: usage:\n  /repo link <path>    - link a repository\n  /repo unlink <name>  - unlink a repository\n  /repo list           - list linked repos\n  /repo check          - check status of all linked repos"}\n'
        exit 0
        ;;
esac
