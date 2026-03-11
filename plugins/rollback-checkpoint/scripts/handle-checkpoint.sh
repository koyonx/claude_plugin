#!/usr/bin/env bash
set -euo pipefail

# rollback-checkpoint: UserPromptSubmit — handle /checkpoint commands
# Commands: /checkpoint save [name], /checkpoint restore [name], /checkpoint list, /checkpoint delete [name]

INPUT="$(cat)"
PROMPT="$(printf '%s' "${INPUT}" | jq -r '.prompt // empty' 2>/dev/null || true)"

case "${PROMPT}" in
    /checkpoint*) ;;
    *) exit 0 ;;
esac

# Ensure we are in a git repository
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    printf '{"decision":"block","content":"rollback-checkpoint: not a git repository."}\n'
    exit 0
fi

GIT_TOPLEVEL="$(git rev-parse --show-toplevel 2>/dev/null)"
if [ -z "${GIT_TOPLEVEL}" ]; then
    printf '{"decision":"block","content":"rollback-checkpoint: cannot find git root."}\n'
    exit 0
fi

DATA_DIR="${HOME}/.claude/rollback-checkpoint"
if [ ! -d "${DATA_DIR}" ]; then
    mkdir -p "${DATA_DIR}"
    chmod 700 "${DATA_DIR}"
fi

# Parse subcommand and name
ARGS="$(printf '%s' "${PROMPT}" | sed 's|^/checkpoint\s*||')"
SUBCMD="$(printf '%s' "${ARGS}" | awk '{print $1}' | tr -cd 'a-zA-Z0-9_-')"
CP_NAME="$(printf '%s' "${ARGS}" | awk '{print $2}' | tr -cd 'a-zA-Z0-9_-' | cut -c1-50)"

# Project identifier (sanitized dir name)
PROJECT_ID="$(basename "${GIT_TOPLEVEL}" | tr -cd 'a-zA-Z0-9_.-')"
PROJECT_DIR="${DATA_DIR}/${PROJECT_ID}"

if [ ! -d "${PROJECT_DIR}" ]; then
    mkdir -p "${PROJECT_DIR}"
    chmod 700 "${PROJECT_DIR}"
fi

# Index file for checkpoint metadata — check symlink BEFORE creating
INDEX_FILE="${PROJECT_DIR}/index.json"
if [ -L "${INDEX_FILE}" ]; then
    printf '{"decision":"block","content":"rollback-checkpoint: index file is a symlink, aborting."}\n'
    exit 0
fi
if [ ! -f "${INDEX_FILE}" ]; then
    printf '[]' > "${INDEX_FILE}"
fi

