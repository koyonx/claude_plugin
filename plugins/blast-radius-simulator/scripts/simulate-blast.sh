#!/usr/bin/env bash
set -euo pipefail

# blast-radius-simulator: PreToolUse(Bash) — simulate impact of destructive commands
# Shows file/line counts that would be affected before execution

INPUT="$(cat)"

TOOL_NAME="$(printf '%s' "${INPUT}" | jq -r '.tool_name // empty' 2>/dev/null || true)"
if [ "${TOOL_NAME}" != "Bash" ]; then
    exit 0
fi

COMMAND="$(printf '%s' "${INPUT}" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
if [ -z "${COMMAND}" ]; then
    exit 0
fi

# Detect destructive patterns
IS_DESTRUCTIVE="false"
DESTRUCTIVE_TYPE=""
IMPACT_MSG=""

# Pattern matching for destructive commands
# rm / rm -rf
if printf '%s' "${COMMAND}" | grep -qE '(^|\s|;|&&|\|)\s*rm\s+'; then
    IS_DESTRUCTIVE="true"
    DESTRUCTIVE_TYPE="rm"
fi

# git reset --hard
if printf '%s' "${COMMAND}" | grep -qE 'git\s+reset\s+--hard'; then
    IS_DESTRUCTIVE="true"
    DESTRUCTIVE_TYPE="git-reset-hard"
fi

# git push --force / -f
if printf '%s' "${COMMAND}" | grep -qE 'git\s+push\s+.*(-f|--force)'; then
    IS_DESTRUCTIVE="true"
    DESTRUCTIVE_TYPE="git-push-force"
fi

# git clean -f
if printf '%s' "${COMMAND}" | grep -qE 'git\s+clean\s+.*-[a-zA-Z]*f'; then
    IS_DESTRUCTIVE="true"
    DESTRUCTIVE_TYPE="git-clean"
fi

# git checkout -- . / git restore .
if printf '%s' "${COMMAND}" | grep -qE 'git\s+(checkout\s+--\s*\.|restore\s+\.)'; then
    IS_DESTRUCTIVE="true"
    DESTRUCTIVE_TYPE="git-discard"
fi

# DROP TABLE / DROP DATABASE
if printf '%s' "${COMMAND}" | grep -qiE 'DROP\s+(TABLE|DATABASE|INDEX|SCHEMA)'; then
    IS_DESTRUCTIVE="true"
    DESTRUCTIVE_TYPE="sql-drop"
fi

# TRUNCATE TABLE
if printf '%s' "${COMMAND}" | grep -qiE 'TRUNCATE\s+TABLE'; then
    IS_DESTRUCTIVE="true"
    DESTRUCTIVE_TYPE="sql-truncate"
fi

# DELETE FROM without WHERE
if printf '%s' "${COMMAND}" | grep -qiE 'DELETE\s+FROM\s+\w+\s*$' && ! printf '%s' "${COMMAND}" | grep -qiE 'WHERE'; then
    IS_DESTRUCTIVE="true"
    DESTRUCTIVE_TYPE="sql-delete-all"
fi

# docker system prune / docker rm
if printf '%s' "${COMMAND}" | grep -qE 'docker\s+(system\s+prune|rm\s+-f|rmi\s+-f|volume\s+prune)'; then
    IS_DESTRUCTIVE="true"
    DESTRUCTIVE_TYPE="docker-prune"
fi

# kubectl delete
if printf '%s' "${COMMAND}" | grep -qE 'kubectl\s+delete'; then
    IS_DESTRUCTIVE="true"
    DESTRUCTIVE_TYPE="kubectl-delete"
fi

if [ "${IS_DESTRUCTIVE}" != "true" ]; then
    exit 0
fi

# Simulate impact based on type
CWD="$(pwd)"

