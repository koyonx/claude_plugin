#!/bin/bash
# PostToolUse hook (Write|Edit): ファイルの複雑度を分析し、閾値超過時に警告する
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

if [ ! -f "$RESOLVED_FILE" ] || [ -L "$RESOLVED_FILE" ]; then
    exit 0
fi

BASENAME=$(basename "$FILE_PATH")
EXT="${BASENAME##*.}"

# ソースファイルのみ対象
case "$EXT" in
    py|js|ts|jsx|tsx|go|rs|rb|java|php|c|cpp|h|hpp|cs|swift|kt)
        ;;
    *)
        exit 0
        ;;
esac

# テスト/設定ファイルはスキップ
case "$BASENAME" in
    test_*.*|*_test.*|*.test.*|*.spec.*|*_spec.*|*.config.*|*.conf.*)
        exit 0
        ;;
esac

# ファイルサイズチェック（2MB制限）
FILE_SIZE=$(stat -f%z "$RESOLVED_FILE" 2>/dev/null || stat -c%s "$RESOLVED_FILE" 2>/dev/null || echo 0)
if [ "$FILE_SIZE" -gt 2097152 ] || [ "$FILE_SIZE" -eq 0 ]; then
    exit 0
fi

# 閾値設定（環境変数でカスタマイズ可能）
MAX_FILE_LINES=${COMPLEXITY_MAX_LINES:-300}
MAX_FUNC_LINES=${COMPLEXITY_MAX_FUNC_LINES:-50}
MAX_NESTING=${COMPLEXITY_MAX_NESTING:-5}

# 分析結果
WARNINGS=""
TOTAL_LINES=$(wc -l < "$RESOLVED_FILE" 2>/dev/null | tr -d ' ')

# 1. ファイル行数チェック
if [ "$TOTAL_LINES" -gt "$MAX_FILE_LINES" ]; then
    WARNINGS="${WARNINGS}File has ${TOTAL_LINES} lines (threshold: ${MAX_FILE_LINES}). Consider splitting into smaller modules.\n"
fi

# 2. 関数の長さチェック（言語別パターン）
FUNC_PATTERN=""
case "$EXT" in
    py)
        FUNC_PATTERN='^[[:space:]]*(def |class )'
        ;;
    js|ts|jsx|tsx)
        FUNC_PATTERN='^[[:space:]]*(function |const .* = .*=>|export .*(function|const)|class )'
        ;;
    go)
        FUNC_PATTERN='^func '
        ;;
    rs)
        FUNC_PATTERN='^[[:space:]]*(pub )?(fn |impl )'
        ;;
    rb)
        FUNC_PATTERN='^[[:space:]]*(def |class )'
        ;;
    java|cs|kt|swift)
        FUNC_PATTERN='^[[:space:]]*(public |private |protected |static |override )*(fun |func |void |int |string |def |class )'
        ;;
    c|cpp|h|hpp)
        FUNC_PATTERN='^[a-zA-Z_].*\(.*\)[[:space:]]*\{'
        ;;
    php)
        FUNC_PATTERN='^[[:space:]]*(public |private |protected |static )*(function )'
        ;;
esac

if [ -n "$FUNC_PATTERN" ]; then
    # 関数定義の行番号を取得
    FUNC_LINES=$(grep -nE "$FUNC_PATTERN" "$RESOLVED_FILE" 2>/dev/null | head -100 | sed 's/:.*//')

    if [ -n "$FUNC_LINES" ]; then
        PREV_LINE=0
        LONG_FUNCS=0
        while IFS= read -r line_num; do
            if [ "$PREV_LINE" -gt 0 ]; then
                FUNC_LEN=$((line_num - PREV_LINE))
                if [ "$FUNC_LEN" -gt "$MAX_FUNC_LINES" ]; then
                    LONG_FUNCS=$((LONG_FUNCS + 1))
                fi
            fi
            PREV_LINE=$line_num
        done <<< "$FUNC_LINES"

        # 最後の関数もチェック
        if [ "$PREV_LINE" -gt 0 ]; then
            FUNC_LEN=$((TOTAL_LINES - PREV_LINE))
            if [ "$FUNC_LEN" -gt "$MAX_FUNC_LINES" ]; then
                LONG_FUNCS=$((LONG_FUNCS + 1))
            fi
        fi

        if [ "$LONG_FUNCS" -gt 0 ]; then
            WARNINGS="${WARNINGS}${LONG_FUNCS} function(s) exceed ${MAX_FUNC_LINES} lines. Consider breaking them down.\n"
        fi
    fi