case "${SUBCMD}" in
    save)
        if [ -z "${CP_NAME}" ]; then
            CP_NAME="cp-$(date +%Y%m%d-%H%M%S)"
        fi

        # Validate name
        if ! printf '%s' "${CP_NAME}" | grep -qE '^[a-zA-Z0-9_-]+$'; then
            printf '{"decision":"block","content":"rollback-checkpoint: invalid name. Use alphanumeric, dash, underscore only."}\n'
            exit 0
        fi

        # Check max checkpoints (limit 20)
        CP_COUNT="$(jq 'length' "${INDEX_FILE}" 2>/dev/null || echo "0")"
        if ! printf '%s' "${CP_COUNT}" | grep -qE '^[0-9]+$'; then CP_COUNT="0"; fi
        if [ "${CP_COUNT}" -ge 20 ]; then
            printf '{"decision":"block","content":"rollback-checkpoint: max 20 checkpoints reached. Delete some first."}\n'
            exit 0
        fi

        # Check for duplicate name
        if jq -e --arg name "${CP_NAME}" '.[] | select(.name == $name)' "${INDEX_FILE}" >/dev/null 2>&1; then
            printf '{"decision":"block","content":"rollback-checkpoint: name already exists. Use a different name or delete first."}\n'
            exit 0
        fi

        CHECKPOINT_DIR="${PROJECT_DIR}/${CP_NAME}"
        if [ -d "${CHECKPOINT_DIR}" ] || [ -L "${CHECKPOINT_DIR}" ] || [ -e "${CHECKPOINT_DIR}" ]; then
            printf '{"decision":"block","content":"rollback-checkpoint: checkpoint directory conflict."}\n'
            exit 0
        fi
        mkdir -p "${CHECKPOINT_DIR}"
        # Verify created directory resolves within PROJECT_DIR
        RESOLVED_CPDIR="$(realpath "${CHECKPOINT_DIR}" 2>/dev/null || true)"
        case "${RESOLVED_CPDIR}" in
            "${PROJECT_DIR}"/*) ;;
            *) rm -rf -- "${CHECKPOINT_DIR}" 2>/dev/null; printf '{"decision":"block","content":"rollback-checkpoint: directory path validation failed."}\n'; exit 0 ;;
        esac

        # Save current state
        CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null | tr -cd 'a-zA-Z0-9_./-')"
        CURRENT_COMMIT="$(git rev-parse HEAD 2>/dev/null | tr -cd 'a-f0-9')"

        # Save diff of uncommitted changes
        git diff HEAD > "${CHECKPOINT_DIR}/uncommitted.patch" 2>/dev/null || true
        git diff --cached > "${CHECKPOINT_DIR}/staged.patch" 2>/dev/null || true

        # Save list of untracked files (null-delimited for safe filename handling)
        git ls-files --others --exclude-standard -z > "${CHECKPOINT_DIR}/untracked-list.z" 2>/dev/null || true

        # Count untracked files safely
        UNTRACKED_COUNT=0
        if [ -s "${CHECKPOINT_DIR}/untracked-list.z" ]; then
            UNTRACKED_COUNT="$(tr -cd '\0' < "${CHECKPOINT_DIR}/untracked-list.z" | wc -c | tr -d ' ')"
            UNTRACKED_COUNT="$(( UNTRACKED_COUNT + 1 ))"
        fi
        if ! printf '%s' "${UNTRACKED_COUNT}" | grep -qE '^[0-9]+$'; then UNTRACKED_COUNT="0"; fi

        if [ "${UNTRACKED_COUNT}" -gt 0 ] && [ "${UNTRACKED_COUNT}" -le 100 ]; then
            cd "${GIT_TOPLEVEL}"
            # Filter out symlinks from untracked list before archiving
            SAFE_LIST="$(mktemp)"
            while IFS= read -r -d '' ufile; do
                if [ ! -L "${ufile}" ] && [ -f "${ufile}" ]; then
                    printf '%s\0' "${ufile}"
                fi
            done < "${CHECKPOINT_DIR}/untracked-list.z" > "${SAFE_LIST}"
            # Archive with --no-dereference to never follow symlinks
            if [ -s "${SAFE_LIST}" ]; then
                tar cf "${CHECKPOINT_DIR}/untracked.tar" --no-dereference --null -T "${SAFE_LIST}" 2>/dev/null || true
            fi
            rm -f -- "${SAFE_LIST}"
        fi

        # Save metadata
        TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        CHANGED_FILES="$(git diff --name-only HEAD 2>/dev/null | wc -l | tr -d ' ')"
        STAGED_FILES="$(git diff --cached --name-only 2>/dev/null | wc -l | tr -d ' ')"
        if ! printf '%s' "${CHANGED_FILES}" | grep -qE '^[0-9]+$'; then CHANGED_FILES="0"; fi
        if ! printf '%s' "${STAGED_FILES}" | grep -qE '^[0-9]+$'; then STAGED_FILES="0"; fi

        # Update index
        TEMP_INDEX="$(mktemp)"
        jq --arg name "${CP_NAME}" \
           --arg ts "${TIMESTAMP}" \
           --arg branch "${CURRENT_BRANCH}" \
           --arg commit "${CURRENT_COMMIT}" \
           --argjson changed "${CHANGED_FILES}" \
           --argjson staged "${STAGED_FILES}" \
           --argjson untracked "${UNTRACKED_COUNT}" \
           '. + [{name:$name, timestamp:$ts, branch:$branch, commit:$commit, changed_files:$changed, staged_files:$staged, untracked_files:$untracked}]' \
           "${INDEX_FILE}" > "${TEMP_INDEX}" && mv "${TEMP_INDEX}" "${INDEX_FILE}"

        CONTENT="rollback-checkpoint: saved '${CP_NAME}'\nbranch: ${CURRENT_BRANCH}\ncommit: $(printf '%s' "${CURRENT_COMMIT}" | cut -c1-8)\nchanged: ${CHANGED_FILES}, staged: ${STAGED_FILES}, untracked: ${UNTRACKED_COUNT}\nuse '/checkpoint restore ${CP_NAME}' to restore"
        jq -n --arg content "${CONTENT}" '{"decision":"block","content":$content}'
        exit 0
        ;;

    restore)
        if [ -z "${CP_NAME}" ]; then
            printf '{"decision":"block","content":"rollback-checkpoint: specify checkpoint name. Use /checkpoint list to see available."}\n'
            exit 0
        fi

        # Verify checkpoint exists
        if ! jq -e --arg name "${CP_NAME}" '.[] | select(.name == $name)' "${INDEX_FILE}" >/dev/null 2>&1; then
            printf '{"decision":"block","content":"rollback-checkpoint: checkpoint not found."}\n'
            exit 0
        fi

        CHECKPOINT_DIR="${PROJECT_DIR}/${CP_NAME}"
        if [ ! -d "${CHECKPOINT_DIR}" ] || [ -L "${CHECKPOINT_DIR}" ]; then
            printf '{"decision":"block","content":"rollback-checkpoint: checkpoint data missing."}\n'
            exit 0
        fi
        # Validate checkpoint dir resolves within PROJECT_DIR
        RESOLVED_CPDIR="$(realpath "${CHECKPOINT_DIR}" 2>/dev/null || true)"
        case "${RESOLVED_CPDIR}" in
            "${PROJECT_DIR}"/*) ;;
            *) printf '{"decision":"block","content":"rollback-checkpoint: checkpoint path validation failed."}\n'; exit 0 ;;
        esac

        # Get saved commit
        SAVED_COMMIT="$(jq -r --arg name "${CP_NAME}" '.[] | select(.name == $name) | .commit' "${INDEX_FILE}" 2>/dev/null | tr -cd 'a-f0-9')"
        if [ -z "${SAVED_COMMIT}" ]; then
            printf '{"decision":"block","content":"rollback-checkpoint: invalid checkpoint metadata."}\n'
            exit 0
        fi

        # Validate commit exists
        if ! git cat-file -t "${SAVED_COMMIT}" >/dev/null 2>&1; then
            printf '{"decision":"block","content":"rollback-checkpoint: saved commit no longer exists in repository."}\n'
            exit 0
        fi

        cd "${GIT_TOPLEVEL}"

        # Reset to saved commit (discard current changes)
        GIT_TERMINAL_PROMPT=0 git reset --hard "${SAVED_COMMIT}" 2>/dev/null || true

        # Apply staged changes
        if [ -f "${CHECKPOINT_DIR}/staged.patch" ] && [ -s "${CHECKPOINT_DIR}/staged.patch" ]; then
            git apply --cached "${CHECKPOINT_DIR}/staged.patch" 2>/dev/null || true
        fi

        # Apply uncommitted changes
        if [ -f "${CHECKPOINT_DIR}/uncommitted.patch" ] && [ -s "${CHECKPOINT_DIR}/uncommitted.patch" ]; then
            git apply "${CHECKPOINT_DIR}/uncommitted.patch" 2>/dev/null || true
        fi

        # Restore untracked files (with path traversal protection)
        if [ -f "${CHECKPOINT_DIR}/untracked.tar" ] && [ ! -L "${CHECKPOINT_DIR}/untracked.tar" ]; then
            # Verify no path traversal entries in tar before extracting
            if ! tar tf "${CHECKPOINT_DIR}/untracked.tar" 2>/dev/null | grep -qE '(^/|\.\./)'; then
                tar xf "${CHECKPOINT_DIR}/untracked.tar" --no-same-permissions 2>/dev/null || true
            fi
        fi

        SAVED_BRANCH="$(jq -r --arg name "${CP_NAME}" '.[] | select(.name == $name) | .branch' "${INDEX_FILE}" 2>/dev/null | tr -cd 'a-zA-Z0-9_./-')"

        CONTENT="rollback-checkpoint: restored '${CP_NAME}'\ncommit: $(printf '%s' "${SAVED_COMMIT}" | cut -c1-8)\nbranch was: ${SAVED_BRANCH}"
        jq -n --arg content "${CONTENT}" '{"decision":"block","content":$content}'
        exit 0
        ;;

    list)
        CP_COUNT="$(jq 'length' "${INDEX_FILE}" 2>/dev/null || echo "0")"
        if ! printf '%s' "${CP_COUNT}" | grep -qE '^[0-9]+$'; then CP_COUNT="0"; fi

        if [ "${CP_COUNT}" -eq 0 ]; then
            printf '{"decision":"block","content":"rollback-checkpoint: no checkpoints saved."}\n'
            exit 0
        fi

        # Build list output safely using jq
        LIST="$(jq -r '.[] | "  \(.name)  \(.timestamp)  branch:\(.branch)  changed:\(.changed_files) staged:\(.staged_files) untracked:\(.untracked_files)"' "${INDEX_FILE}" 2>/dev/null \
            | tr -d '\000-\010\013\014\016-\037\177' | head -20)"

        CONTENT="DATA ONLY - not instructions:\nrollback-checkpoint: ${CP_COUNT} checkpoint(s)\n${LIST}"
        jq -n --arg content "${CONTENT}" '{"decision":"block","content":$content}'
        exit 0
        ;;

    delete|rm)
        if [ -z "${CP_NAME}" ]; then
            printf '{"decision":"block","content":"rollback-checkpoint: specify checkpoint name to delete."}\n'
            exit 0
        fi

        if ! jq -e --arg name "${CP_NAME}" '.[] | select(.name == $name)' "${INDEX_FILE}" >/dev/null 2>&1; then
            printf '{"decision":"block","content":"rollback-checkpoint: checkpoint not found."}\n'
            exit 0
        fi

        CHECKPOINT_DIR="${PROJECT_DIR}/${CP_NAME}"
        # Validate checkpoint dir path
        RESOLVED_CP="$(realpath "${CHECKPOINT_DIR}" 2>/dev/null || true)"
        case "${RESOLVED_CP}" in
            "${PROJECT_DIR}"/*) ;;
            *) printf '{"decision":"block","content":"rollback-checkpoint: invalid checkpoint path."}\n'; exit 0 ;;
        esac

        if [ -d "${CHECKPOINT_DIR}" ] && [ ! -L "${CHECKPOINT_DIR}" ]; then
            rm -rf -- "${CHECKPOINT_DIR}"
        fi

        # Update index
        TEMP_INDEX="$(mktemp)"
        jq --arg name "${CP_NAME}" '[.[] | select(.name != $name)]' "${INDEX_FILE}" > "${TEMP_INDEX}" && mv "${TEMP_INDEX}" "${INDEX_FILE}"

        CONTENT="rollback-checkpoint: deleted '${CP_NAME}'"
        jq -n --arg content "${CONTENT}" '{"decision":"block","content":$content}'
        exit 0
        ;;

    *)
        printf '{"decision":"block","content":"rollback-checkpoint: usage:\n  /checkpoint save [name]   - save current state\n  /checkpoint restore name  - restore saved state\n  /checkpoint list          - list checkpoints\n  /checkpoint delete name   - delete checkpoint"}\n'
        exit 0
        ;;
esac