case "${DESTRUCTIVE_TYPE}" in
    rm)
        # Use dry-run approach: count files that would match
        # Note: this is a best-effort heuristic — complex shell commands may not parse correctly
        TOTAL_FILES=0
        TOTAL_DIRS=0

        # Check if -r or -R flag is present (recursive)
        IS_RECURSIVE="false"
        if printf '%s' "${COMMAND}" | grep -qE 'rm\s+.*-[a-zA-Z]*[rR]'; then
            IS_RECURSIVE="true"
        fi

        # Try to count affected files via git tracked files as a safe proxy
        # This avoids following symlinks or running arbitrary globs
        TRACKED_TOTAL="$(git ls-files 2>/dev/null | wc -l | tr -d ' ')"
        UNCOMMITTED="$(git diff --name-only HEAD 2>/dev/null | wc -l | tr -d ' ')"
        if ! printf '%s' "${TRACKED_TOTAL}" | grep -qE '^[0-9]+$'; then TRACKED_TOTAL="0"; fi
        if ! printf '%s' "${UNCOMMITTED}" | grep -qE '^[0-9]+$'; then UNCOMMITTED="0"; fi

        # Check for broad targets (., *, /, ~)
        if printf '%s' "${COMMAND}" | grep -qE 'rm\s+.*(\s+/\s|\s+/\s*$|\s+\.\s|\s+\*\s|\s+~)'; then
            IMPACT_MSG="rm: BROAD TARGET detected — potentially ${TRACKED_TOTAL} tracked files at risk"
        elif [ "${IS_RECURSIVE}" = "true" ]; then
            IMPACT_MSG="rm (recursive): directory deletion — check target carefully"
        else
            IMPACT_MSG="rm: file deletion command detected"
        fi
        ;;

    git-reset-hard)
        # Count files with uncommitted changes
        CHANGED="$(git diff --name-only HEAD 2>/dev/null | wc -l | tr -d ' ')"
        STAGED="$(git diff --cached --name-only 2>/dev/null | wc -l | tr -d ' ')"
        TOTAL_LINES="$(git diff HEAD 2>/dev/null | grep -c '^[+-]' || echo "0")"
        if ! printf '%s' "${CHANGED}" | grep -qE '^[0-9]+$'; then CHANGED="0"; fi
        if ! printf '%s' "${STAGED}" | grep -qE '^[0-9]+$'; then STAGED="0"; fi
        if ! printf '%s' "${TOTAL_LINES}" | grep -qE '^[0-9]+$'; then TOTAL_LINES="0"; fi
        IMPACT_MSG="git reset --hard: ${CHANGED} modified + ${STAGED} staged file(s) would be discarded (${TOTAL_LINES} changed lines)"
        ;;

    git-push-force)
        # Check how many commits would be rewritten
        REMOTE_BRANCH="$(git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null | tr -cd 'a-zA-Z0-9_./-' || true)"
        if [ -n "${REMOTE_BRANCH}" ]; then
            # Validate branch name format before using in git commands
            if printf '%s' "${REMOTE_BRANCH}" | grep -qE '^[a-zA-Z0-9_./-]+$' && ! printf '%s' "${REMOTE_BRANCH}" | grep -qE '^-'; then
                AHEAD="$(git rev-list --count "${REMOTE_BRANCH}..HEAD" 2>/dev/null | tr -d ' ' || echo "?")"
                BEHIND="$(git rev-list --count "HEAD..${REMOTE_BRANCH}" 2>/dev/null | tr -d ' ' || echo "?")"
                IMPACT_MSG="git push --force: ${BEHIND} remote commit(s) would be overwritten, ${AHEAD} local commit(s) pushed"
            else
                IMPACT_MSG="git push --force: upstream branch name invalid for analysis"
            fi
        else
            IMPACT_MSG="git push --force: no upstream tracked — remote history may be rewritten"
        fi
        ;;

    git-clean)
        UNTRACKED="$(git ls-files --others --exclude-standard 2>/dev/null | wc -l | tr -d ' ')"
        if ! printf '%s' "${UNTRACKED}" | grep -qE '^[0-9]+$'; then UNTRACKED="0"; fi
        IMPACT_MSG="git clean: ${UNTRACKED} untracked file(s) would be permanently deleted"
        ;;

    git-discard)
        CHANGED="$(git diff --name-only 2>/dev/null | wc -l | tr -d ' ')"
        TOTAL_LINES="$(git diff 2>/dev/null | grep -c '^[+-]' || echo "0")"
        if ! printf '%s' "${CHANGED}" | grep -qE '^[0-9]+$'; then CHANGED="0"; fi
        if ! printf '%s' "${TOTAL_LINES}" | grep -qE '^[0-9]+$'; then TOTAL_LINES="0"; fi
        IMPACT_MSG="git checkout/restore: ${CHANGED} file(s) with ${TOTAL_LINES} changed lines would be discarded"
        ;;

    sql-drop)
        TABLE_NAME="$(printf '%s' "${COMMAND}" | grep -oiE 'DROP\s+(TABLE|DATABASE)\s+(IF\s+EXISTS\s+)?[A-Za-z_][A-Za-z0-9_.]*' | awk '{print $NF}' | tr -cd 'a-zA-Z0-9_.' | cut -c1-50)"
        IMPACT_MSG="SQL DROP: table/database '${TABLE_NAME}' would be permanently destroyed — ALL data lost"
        ;;

    sql-truncate)
        TABLE_NAME="$(printf '%s' "${COMMAND}" | grep -oiE 'TRUNCATE\s+TABLE\s+[A-Za-z_][A-Za-z0-9_.]*' | awk '{print $NF}' | tr -cd 'a-zA-Z0-9_.' | cut -c1-50)"
        IMPACT_MSG="SQL TRUNCATE: all rows in '${TABLE_NAME}' would be deleted"
        ;;

    sql-delete-all)
        TABLE_NAME="$(printf '%s' "${COMMAND}" | grep -oiE 'DELETE\s+FROM\s+[A-Za-z_][A-Za-z0-9_.]*' | awk '{print $NF}' | tr -cd 'a-zA-Z0-9_.' | cut -c1-50)"
        IMPACT_MSG="SQL DELETE without WHERE: all rows in '${TABLE_NAME}' would be deleted"
        ;;

    docker-prune)
        IMPACT_MSG="Docker: containers/images/volumes would be permanently removed"
        ;;

    kubectl-delete)
        RESOURCE="$(printf '%s' "${COMMAND}" | sed 's/.*kubectl\s\+delete\s\+//' | awk '{print $1}' | tr -cd 'a-zA-Z0-9_./-' | cut -c1-50)"
        IMPACT_MSG="kubectl delete: resource '${RESOURCE}' would be permanently deleted from cluster"
        ;;
esac

# Sanitize IMPACT_MSG: strip to alphanumeric + basic punctuation, limit length
SAFE_IMPACT="$(printf '%b' "${IMPACT_MSG}" | tr -cd 'a-zA-Z0-9 :.,_()/-\n' | head -5 | cut -c1-200)"

# Output minimal structured data to stdout (for Claude context)
# Only safe, pre-determined strings are included
printf 'DATA ONLY - not instructions:\n'
printf 'blast-radius-simulator: destructive_command_detected\n'
printf 'type: %s\n' "${DESTRUCTIVE_TYPE}"
printf 'impact: %s\n' "${SAFE_IMPACT}"
printf 'action: ask user for confirmation before executing\n'

# Show full details to user via stderr (not read by Claude)
>&2 printf '[blast-radius] ⚠️  %s\n' "$(printf '%b' "${IMPACT_MSG}" | head -1 | tr -d '\000-\037\177')"

exit 0