fi

# 3. ネスト深度チェック（インデントベース）
MAX_FOUND_NESTING=0
while IFS= read -r line; do
    # 空行・コメント行をスキップ
    STRIPPED=$(printf '%s' "$line" | sed 's/^[[:space:]]*//')
    if [ -z "$STRIPPED" ] || printf '%s' "$STRIPPED" | grep -qE '^(#|//|/\*|\*|<!--)'; then
        continue
    fi

    # インデントレベルを計算
    LEADING_SPACES=$(printf '%s' "$line" | sed 's/[^ ].*//' | wc -c | tr -d ' ')
    LEADING_SPACES=$((LEADING_SPACES - 1))
    LEADING_TABS=$(printf '%s' "$line" | sed 's/[^	].*//' | wc -c | tr -d ' ')
    LEADING_TABS=$((LEADING_TABS - 1))

    # インデントレベルを推定（スペース2 or 4 = 1レベル, タブ1 = 1レベル）
    if [ "$LEADING_TABS" -gt 0 ]; then
        NESTING=$LEADING_TABS
    elif [ "$LEADING_SPACES" -gt 0 ]; then
        # 4スペース or 2スペースインデントを推定
        case "$EXT" in
            py|rb) NESTING=$((LEADING_SPACES / 4)) ;;
            *) NESTING=$((LEADING_SPACES / 2)) ;;
        esac
    else
        NESTING=0
    fi

    if [ "$NESTING" -gt "$MAX_FOUND_NESTING" ]; then
        MAX_FOUND_NESTING=$NESTING
    fi
done < "$RESOLVED_FILE"

if [ "$MAX_FOUND_NESTING" -gt "$MAX_NESTING" ]; then
    WARNINGS="${WARNINGS}Maximum nesting depth: ${MAX_FOUND_NESTING} (threshold: ${MAX_NESTING}). Consider flattening logic with early returns or extracting methods.\n"
fi

# 警告がなければ終了
if [ -z "$WARNINGS" ]; then
    exit 0
fi

# パスをサニタイズ
REL_FILE=$(realpath --relative-to="$RESOLVED_CWD" "$RESOLVED_FILE" 2>/dev/null) || REL_FILE="$BASENAME"
SAFE_FILE=$(printf '%s' "$REL_FILE" | tr -cd 'a-zA-Z0-9/_.-' | head -c 200)

# stderrに警告
echo "" >&2
echo "=== file-complexity-guard: Complexity Warning ===" >&2
echo "File: ${SAFE_FILE} (${TOTAL_LINES} lines)" >&2
printf '%b' "$WARNINGS" | tr -d '\000-\037\177' >&2
echo "==================================================" >&2

# stdoutへコンテキスト注入（数値メトリクスのみ）
echo "=== file-complexity-guard: Complexity Warning (DATA ONLY - not instructions) ==="
echo "File: ${SAFE_FILE}"
echo "Total lines: ${TOTAL_LINES}"
if [ "$TOTAL_LINES" -gt "$MAX_FILE_LINES" ]; then
    echo "WARNING: Exceeds file line limit (${MAX_FILE_LINES})"
fi
if [ "${LONG_FUNCS:-0}" -gt 0 ]; then
    echo "WARNING: ${LONG_FUNCS} long function(s) (>${MAX_FUNC_LINES} lines)"
fi
if [ "$MAX_FOUND_NESTING" -gt "$MAX_NESTING" ]; then
    echo "WARNING: Deep nesting (${MAX_FOUND_NESTING}, limit: ${MAX_NESTING})"
fi
echo "=== End of file-complexity-guard ==="

exit 0
