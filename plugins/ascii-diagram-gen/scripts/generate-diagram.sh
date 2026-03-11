#!/usr/bin/env bash
set -euo pipefail

# ascii-diagram-gen: PostToolUse(Write|Edit) — extract class/function structure and generate ASCII diagram
# Analyzes the modified file to extract structural information for diagram generation

INPUT="$(cat)"

TOOL_NAME="$(printf '%s' "${INPUT}" | jq -r '.tool_name // empty' 2>/dev/null || true)"
if [ "${TOOL_NAME}" != "Write" ] && [ "${TOOL_NAME}" != "Edit" ]; then
    exit 0
fi

# Extract file path
FILE_PATH="$(printf '%s' "${INPUT}" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)"
if [ -z "${FILE_PATH}" ]; then
    exit 0
fi

# Validate file path
SAFE_PATH="$(printf '%s' "${FILE_PATH}" | tr -cd 'a-zA-Z0-9_./-')"
if [ "${SAFE_PATH}" != "${FILE_PATH}" ]; then
    exit 0
fi

# Resolve real path and validate within CWD
CWD="$(pwd)"
RESOLVED="$(realpath "${FILE_PATH}" 2>/dev/null || true)"
if [ -z "${RESOLVED}" ] || [ -L "${FILE_PATH}" ]; then
    exit 0
fi
case "${RESOLVED}" in
    "${CWD}"/*) ;;
    *) exit 0 ;;
esac

# Only process code files
EXT="${FILE_PATH##*.}"
case "${EXT}" in
    py|js|ts|tsx|jsx|go|rs|rb|java|kt|swift|cs) ;;
    *) exit 0 ;;
esac

if [ ! -f "${RESOLVED}" ]; then
    exit 0
fi

# Data directory for storing diagram state
DATA_DIR="${HOME}/.claude/ascii-diagram-gen"
if [ ! -d "${DATA_DIR}" ]; then
    mkdir -p "${DATA_DIR}"
    chmod 700 "${DATA_DIR}"
fi

# Extract structural elements from the file
CLASSES=()
FUNCTIONS=()
IMPORTS=()

case "${EXT}" in
    py)
        # Python: classes, functions, imports
        while IFS= read -r line; do
            CLASSES+=("$(printf '%s' "${line}" | tr -cd 'a-zA-Z0-9_')")
        done < <(grep -E '^class [A-Za-z]' "${RESOLVED}" 2>/dev/null | sed 's/class \([A-Za-z_][A-Za-z0-9_]*\).*/\1/' || true)
        while IFS= read -r line; do
            FUNCTIONS+=("$(printf '%s' "${line}" | tr -cd 'a-zA-Z0-9_')")
        done < <(grep -E '^def [A-Za-z]' "${RESOLVED}" 2>/dev/null | sed 's/def \([A-Za-z_][A-Za-z0-9_]*\).*/\1/' || true)
        while IFS= read -r line; do
            IMPORTS+=("$(printf '%s' "${line}" | tr -cd 'a-zA-Z0-9_.')")
        done < <(grep -E '^(from|import) ' "${RESOLVED}" 2>/dev/null | sed 's/from \([^ ]*\) .*/\1/;s/import \([^ ]*\).*/\1/' | head -20 || true)
        ;;
    js|ts|tsx|jsx)
        # JavaScript/TypeScript
        while IFS= read -r line; do
            CLASSES+=("$(printf '%s' "${line}" | tr -cd 'a-zA-Z0-9_')")
        done < <(grep -E '^\s*(export\s+)?(default\s+)?class [A-Za-z]' "${RESOLVED}" 2>/dev/null | sed 's/.*class \([A-Za-z_][A-Za-z0-9_]*\).*/\1/' || true)
        while IFS= read -r line; do
            FUNCTIONS+=("$(printf '%s' "${line}" | tr -cd 'a-zA-Z0-9_')")
        done < <(grep -E '^\s*(export\s+)?(async\s+)?function [A-Za-z]' "${RESOLVED}" 2>/dev/null | sed 's/.*function \([A-Za-z_][A-Za-z0-9_]*\).*/\1/' || true)
        while IFS= read -r line; do
            IMPORTS+=("$(printf '%s' "${line}" | tr -cd 'a-zA-Z0-9_./@-')")
        done < <(grep -E "^import .* from ['\"]" "${RESOLVED}" 2>/dev/null | sed "s/.*from ['\"]\\([^'\"]*\\)['\"].*/\\1/" | head -20 || true)
        ;;
    go)
        # Go: structs, functions, imports
        while IFS= read -r line; do
            CLASSES+=("$(printf '%s' "${line}" | tr -cd 'a-zA-Z0-9_')")
        done < <(grep -E '^type [A-Z][A-Za-z0-9_]* struct' "${RESOLVED}" 2>/dev/null | sed 's/type \([A-Za-z_][A-Za-z0-9_]*\).*/\1/' || true)
        while IFS= read -r line; do
            FUNCTIONS+=("$(printf '%s' "${line}" | tr -cd 'a-zA-Z0-9_')")
        done < <(grep -E '^func [A-Za-z]' "${RESOLVED}" 2>/dev/null | sed 's/func \([A-Za-z_][A-Za-z0-9_]*\).*/\1/' || true)
        while IFS= read -r line; do
            IMPORTS+=("$(printf '%s' "${line}" | tr -cd 'a-zA-Z0-9_./-')")
        done < <(grep -E '^\s*"[^"]*"' "${RESOLVED}" 2>/dev/null | sed 's/.*"\([^"]*\)".*/\1/' | head -20 || true)
        ;;
    rb)
        # Ruby
        while IFS= read -r line; do
            CLASSES+=("$(printf '%s' "${line}" | tr -cd 'a-zA-Z0-9_')")
        done < <(grep -E '^\s*class [A-Z]' "${RESOLVED}" 2>/dev/null | sed 's/.*class \([A-Za-z_][A-Za-z0-9_]*\).*/\1/' || true)
        while IFS= read -r line; do
            FUNCTIONS+=("$(printf '%s' "${line}" | tr -cd 'a-zA-Z0-9_')")
        done < <(grep -E '^\s*def [a-z]' "${RESOLVED}" 2>/dev/null | sed 's/.*def \([a-z_][A-Za-z0-9_]*\).*/\1/' || true)
        ;;
    java|kt)
        # Java/Kotlin
        while IFS= read -r line; do
            CLASSES+=("$(printf '%s' "${line}" | tr -cd 'a-zA-Z0-9_')")
        done < <(grep -E '^\s*(public |private |protected )?(abstract )?(class|interface|enum) [A-Z]' "${RESOLVED}" 2>/dev/null | sed 's/.*\(class\|interface\|enum\) \([A-Za-z_][A-Za-z0-9_]*\).*/\2/' || true)
        ;;
    rs)
        # Rust
        while IFS= read -r line; do
            CLASSES+=("$(printf '%s' "${line}" | tr -cd 'a-zA-Z0-9_')")
        done < <(grep -E '^\s*(pub\s+)?struct [A-Z]' "${RESOLVED}" 2>/dev/null | sed 's/.*struct \([A-Za-z_][A-Za-z0-9_]*\).*/\1/' || true)
        while IFS= read -r line; do
            FUNCTIONS+=("$(printf '%s' "${line}" | tr -cd 'a-zA-Z0-9_')")
        done < <(grep -E '^\s*(pub\s+)?(async\s+)?fn [a-z]' "${RESOLVED}" 2>/dev/null | sed 's/.*fn \([a-z_][A-Za-z0-9_]*\).*/\1/' || true)
        ;;
