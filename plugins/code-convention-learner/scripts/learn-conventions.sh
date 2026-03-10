#!/bin/bash
# PostToolUse hook (Write|Edit): 変更されたファイルからコーディング規約を学習する
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
    "$RESOLVED_CWD"/*)
        ;;
    *)
        exit 0
        ;;
esac

# ファイルが存在し、symlinkでないことを確認（RESOLVED_FILEで検証）
if [ ! -f "$RESOLVED_FILE" ] || [ -L "$RESOLVED_FILE" ]; then
    exit 0
fi

# ファイルサイズチェック（1MB制限）
FILE_SIZE=$(stat -f%z "$RESOLVED_FILE" 2>/dev/null || stat -c%s "$RESOLVED_FILE" 2>/dev/null || echo 0)
if [ "$FILE_SIZE" -gt 1048576 ] || [ "$FILE_SIZE" -eq 0 ]; then
    exit 0
fi

BASENAME=$(basename "$FILE_PATH")
EXT="${BASENAME##*.}"

# 対応する言語を判定
LANG=""
case "$EXT" in
    js|jsx) LANG="javascript" ;;
    ts|tsx) LANG="typescript" ;;
    py) LANG="python" ;;
    go) LANG="go" ;;
    rs) LANG="rust" ;;
    rb) LANG="ruby" ;;
    java) LANG="java" ;;
    *)
        exit 0
        ;;
esac

# 行数チェック（5行未満はスキップ）
LINE_COUNT=$(wc -l < "$RESOLVED_FILE" 2>/dev/null | tr -d ' ')
if [ "$LINE_COUNT" -lt 5 ]; then
    exit 0
fi

# データディレクトリ
DATA_DIR="$HOME/.claude/code-convention-learner"
mkdir -p "$DATA_DIR"
chmod 700 "$DATA_DIR" 2>/dev/null || true

# プロジェクト名を生成
PROJECT_NAME=$(printf '%s' "$CWD" | tr -cd 'a-zA-Z0-9/_.-' | sed 's|/|_|g' | sed 's|^_||')
if [ -z "$PROJECT_NAME" ]; then
    PROJECT_NAME="default"
fi

CONV_FILE="${DATA_DIR}/${PROJECT_NAME}.json"

# 規約を分析
INDENT_SPACES=0
INDENT_TABS=0
INDENT_SIZE_2=0
INDENT_SIZE_4=0
SINGLE_QUOTES=0
DOUBLE_QUOTES=0
SEMICOLONS=0
NO_SEMICOLONS=0
CAMEL_CASE=0
SNAKE_CASE=0
TRAILING_COMMA=0
NO_TRAILING_COMMA=0

# インデント分析
while IFS= read -r line; do
    case "$line" in
        "  "*)
            INDENT_SPACES=$((INDENT_SPACES + 1))
            # 2スペース vs 4スペース
            if printf '%s' "$line" | grep -qE '^    [^ ]'; then
                INDENT_SIZE_4=$((INDENT_SIZE_4 + 1))
            elif printf '%s' "$line" | grep -qE '^  [^ ]'; then
                INDENT_SIZE_2=$((INDENT_SIZE_2 + 1))
            fi
            ;;
        "	"*)
            INDENT_TABS=$((INDENT_TABS + 1))
            ;;
    esac
done < "$RESOLVED_FILE"

# クォート分析（JS/TS/Python）
case "$LANG" in
    javascript|typescript|python)
        SINGLE_QUOTES=$(grep -c "'" "$RESOLVED_FILE" 2>/dev/null || echo 0)
        DOUBLE_QUOTES=$(grep -c '"' "$RESOLVED_FILE" 2>/dev/null || echo 0)
        ;;
esac

# セミコロン分析（JS/TS）
case "$LANG" in
    javascript|typescript)
        SEMICOLONS=$(grep -cE ';\s*$' "$RESOLVED_FILE" 2>/dev/null || echo 0)
        NO_SEMICOLONS=$(grep -cE '[^;{}\s]\s*$' "$RESOLVED_FILE" 2>/dev/null || echo 0)
        ;;
esac

# 命名規則分析
case "$LANG" in
    javascript|typescript)
        CAMEL_CASE=$(grep -coE '\b[a-z][a-z0-9]*[A-Z][a-zA-Z0-9]*\b' "$RESOLVED_FILE" 2>/dev/null || echo 0)
        SNAKE_CASE=$(grep -coE '\b[a-z][a-z0-9]*_[a-z][a-z0-9_]*\b' "$RESOLVED_FILE" 2>/dev/null || echo 0)
        ;;
    python|ruby)
        CAMEL_CASE=$(grep -coE '\b[a-z][a-z0-9]*[A-Z][a-zA-Z0-9]*\b' "$RESOLVED_FILE" 2>/dev/null || echo 0)
        SNAKE_CASE=$(grep -coE '\b[a-z][a-z0-9]*_[a-z][a-z0-9_]*\b' "$RESOLVED_FILE" 2>/dev/null || echo 0)
        ;;
esac

# トレーリングカンマ分析（JS/TS）
case "$LANG" in
    javascript|typescript)
        TRAILING_COMMA=$(grep -cE ',\s*$' "$RESOLVED_FILE" 2>/dev/null || echo 0)
        NO_TRAILING_COMMA=$(grep -cE '[^,]\s*[}\]]\s*$' "$RESOLVED_FILE" 2>/dev/null || echo 0)
        ;;
esac

# 規約データを更新（flock排他ロック）
(
    flock -x -w 5 200 || exit 0

    # 既存データを読み込み
    if [ -f "$CONV_FILE" ] && jq empty "$CONV_FILE" 2>/dev/null; then
        EXISTING=$(cat "$CONV_FILE")
    else
        EXISTING='{}'
    fi

    # ファイルカウントチェック（言語あたり100件制限）
    CURRENT_COUNT=$(printf '%s' "$EXISTING" | jq --arg lang "$LANG" '.[$lang].files_analyzed // 0' 2>/dev/null || echo 0)
    if [ "$CURRENT_COUNT" -ge 100 ]; then
        exit 0
    fi

    # 既存の値に加算
    TMPFILE=$(mktemp "${CONV_FILE}.XXXXXX")
    printf '%s' "$EXISTING" | jq \
        --arg lang "$LANG" \
        --argjson indent_spaces "$INDENT_SPACES" \
        --argjson indent_tabs "$INDENT_TABS" \
        --argjson indent_size_2 "$INDENT_SIZE_2" \
        --argjson indent_size_4 "$INDENT_SIZE_4" \
        --argjson single_quotes "$SINGLE_QUOTES" \
        --argjson double_quotes "$DOUBLE_QUOTES" \
        --argjson semicolons "$SEMICOLONS" \
        --argjson no_semicolons "$NO_SEMICOLONS" \
        --argjson camel_case "$CAMEL_CASE" \
        --argjson snake_case "$SNAKE_CASE" \
        --argjson trailing_comma "$TRAILING_COMMA" \
        --argjson no_trailing_comma "$NO_TRAILING_COMMA" \
        '.[$lang] = {
            files_analyzed: ((.[$lang].files_analyzed // 0) + 1),
            indent_spaces: ((.[$lang].indent_spaces // 0) + $indent_spaces),
            indent_tabs: ((.[$lang].indent_tabs // 0) + $indent_tabs),
            indent_size_2: ((.[$lang].indent_size_2 // 0) + $indent_size_2),
            indent_size_4: ((.[$lang].indent_size_4 // 0) + $indent_size_4),
            single_quotes: ((.[$lang].single_quotes // 0) + $single_quotes),
            double_quotes: ((.[$lang].double_quotes // 0) + $double_quotes),
            semicolons: ((.[$lang].semicolons // 0) + $semicolons),
            no_semicolons: ((.[$lang].no_semicolons // 0) + $no_semicolons),
            camel_case: ((.[$lang].camel_case // 0) + $camel_case),
            snake_case: ((.[$lang].snake_case // 0) + $snake_case),
            trailing_comma: ((.[$lang].trailing_comma // 0) + $trailing_comma),
            no_trailing_comma: ((.[$lang].no_trailing_comma // 0) + $no_trailing_comma)
        }' > "$TMPFILE" && mv "$TMPFILE" "$CONV_FILE"

) 200>"${CONV_FILE}.lock"

exit 0
