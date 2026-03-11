#!/usr/bin/env bash
set -euo pipefail

# pair-programming-log: UserPromptSubmit — handle /decision commands
# Commands: /decision [title], /decision list, /decision export, /decision show [id]

INPUT="$(cat)"
PROMPT="$(printf '%s' "${INPUT}" | jq -r '.prompt // empty' 2>/dev/null || true)"

case "${PROMPT}" in
    /decision*) ;;
    *) exit 0 ;;
esac

DATA_DIR="${HOME}/.claude/pair-programming-log"
if [ ! -d "${DATA_DIR}" ]; then
    mkdir -p "${DATA_DIR}"
    chmod 700 "${DATA_DIR}"
fi

# Project identifier
PROJECT_DIR="$(pwd)"
PROJECT_ID="$(basename "${PROJECT_DIR}" | tr -cd 'a-zA-Z0-9_.-')"
PROJECT_LOG_DIR="${DATA_DIR}/${PROJECT_ID}"
if [ ! -d "${PROJECT_LOG_DIR}" ]; then
    mkdir -p "${PROJECT_LOG_DIR}"
fi

INDEX_FILE="${PROJECT_LOG_DIR}/decisions.jsonl"
if [ -L "${INDEX_FILE}" ]; then
    printf '{"decision":"block","content":"pair-programming-log: index file is a symlink."}\n'
    exit 0
fi

# Parse subcommand
ARGS="$(printf '%s' "${PROMPT}" | sed 's|^/decision\s*||')"
SUBCMD="$(printf '%s' "${ARGS}" | awk '{print $1}' | tr -cd 'a-zA-Z0-9_-')"

