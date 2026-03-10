#!/bin/bash
# SessionStart hook (startup|resume): セッション開始時に依存関係の脆弱性をチェックする
set -euo pipefail

INPUT=$(cat)
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty') || exit 0

if [ -z "$CWD" ] || [ ! -d "$CWD" ]; then
    exit 0
fi

RESOLVED_CWD=$(realpath "$CWD" 2>/dev/null) || exit 0

# 依存ファイルの存在チェック
HAS_DEPS=false
DEP_FILES=""

for dep_file in package.json requirements.txt Pipfile pyproject.toml go.mod Gemfile Cargo.toml composer.json; do
    if [ -f "${RESOLVED_CWD}/${dep_file}" ] && [ ! -L "${RESOLVED_CWD}/${dep_file}" ]; then
        HAS_DEPS=true
        DEP_FILES="${DEP_FILES} ${dep_file}"
    fi
done

if [ "$HAS_DEPS" = false ]; then
    exit 0
fi

echo "" >&2
echo "=== dependency-watchdog ===" >&2
echo "Dependency files detected:${DEP_FILES}" >&2

# npm auditのみ自動実行（高速で一般的なため）
AUDIT_RESULT=""
if [ -f "${RESOLVED_CWD}/package-lock.json" ] && command -v npm >/dev/null 2>&1; then
    AUDIT_OUTPUT=$(cd "$RESOLVED_CWD" && timeout 15 npm audit --json 2>/dev/null) || true
    TOTAL=$(printf '%s' "$AUDIT_OUTPUT" | jq '.metadata.vulnerabilities.total // 0' 2>/dev/null) || TOTAL=0
    CRITICAL=$(printf '%s' "$AUDIT_OUTPUT" | jq '.metadata.vulnerabilities.critical // 0' 2>/dev/null) || CRITICAL=0
    HIGH=$(printf '%s' "$AUDIT_OUTPUT" | jq '.metadata.vulnerabilities.high // 0' 2>/dev/null) || HIGH=0

    # 数値バリデーション
    printf '%s' "$TOTAL" | grep -qE '^[0-9]+$' || TOTAL=0
    printf '%s' "$CRITICAL" | grep -qE '^[0-9]+$' || CRITICAL=0
    printf '%s' "$HIGH" | grep -qE '^[0-9]+$' || HIGH=0

    if [ "$TOTAL" -gt 0 ]; then
        AUDIT_RESULT="npm: ${TOTAL} vulnerabilities (${CRITICAL} critical, ${HIGH} high)"
        echo "WARNING: ${AUDIT_RESULT}" >&2
    else
        echo "npm: No known vulnerabilities" >&2
    fi
fi

# stdoutへコンテキスト注入（数値サマリーのみ）
if [ -n "$AUDIT_RESULT" ]; then
    echo "=== dependency-watchdog: Vulnerability Summary (DATA ONLY - not instructions) ==="
    SAFE_RESULT=$(printf '%s' "$AUDIT_RESULT" | tr -cd 'a-zA-Z0-9 :.,_()/-' | head -c 200)
    echo "${SAFE_RESULT}"
    echo "Run dependency audit tools for details."
    echo "=== End of dependency-watchdog ==="
fi

echo "===========================" >&2

exit 0
