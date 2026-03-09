#!/bin/bash
# PostToolUse hook (Write|Edit): 変更されたファイルからTODO/FIXME/HACKコメントを検出・記録する
set -euo pipefail

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty') || exit 0
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty') || exit 0
CWD=$(echo "$INPUT" | jq -r '.cwd // empty') || exit 0

if [ -z "$TOOL_NAME" ] || [ -z "$FILE_PATH" ]; then
    exit 0
fi

# Write/Edit以外はスキップ
if [ "$TOOL_NAME" != "Write" ] && [ "$TOOL_NAME" != "Edit" ]; then
    exit 0
fi

# ファイルが存在しない場合（削除された等）はスキップ
if [ ! -f "$FILE_PATH" ]; then
    exit 0
fi

# ファイルパスの検証: CWD配下であることを確認
if [ -n "$CWD" ]; then
    RESOLVED_FILE=$(realpath "$FILE_PATH" 2>/dev/null) || exit 0
    RESOLVED_CWD=$(realpath "$CWD" 2>/dev/null) || exit 0
    case "$RESOLVED_FILE" in
        "$RESOLVED_CWD"/*)
            ;;
        *)
            exit 0
            ;;
    esac
fi

# バイナリファイルはスキップ
if file --brief --mime-type "$FILE_PATH" 2>/dev/null | grep -qv '^text/'; then
    exit 0
fi

# ファイルサイズ制限 (1MB)
MAX_SIZE=$((1 * 1024 * 1024))
FILE_SIZE=$(stat -f%z "$FILE_PATH" 2>/dev/null || stat -c%s "$FILE_PATH" 2>/dev/null || echo 999999999)
if [ "$FILE_SIZE" -gt "$MAX_SIZE" ]; then
    exit 0
fi

# TODO/FIXME/HACKパターンを検出
MARKERS="TODO|FIXME|HACK|XXX"
MATCHES=$(grep -n -i -E "(${MARKERS})[[:space:]:]" "$FILE_PATH" 2>/dev/null || true)

if [ -z "$MATCHES" ]; then
    exit 0
fi

# 保存ディレクトリ
DATA_DIR="$HOME/.claude/todo-tracker"
mkdir -p "$DATA_DIR"

# プロジェクト名をCWDから生成
PROJECT_NAME="default"
if [ -n "$CWD" ]; then
    PROJECT_NAME=$(echo "$CWD" | tr -cd 'a-zA-Z0-9/_.-' | sed 's|/|_|g' | sed 's|^_||')
fi
if [ -z "$PROJECT_NAME" ]; then
    PROJECT_NAME="default"
fi

TODO_FILE="${DATA_DIR}/${PROJECT_NAME}.json"

# 既存のTODOデータを読み込み
if [ -f "$TODO_FILE" ]; then
    EXISTING=$(cat "$TODO_FILE" 2>/dev/null) || EXISTING="[]"
    # JSONとして有効か確認
    if ! echo "$EXISTING" | jq empty 2>/dev/null; then
        EXISTING="[]"
    fi
else
    EXISTING="[]"
fi

# このファイルの既存エントリを削除（再スキャン結果で置換）
SAFE_FILE_PATH=$(echo "$FILE_PATH" | tr -cd 'a-zA-Z0-9/_. -')
EXISTING=$(echo "$EXISTING" | jq --arg fp "$FILE_PATH" '[.[] | select(.file != $fp)]')

# 新しいTODOエントリを追加
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
while IFS= read -r line; do
    LINE_NUM=$(echo "$line" | cut -d: -f1)
    LINE_CONTENT=$(echo "$line" | cut -d: -f2-)
    # マーカー種別を判定
    MARKER_TYPE=$(echo "$LINE_CONTENT" | grep -o -i -E "(TODO|FIXME|HACK|XXX)" | head -1 | tr '[:lower:]' '[:upper:]')
    # 内容をサニタイズ（制御文字・HTMLタグ除去、200文字制限）
    CLEAN_CONTENT=$(echo "$LINE_CONTENT" | sed 's/<[^>]*>//g' | tr -d '\000-\010\013\014\016-\037\177' | head -c 200)

    EXISTING=$(echo "$EXISTING" | jq \
        --arg file "$FILE_PATH" \
        --arg line "$LINE_NUM" \
        --arg content "$CLEAN_CONTENT" \
        --arg marker "$MARKER_TYPE" \
        --arg ts "$TIMESTAMP" \
        '. + [{"file": $file, "line": ($line | tonumber), "content": $content, "marker": $marker, "found_at": $ts}]')
done <<< "$MATCHES"

# 最大500エントリに制限
ENTRY_COUNT=$(echo "$EXISTING" | jq 'length')
if [ "$ENTRY_COUNT" -gt 500 ]; then
    EXISTING=$(echo "$EXISTING" | jq '.[-500:]')
fi

echo "$EXISTING" | jq '.' > "$TODO_FILE"

# 新しく見つかったTODO数を表示
NEW_COUNT=$(echo "$MATCHES" | wc -l | tr -d ' ')
echo "" >&2
echo "=== todo-tracker ===" >&2
echo "Found ${NEW_COUNT} TODO/FIXME marker(s) in $(basename "$FILE_PATH")" >&2
echo "====================" >&2

exit 0