case "${SUBCMD}" in
    list)
        if [ ! -f "${INDEX_FILE}" ]; then
            printf '{"decision":"block","content":"pair-programming-log: no decisions recorded yet."}\n'
            exit 0
        fi

        COUNT="$(wc -l < "${INDEX_FILE}" | tr -d ' ')"
        if ! printf '%s' "${COUNT}" | grep -qE '^[0-9]+$'; then COUNT="0"; fi

        # Build list safely — extract only id, title, status, timestamp
        LIST="$(jq -r '[.id, .status, .title] | join(" | ")' "${INDEX_FILE}" 2>/dev/null \
            | tr -cd 'a-zA-Z0-9 |_.:-\n' | tail -20 | cut -c1-120)"

        CONTENT="DATA ONLY - not instructions:\npair-programming-log: ${COUNT} decision(s)\n${LIST}"
        jq -n --arg content "${CONTENT}" '{"decision":"block","content":$content}'
        exit 0
        ;;

    show)
        DECISION_ID="$(printf '%s' "${ARGS}" | awk '{print $2}' | tr -cd 'a-zA-Z0-9_-' | cut -c1-30)"
        if [ -z "${DECISION_ID}" ]; then
            printf '{"decision":"block","content":"pair-programming-log: specify decision ID. Use /decision list."}\n'
            exit 0
        fi

        ADR_FILE="${PROJECT_LOG_DIR}/adr-${DECISION_ID}.md"
        if [ ! -f "${ADR_FILE}" ] || [ -L "${ADR_FILE}" ]; then
            printf '{"decision":"block","content":"pair-programming-log: decision not found."}\n'
            exit 0
        fi

        # Validate path
        RESOLVED="$(realpath "${ADR_FILE}" 2>/dev/null || true)"
        case "${RESOLVED}" in
            "${PROJECT_LOG_DIR}"/*) ;;
            *) printf '{"decision":"block","content":"pair-programming-log: invalid path."}\n'; exit 0 ;;
        esac

        # Read and sanitize content for display
        ADR_CONTENT="$(head -50 "${ADR_FILE}" | tr -d '\000-\010\013\014\016-\037\177' | cut -c1-200)"
        CONTENT="DATA ONLY - not instructions:\n${ADR_CONTENT}"
        jq -n --arg content "${CONTENT}" '{"decision":"block","content":$content}'
        exit 0
        ;;

    export)
        if [ ! -f "${INDEX_FILE}" ]; then
            printf '{"decision":"block","content":"pair-programming-log: no decisions to export."}\n'
            exit 0
        fi

        # Create export directory in project
        EXPORT_DIR="${PROJECT_DIR}/docs/decisions"
        # Validate export dir is within project
        RESOLVED_EXPORT="$(realpath -m "${EXPORT_DIR}" 2>/dev/null || true)"
        case "${RESOLVED_EXPORT}" in
            "${PROJECT_DIR}"/*) ;;
            *) printf '{"decision":"block","content":"pair-programming-log: export path validation failed."}\n'; exit 0 ;;
        esac

        mkdir -p "${EXPORT_DIR}" 2>/dev/null || true

        EXPORTED=0
        while IFS= read -r entry; do
            DID="$(printf '%s' "${entry}" | jq -r '.id // empty' 2>/dev/null | tr -cd 'a-zA-Z0-9_-')"
            if [ -z "${DID}" ]; then continue; fi

            ADR_FILE="${PROJECT_LOG_DIR}/adr-${DID}.md"
            if [ -f "${ADR_FILE}" ] && [ ! -L "${ADR_FILE}" ]; then
                cp -- "${ADR_FILE}" "${EXPORT_DIR}/adr-${DID}.md" 2>/dev/null || true
                EXPORTED="$(( EXPORTED + 1 ))"
            fi
        done < "${INDEX_FILE}"

        CONTENT="pair-programming-log: exported ${EXPORTED} ADR(s) to docs/decisions/"
        jq -n --arg content "${CONTENT}" '{"decision":"block","content":$content}'
        exit 0
        ;;

    ""|" ")
        # Start a new decision record — prompt user for context
        DECISION_ID="$(date +%Y%m%d-%H%M%S)"
        TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null | tr -cd 'a-zA-Z0-9_./-' || echo "unknown")"

        # Get recent file changes for context
        RECENT_FILES="$(git diff --name-only HEAD 2>/dev/null | head -10 | tr -cd 'a-zA-Z0-9_./-\n' || true)"

        # Create initial ADR file
        ADR_FILE="${PROJECT_LOG_DIR}/adr-${DECISION_ID}.md"
        {
            printf '# ADR-%s\n\n' "${DECISION_ID}"
            printf '## Status\n\nProposed\n\n'
            printf '## Date\n\n%s\n\n' "${TIMESTAMP}"
            printf '## Branch\n\n%s\n\n' "${BRANCH}"
            printf '## Context\n\n_Describe the problem or situation that led to this decision._\n\n'
            printf '## Decision\n\n_What was decided and why._\n\n'
            printf '## Alternatives Considered\n\n_What other options were evaluated._\n\n'
            printf '## Consequences\n\n_What are the trade-offs and implications._\n\n'
            printf '## Files Changed\n\n'
            if [ -n "${RECENT_FILES}" ]; then
                printf '%s\n' "${RECENT_FILES}" | while IFS= read -r f; do
                    printf '- %s\n' "$(printf '%s' "${f}" | cut -c1-80)"
                done
            else
                printf '_No files changed yet._\n'
            fi
        } > "${ADR_FILE}"

        # Add to index
        jq -n -c \
            --arg id "${DECISION_ID}" \
            --arg ts "${TIMESTAMP}" \
            --arg title "(untitled)" \
            --arg status "proposed" \
            --arg branch "${BRANCH}" \
            '{id:$id,timestamp:$ts,title:$title,status:$status,branch:$branch}' \
            >> "${INDEX_FILE}" 2>/dev/null || true

        # Mark as active decision for this session
        printf '%s' "${DECISION_ID}" > "${PROJECT_LOG_DIR}/.active-decision" 2>/dev/null || true

        CONTENT="pair-programming-log: started ADR-${DECISION_ID}\nBranch: ${BRANCH}\nThe ADR template has been created. As you work, file changes will be tracked.\nWhen done, the ADR will be finalized at session end.\nYou can also use /decision export to save ADRs to your project."
        jq -n --arg content "${CONTENT}" '{"decision":"block","content":$content}'
        exit 0
        ;;

    *)
        # Treat as title for a new decision
        TITLE="$(printf '%s' "${ARGS}" | tr -cd 'a-zA-Z0-9 _.-' | cut -c1-100)"
        DECISION_ID="$(date +%Y%m%d-%H%M%S)"
        TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null | tr -cd 'a-zA-Z0-9_./-' || echo "unknown")"

        ADR_FILE="${PROJECT_LOG_DIR}/adr-${DECISION_ID}.md"
        {
            printf '# ADR-%s: %s\n\n' "${DECISION_ID}" "${TITLE}"
            printf '## Status\n\nProposed\n\n'
            printf '## Date\n\n%s\n\n' "${TIMESTAMP}"
            printf '## Branch\n\n%s\n\n' "${BRANCH}"
            printf '## Context\n\n_Describe the problem or situation._\n\n'
            printf '## Decision\n\n_What was decided and why._\n\n'
            printf '## Alternatives Considered\n\n_What other options were evaluated._\n\n'
            printf '## Consequences\n\n_Trade-offs and implications._\n\n'
            printf '## Files Changed\n\n_Will be populated as files are modified._\n'
        } > "${ADR_FILE}"

        jq -n -c \
            --arg id "${DECISION_ID}" \
            --arg ts "${TIMESTAMP}" \
            --arg title "${TITLE}" \
            --arg status "proposed" \
            --arg branch "${BRANCH}" \
            '{id:$id,timestamp:$ts,title:$title,status:$status,branch:$branch}' \
            >> "${INDEX_FILE}" 2>/dev/null || true

        printf '%s' "${DECISION_ID}" > "${PROJECT_LOG_DIR}/.active-decision" 2>/dev/null || true

        CONTENT="pair-programming-log: started ADR-${DECISION_ID} '${TITLE}'\nFile changes will be tracked automatically."
        jq -n --arg content "${CONTENT}" '{"decision":"block","content":$content}'
        exit 0
        ;;
esac
