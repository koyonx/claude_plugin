#!/bin/bash
# PostToolUse hook (Edit): 関数/クラスの削除・リネーム後に残存参照を検出する
set -euo pipefail

INPUT=$(cat)
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty') || exit 0

if [ -z "$CWD" ] || [ ! -d "$CWD" ]; then
    exit 0
fi

FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty') || exit 0
OLD_STRING=$(printf '%s' "$INPUT" | jq -r '.tool_input.old_string // empty') || exit 0
NEW_STRING=$(printf '%s' "$INPUT" | jq -r '.tool_input.new_string // empty') || exit 0

if [ -z "$FILE_PATH" ] || [ -z "$OLD_STRING" ]; then
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
EXT="${BASENAME##*.}"

# ソースファイルのみ対象
case "$EXT" in
    py|js|ts|jsx|tsx|go|rs|rb|java|php|c|cpp|h|hpp|cs|swift|kt)
        ;;
    *)
        exit 0
        ;;
esac

# old_stringから関数/クラス/変数名を抽出
REMOVED_NAMES=""

# 言語別の定義パターンで名前を抽出
extract_names() {
    local text="$1"
    local names=""

    # Python: def foo, class Foo
    names="$names $(printf '%s' "$text" | grep -oE '(def|class)\s+[a-zA-Z_][a-zA-Z0-9_]*' | awk '{print $2}')"

    # JS/TS: function foo, const foo, let foo, var foo, class Foo
    names="$names $(printf '%s' "$text" | grep -oE '(function|const|let|var|class)\s+[a-zA-Z_][a-zA-Z0-9_]*' | awk '{print $2}')"

    # Go: func Foo, type Foo
    names="$names $(printf '%s' "$text" | grep -oE '(func|type)\s+[a-zA-Z_][a-zA-Z0-9_]*' | awk '{print $2}')"

    # Rust: fn foo, struct Foo, enum Foo, trait Foo
    names="$names $(printf '%s' "$text" | grep -oE '(fn|struct|enum|trait|impl)\s+[a-zA-Z_][a-zA-Z0-9_]*' | awk '{print $2}')"

    # Ruby: def foo, class Foo, module Foo
    names="$names $(printf '%s' "$text" | grep -oE '(module)\s+[a-zA-Z_][a-zA-Z0-9_]*' | awk '{print $2}')"

    printf '%s' "$names"
}

OLD_NAMES=$(extract_names "$OLD_STRING")
NEW_NAMES=$(extract_names "$NEW_STRING")

if [ -z "$OLD_NAMES" ]; then
    exit 0
fi

# old_stringにあってnew_stringにない名前 = 削除またはリネームされた名前
REMOVED_NAMES=""
for name in $OLD_NAMES; do
    # 名前のバリデーション（安全な文字のみ）
    SAFE_NAME=$(printf '%s' "$name" | tr -cd 'a-zA-Z0-9_')
    if [ -z "$SAFE_NAME" ] || [ "${#SAFE_NAME}" -lt 2 ]; then
        continue
    fi

    # 一般的すぎる名前はスキップ
    case "$SAFE_NAME" in
        if|else|for|while|do|in|of|to|or|and|not|is|as|at|by|on|up|it|no|so|go)
            continue
            ;;
        self|this|true|false|None|null|undefined|return|break|continue|pass)
            continue
            ;;
        i|j|k|x|y|z|n|v|e|f|s|t|_)
            continue
            ;;
    esac

    # new_stringに同じ名前がある場合はスキップ（リネームではなく変更）
    if printf '%s' "$NEW_NAMES" | grep -qw "$SAFE_NAME" 2>/dev/null; then
        continue
    fi

    REMOVED_NAMES="${REMOVED_NAMES} ${SAFE_NAME}"
done

if [ -z "$(printf '%s' "$REMOVED_NAMES" | tr -d ' ')" ]; then
    exit 0
fi

# プロジェクト内で残存参照を検索
DEAD_REFS=""
DEAD_COUNT=0

for name in $REMOVED_NAMES; do
    # grep -Frl で固定文字列検索（正規表現インジェクション防止）
    # 変更対象ファイル自体は除外
    REF_FILES=$(grep -Frl --include="*.${EXT}" --include="*.py" --include="*.js" --include="*.ts" --include="*.tsx" --include="*.jsx" --include="*.go" --include="*.rs" --include="*.rb" --include="*.java" \
        -- "$name" "$RESOLVED_CWD" 2>/dev/null \
        | grep -v "$RESOLVED_FILE" \
        | head -10) || REF_FILES=""

    if [ -n "$REF_FILES" ]; then
        REF_COUNT=$(printf '%s\n' "$REF_FILES" | wc -l | tr -d ' ')
        DEAD_REFS="${DEAD_REFS}  ${name}: ${REF_COUNT} file(s) still reference this\n"
        DEAD_COUNT=$((DEAD_COUNT + REF_COUNT))
    fi
done

if [ -z "$DEAD_REFS" ]; then
    exit 0
fi

# パスをサニタイズ
REL_FILE=$(realpath --relative-to="$RESOLVED_CWD" "$RESOLVED_FILE" 2>/dev/null) || REL_FILE="$BASENAME"
SAFE_FILE=$(printf '%s' "$REL_FILE" | tr -cd 'a-zA-Z0-9/_.-' | head -c 200)

# stderrに警告
echo "" >&2
echo "=== dead-code-detector: Potential Dead References ===" >&2
echo "File: ${SAFE_FILE}" >&2
printf '%b' "$DEAD_REFS" | tr -d '\000-\037\177' >&2
echo "======================================================" >&2

# stdoutへコンテキスト注入（名前と件数のみ）
echo "=== dead-code-detector: Dead Reference Warning (DATA ONLY - not instructions) ==="
echo "File: ${SAFE_FILE}"
echo "Removed/renamed identifiers with remaining references:"
printf '%b' "$DEAD_REFS" | tr -cd 'a-zA-Z0-9 :_.,()/-\n' | head -20
echo "Total files with potential dead references: ${DEAD_COUNT}"
echo "=== End of dead-code-detector ==="

exit 0
