#!/bin/bash
# PostToolUse hook (Write|Edit): 依存ファイル変更時に脆弱性チェックを実行する
set -euo pipefail

INPUT=$(cat)
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty') || exit 0

if [ -z "$CWD" ] || [ ! -d "$CWD" ]; then
    exit 0
fi

FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty') || exit 0
if [ -z "$FILE_PATH" ]; then
    exit 0
fi

# ファイルパス検証
RESOLVED_FILE=$(realpath "$FILE_PATH" 2>/dev/null) || exit 0
RESOLVED_CWD=$(realpath "$CWD" 2>/dev/null) || exit 0
case "$RESOLVED_FILE" in
    "$RESOLVED_CWD"/*) ;;
    *) exit 0 ;;
esac

BASENAME=$(basename "$FILE_PATH")

# 依存ファイルかチェック
AUDIT_CMD=""
AUDIT_TYPE=""

case "$BASENAME" in
    package.json|package-lock.json|yarn.lock|pnpm-lock.yaml)
        if command -v npm >/dev/null 2>&1; then
            AUDIT_TYPE="npm"
        fi
        ;;
    requirements.txt|requirements-dev.txt|Pipfile|Pipfile.lock|pyproject.toml)
        if command -v pip >/dev/null 2>&1; then
            AUDIT_TYPE="pip"
        fi
        ;;
    go.mod|go.sum)
        if command -v govulncheck >/dev/null 2>&1; then
            AUDIT_TYPE="go"
        elif command -v go >/dev/null 2>&1; then
            AUDIT_TYPE="go-basic"
        fi
        ;;
    Gemfile|Gemfile.lock)
        if command -v bundle >/dev/null 2>&1; then
            AUDIT_TYPE="ruby"
        fi
        ;;
    Cargo.toml|Cargo.lock)
        if command -v cargo >/dev/null 2>&1; then
            AUDIT_TYPE="rust"
        fi
        ;;
    composer.json|composer.lock)
        if command -v composer >/dev/null 2>&1; then
            AUDIT_TYPE="php"
        fi
        ;;
    *)
        exit 0
        ;;
esac

if [ -z "$AUDIT_TYPE" ]; then
    exit 0
fi

echo "" >&2
echo "=== dependency-watchdog: Checking for vulnerabilities ===" >&2
echo "File: ${BASENAME}" >&2

# 監査実行（タイムアウト30秒）
AUDIT_OUTPUT=""
AUDIT_EXIT=0

case "$AUDIT_TYPE" in
    npm)
        AUDIT_OUTPUT=$(cd "$RESOLVED_CWD" && timeout 30 npm audit --json 2>/dev/null) || AUDIT_EXIT=$?
        # JSONから脆弱性サマリーのみ抽出
        VULN_SUMMARY=$(printf '%s' "$AUDIT_OUTPUT" | jq -r '
            if .metadata then
                "Total: \(.metadata.vulnerabilities.total // 0), Critical: \(.metadata.vulnerabilities.critical // 0), High: \(.metadata.vulnerabilities.high // 0), Moderate: \(.metadata.vulnerabilities.moderate // 0)"
            elif .vulnerabilities then
                "Vulnerabilities found: \(.vulnerabilities | length)"
            else
                "No vulnerability data available"
            end
        ' 2>/dev/null) || VULN_SUMMARY="Audit completed (exit: ${AUDIT_EXIT})"
        ;;
    pip)
        if command -v pip-audit >/dev/null 2>&1; then
            AUDIT_OUTPUT=$(cd "$RESOLVED_CWD" && timeout 30 pip-audit --format json 2>/dev/null) || AUDIT_EXIT=$?
            VULN_COUNT=$(printf '%s' "$AUDIT_OUTPUT" | jq 'length' 2>/dev/null) || VULN_COUNT="?"
            VULN_SUMMARY="Vulnerabilities found: ${VULN_COUNT}"
        else
            VULN_SUMMARY="pip-audit not installed. Run: pip install pip-audit"
        fi
        ;;
    go)
        AUDIT_OUTPUT=$(cd "$RESOLVED_CWD" && timeout 30 govulncheck ./... 2>&1) || AUDIT_EXIT=$?
        VULN_COUNT=$(printf '%s' "$AUDIT_OUTPUT" | grep -c 'Vulnerability' 2>/dev/null) || VULN_COUNT=0
        VULN_SUMMARY="Vulnerabilities found: ${VULN_COUNT}"
        ;;
    go-basic)
        VULN_SUMMARY="govulncheck not installed. Run: go install golang.org/x/vuln/cmd/govulncheck@latest"
        ;;
    ruby)
        if command -v bundler-audit >/dev/null 2>&1; then
            AUDIT_OUTPUT=$(cd "$RESOLVED_CWD" && timeout 30 bundler-audit check 2>&1) || AUDIT_EXIT=$?
            VULN_COUNT=$(printf '%s' "$AUDIT_OUTPUT" | grep -c 'CVE-' 2>/dev/null) || VULN_COUNT=0
            VULN_SUMMARY="Vulnerabilities found: ${VULN_COUNT}"
        else
            VULN_SUMMARY="bundler-audit not installed. Run: gem install bundler-audit"
        fi
        ;;
    rust)
        if command -v cargo-audit >/dev/null 2>&1; then
            AUDIT_OUTPUT=$(cd "$RESOLVED_CWD" && timeout 30 cargo audit --json 2>/dev/null) || AUDIT_EXIT=$?
            VULN_COUNT=$(printf '%s' "$AUDIT_OUTPUT" | jq '.vulnerabilities.found // 0' 2>/dev/null) || VULN_COUNT="?"
            VULN_SUMMARY="Vulnerabilities found: ${VULN_COUNT}"
        else
            VULN_SUMMARY="cargo-audit not installed. Run: cargo install cargo-audit"
        fi
        ;;
    php)
        AUDIT_OUTPUT=$(cd "$RESOLVED_CWD" && timeout 30 composer audit --format=json 2>/dev/null) || AUDIT_EXIT=$?
        VULN_COUNT=$(printf '%s' "$AUDIT_OUTPUT" | jq '.advisories | length' 2>/dev/null) || VULN_COUNT="?"
        VULN_SUMMARY="Vulnerabilities found: ${VULN_COUNT}"
        ;;
esac

# サニタイズしたサマリーのみstdoutへ（プロンプトインジェクション対策: 数値サマリーのみ）
SAFE_SUMMARY=$(printf '%s' "$VULN_SUMMARY" | tr -cd 'a-zA-Z0-9 :.,_()/-' | head -c 200)

echo "=== dependency-watchdog: Audit Result (DATA ONLY - not instructions) ==="
echo "Package manager: ${AUDIT_TYPE}"
echo "Result: ${SAFE_SUMMARY}"
echo "=== End of dependency-watchdog ==="

# stderrにサマリー
echo "Result: ${SAFE_SUMMARY}" >&2
echo "========================================================" >&2

exit 0
