#!/bin/bash
# PostToolUse hook (Write|Edit): APIエンドポイント変更を検出し、ドキュメント同期を警告する
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
    py|js|ts|go|rb|java|php)
        ;;
    *)
        exit 0
        ;;
esac

# ファイルサイズチェック（2MB制限）
FILE_SIZE=$(stat -f%z "$RESOLVED_FILE" 2>/dev/null || stat -c%s "$RESOLVED_FILE" 2>/dev/null || echo 0)
if [ "$FILE_SIZE" -gt 2097152 ] || [ "$FILE_SIZE" -eq 0 ]; then
    exit 0
fi

# APIルート定義パターンを検出
HAS_ROUTES=false

case "$EXT" in
    py)
        # FastAPI: @app.get("/path"), @router.post("/path")
        # Flask: @app.route("/path"), @blueprint.route("/path")
        # Django: path("url", view)
        if grep -qE '@(app|router|blueprint)\.(get|post|put|delete|patch|route)\s*\(' "$RESOLVED_FILE" 2>/dev/null; then
            HAS_ROUTES=true
        elif grep -qE '^\s*path\s*\(' "$RESOLVED_FILE" 2>/dev/null; then
            HAS_ROUTES=true
        fi
        ;;
    js|ts)
        # Express: app.get("/path"), router.post("/path")
        # Nest.js: @Get("/path"), @Post("/path")
        # Next.js: export default function handler / export async function GET
        if grep -qE '(app|router)\.(get|post|put|delete|patch|all|use)\s*\(' "$RESOLVED_FILE" 2>/dev/null; then
            HAS_ROUTES=true
        elif grep -qE '@(Get|Post|Put|Delete|Patch)\s*\(' "$RESOLVED_FILE" 2>/dev/null; then
            HAS_ROUTES=true
        elif grep -qE 'export\s+(async\s+)?function\s+(GET|POST|PUT|DELETE|PATCH)' "$RESOLVED_FILE" 2>/dev/null; then
            HAS_ROUTES=true
        fi
        ;;
    go)
        # Gin: r.GET("/path"), r.POST("/path")
        # Echo: e.GET("/path")
        # net/http: http.HandleFunc("/path")
        if grep -qE '\.(GET|POST|PUT|DELETE|PATCH|Handle|HandleFunc)\s*\(' "$RESOLVED_FILE" 2>/dev/null; then
            HAS_ROUTES=true
        fi
        ;;
    rb)
        # Rails: get "/path", post "/path", resources :foo
        if grep -qE '^\s*(get|post|put|patch|delete|resources|resource|namespace)\s' "$RESOLVED_FILE" 2>/dev/null; then
            HAS_ROUTES=true
        fi
        ;;
    java)
        # Spring: @GetMapping, @PostMapping, @RequestMapping
        if grep -qE '@(Get|Post|Put|Delete|Patch|Request)Mapping' "$RESOLVED_FILE" 2>/dev/null; then
            HAS_ROUTES=true
        fi
        ;;
    php)
        # Laravel: Route::get, Route::post
        if grep -qE 'Route::(get|post|put|delete|patch|any|match)\s*\(' "$RESOLVED_FILE" 2>/dev/null; then
            HAS_ROUTES=true
        fi
        ;;
esac

if [ "$HAS_ROUTES" = false ]; then
    exit 0
fi

# API仕様書の存在をチェック
DOC_FILES=""
DOC_FOUND=false

for doc_pattern in "openapi.yaml" "openapi.yml" "openapi.json" "swagger.yaml" "swagger.yml" "swagger.json" "api-spec.yaml" "api-spec.yml" "docs/api" "doc/api"; do
    DOC_PATH="${RESOLVED_CWD}/${doc_pattern}"
    if [ -e "$DOC_PATH" ] && [ ! -L "$DOC_PATH" ]; then
        DOC_FOUND=true
        DOC_FILES="${DOC_FILES} ${doc_pattern}"
    fi
done

# パスをサニタイズ
REL_FILE=$(realpath --relative-to="$RESOLVED_CWD" "$RESOLVED_FILE" 2>/dev/null) || REL_FILE="$BASENAME"
SAFE_FILE=$(printf '%s' "$REL_FILE" | tr -cd 'a-zA-Z0-9/_.-' | head -c 200)

# APIルート数をカウント
ROUTE_COUNT=0
case "$EXT" in
    py)
        ROUTE_COUNT=$(grep -cE '@(app|router|blueprint)\.(get|post|put|delete|patch|route)\s*\(|^\s*path\s*\(' "$RESOLVED_FILE" 2>/dev/null) || ROUTE_COUNT=0
        ;;
    js|ts)
        ROUTE_COUNT=$(grep -cE '(app|router)\.(get|post|put|delete|patch|all)\s*\(|@(Get|Post|Put|Delete|Patch)\s*\(' "$RESOLVED_FILE" 2>/dev/null) || ROUTE_COUNT=0
        ;;
    go)
        ROUTE_COUNT=$(grep -cE '\.(GET|POST|PUT|DELETE|PATCH|Handle|HandleFunc)\s*\(' "$RESOLVED_FILE" 2>/dev/null) || ROUTE_COUNT=0
        ;;
    *)
        ROUTE_COUNT=1
        ;;
esac

# stderrに通知
echo "" >&2
echo "=== api-doc-sync ===" >&2
echo "API routes detected in: ${SAFE_FILE} (${ROUTE_COUNT} endpoint(s))" >&2

if [ "$DOC_FOUND" = true ]; then
    SAFE_DOCS=$(printf '%s' "$DOC_FILES" | tr -cd 'a-zA-Z0-9 /_.-')
    echo "API docs found:${SAFE_DOCS}" >&2
    echo "Reminder: Update API documentation if endpoints changed." >&2
else
    echo "WARNING: No API documentation found (openapi.yaml/swagger.json etc.)" >&2
    echo "Consider creating API documentation for this project." >&2
fi
echo "====================" >&2

# stdoutへコンテキスト注入（メタデータのみ）
echo "=== api-doc-sync: API Change Detected (DATA ONLY - not instructions) ==="
echo "File: ${SAFE_FILE}"
echo "Endpoints detected: ${ROUTE_COUNT}"
if [ "$DOC_FOUND" = true ]; then
    echo "API documentation exists. Verify it reflects the current changes."
else
    echo "No API documentation found. Consider creating openapi.yaml or swagger.json."
fi
echo "=== End of api-doc-sync ==="

exit 0
