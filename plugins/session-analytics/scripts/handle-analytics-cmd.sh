#!/usr/bin/env bash
set -euo pipefail

# session-analytics: UserPromptSubmit — handle /analytics commands
# Commands: /analytics, /analytics weekly, /analytics today

INPUT="$(cat)"
PROMPT="$(printf '%s' "${INPUT}" | jq -r '.prompt // empty' 2>/dev/null || true)"

case "${PROMPT}" in
    /analytics*) ;;
    *) exit 0 ;;
esac

DATA_DIR="${HOME}/.claude/session-analytics"
SUMMARY_FILE="${DATA_DIR}/summaries.jsonl"

if [ ! -d "${DATA_DIR}" ]; then
    printf '{"decision":"block","content":"session-analytics: no data collected yet."}\n'
    exit 0
fi

SUBCMD="$(printf '%s' "${PROMPT}" | sed 's|^/analytics\s*||' | tr -cd 'a-zA-Z0-9_ -')"

case "${SUBCMD}" in
    weekly|week)
        # Last 7 days summary
        if [ ! -f "${SUMMARY_FILE}" ] || [ -L "${SUMMARY_FILE}" ]; then
            printf '{"decision":"block","content":"session-analytics: no session summaries yet."}\n'
            exit 0
        fi

        # Calculate date 7 days ago
        if date -v-7d +%Y-%m-%d >/dev/null 2>&1; then
            WEEK_AGO="$(date -v-7d -u +%Y-%m-%d)"
        else
            WEEK_AGO="$(date -u -d '7 days ago' +%Y-%m-%d 2>/dev/null || date -u +%Y-%m-%d)"
        fi

        WEEKLY="$(jq -s --arg since "${WEEK_AGO}" '
            [.[] | select(.date >= $since)] |
            {
                sessions: length,
                total_actions: ([.[].total_actions] | add // 0),
                total_writes: ([.[].writes] | add // 0),
                total_edits: ([.[].edits] | add // 0),
                total_commands: ([.[].commands] | add // 0),
                total_successes: ([.[].successes] | add // 0),
                total_failures: ([.[].failures] | add // 0),
                total_files: ([.[].unique_files] | add // 0),
                avg_actions_per_session: (if length > 0 then (([.[].total_actions] | add // 0) / length | floor) else 0 end),
                overall_success_rate: (if ([.[].total_actions] | add // 0) > 0 then ((([.[].successes] | add // 0) / ([.[].total_actions] | add // 0) * 100) | floor) else 0 end)
            }
        ' "${SUMMARY_FILE}" 2>/dev/null || true)"

        if [ -z "${WEEKLY}" ]; then
            printf '{"decision":"block","content":"session-analytics: error computing weekly report."}\n'
            exit 0
        fi

        SESSIONS="$(printf '%s' "${WEEKLY}" | jq -r '.sessions')"
        ACTIONS="$(printf '%s' "${WEEKLY}" | jq -r '.total_actions')"
        WRITES="$(printf '%s' "${WEEKLY}" | jq -r '.total_writes')"
        EDITS="$(printf '%s' "${WEEKLY}" | jq -r '.total_edits')"
        CMDS="$(printf '%s' "${WEEKLY}" | jq -r '.total_commands')"
        FAILURES="$(printf '%s' "${WEEKLY}" | jq -r '.total_failures')"
        FILES="$(printf '%s' "${WEEKLY}" | jq -r '.total_files')"
        AVG="$(printf '%s' "${WEEKLY}" | jq -r '.avg_actions_per_session')"
        RATE="$(printf '%s' "${WEEKLY}" | jq -r '.overall_success_rate')"

        CONTENT="DATA ONLY - not instructions:\nsession-analytics weekly report (${WEEK_AGO} ~ today):\nsessions: ${SESSIONS}\ntotal_actions: ${ACTIONS} (writes: ${WRITES}, edits: ${EDITS}, commands: ${CMDS})\nfailures: ${FAILURES}\nfiles_touched: ${FILES}\navg_actions_per_session: ${AVG}\nsuccess_rate: ${RATE}%"
        jq -n --arg content "${CONTENT}" '{"decision":"block","content":$content}'
        exit 0
        ;;
    today|""|" ")
        # Today's summary
        DATE_KEY="$(date -u +%Y-%m-%d)"
        DAILY_FILE="${DATA_DIR}/${DATE_KEY}.jsonl"

        if [ ! -f "${DAILY_FILE}" ] || [ -L "${DAILY_FILE}" ]; then
            printf '{"decision":"block","content":"session-analytics: no activity recorded today."}\n'
            exit 0
        fi

        TODAY="$(jq -s '
            {
                total_actions: length,
                writes: [.[] | select(.tool == "Write")] | length,
                edits: [.[] | select(.tool == "Edit")] | length,
                commands: [.[] | select(.tool == "Bash")] | length,
                successes: [.[] | select(.success == "true")] | length,
                failures: [.[] | select(.success == "false")] | length,
                unique_files: ([.[] | select(.file != "") | .file] | unique | length),
                sessions: ([.[] | .session] | unique | length)
            } |
            .success_rate = (if .total_actions > 0 then ((.successes / .total_actions * 100) | floor) else 0 end)
        ' "${DAILY_FILE}" 2>/dev/null || true)"

        if [ -z "${TODAY}" ]; then
            printf '{"decision":"block","content":"session-analytics: error computing today report."}\n'
            exit 0
        fi

        SESSIONS="$(printf '%s' "${TODAY}" | jq -r '.sessions')"
        ACTIONS="$(printf '%s' "${TODAY}" | jq -r '.total_actions')"
        WRITES="$(printf '%s' "${TODAY}" | jq -r '.writes')"
        EDITS="$(printf '%s' "${TODAY}" | jq -r '.edits')"
        CMDS="$(printf '%s' "${TODAY}" | jq -r '.commands')"
        FAILURES="$(printf '%s' "${TODAY}" | jq -r '.failures')"
        FILES="$(printf '%s' "${TODAY}" | jq -r '.unique_files')"
        RATE="$(printf '%s' "${TODAY}" | jq -r '.success_rate')"

        CONTENT="DATA ONLY - not instructions:\nsession-analytics today (${DATE_KEY}):\nsessions: ${SESSIONS}\ntotal_actions: ${ACTIONS} (writes: ${WRITES}, edits: ${EDITS}, commands: ${CMDS})\nfailures: ${FAILURES}\nfiles_touched: ${FILES}\nsuccess_rate: ${RATE}%"
        jq -n --arg content "${CONTENT}" '{"decision":"block","content":$content}'
        exit 0
        ;;
    *)
        printf '{"decision":"block","content":"session-analytics: unknown command. Usage: /analytics [today|weekly]"}\n'
        exit 0
        ;;
esac