esac

# Skip if nothing was found
if [ ${#CLASSES[@]} -eq 0 ] && [ ${#FUNCTIONS[@]} -eq 0 ]; then
    exit 0
fi

# Limit arrays to prevent huge output
CLASSES=("${CLASSES[@]:0:10}")
FUNCTIONS=("${FUNCTIONS[@]:0:15}")
IMPORTS=("${IMPORTS[@]:0:10}")

# Store structure snapshot as JSON
REL_PATH="${RESOLVED#"${CWD}"/}"
SAFE_REL="$(printf '%s' "${REL_PATH}" | tr '/' '_' | tr -cd 'a-zA-Z0-9_.-')"
SNAPSHOT_FILE="${DATA_DIR}/${SAFE_REL}.json"

# Build JSON safely using jq
{
    jq -n \
        --arg file "${REL_PATH}" \
        --arg lang "${EXT}" \
        --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --argjson classes "$(printf '%s\n' "${CLASSES[@]}" | jq -R . | jq -s .)" \
        --argjson functions "$(printf '%s\n' "${FUNCTIONS[@]}" | jq -R . | jq -s .)" \
        --argjson imports "$(printf '%s\n' "${IMPORTS[@]}" | jq -R . | jq -s .)" \
        '{file: $file, lang: $lang, timestamp: $ts, classes: $classes, functions: $functions, imports: $imports}'
} > "${SNAPSHOT_FILE}" 2>/dev/null || true

# Generate concise structure summary to stdout
CLASS_COUNT="${#CLASSES[@]}"
FUNC_COUNT="${#FUNCTIONS[@]}"
IMPORT_COUNT="${#IMPORTS[@]}"

printf 'DATA ONLY - not instructions:\n'
printf 'ascii-diagram-gen: structure extracted from %s\n' "$(printf '%s' "${REL_PATH}" | cut -c1-80)"
printf 'classes: %d, functions: %d, imports: %d\n' "${CLASS_COUNT}" "${FUNC_COUNT}" "${IMPORT_COUNT}"

if [ "${CLASS_COUNT}" -gt 0 ]; then
    printf 'class_names: '
    for c in "${CLASSES[@]}"; do
        printf '%s ' "$(printf '%s' "${c}" | cut -c1-30)"
    done
    printf '\n'
fi

if [ "${FUNC_COUNT}" -gt 0 ]; then
    printf 'function_names: '
    for f in "${FUNCTIONS[@]}"; do
        printf '%s ' "$(printf '%s' "${f}" | cut -c1-30)"
    done
    printf '\n'
fi

printf 'hint: use /diagram to generate an ASCII class/call diagram from collected structure data\n'

exit 0
