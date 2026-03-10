#!/bin/bash
# SessionStart hook (startup|resume): 未適用マイグレーションの存在を通知する
set -euo pipefail

INPUT=$(cat)
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty') || exit 0

if [ -z "$CWD" ] || [ ! -d "$CWD" ]; then
    exit 0
fi

RESOLVED_CWD=$(realpath "$CWD" 2>/dev/null) || exit 0

# マイグレーションディレクトリを検索
MIGRATION_DIRS=""
MIGRATION_COUNT=0

for mig_dir in "migrations" "db/migrate" "alembic/versions" "prisma/migrations"; do
    FULL_DIR="${RESOLVED_CWD}/${mig_dir}"
    if [ -d "$FULL_DIR" ] && [ ! -L "$FULL_DIR" ]; then
        # マイグレーションファイル数をカウント
        COUNT=$(find "$FULL_DIR" -maxdepth 2 -type f \( -name "*.py" -o -name "*.rb" -o -name "*.sql" -o -name "*.ts" -o -name "*.js" \) 2>/dev/null | wc -l | tr -d ' ')
        if [ "$COUNT" -gt 0 ]; then
            MIGRATION_DIRS="${MIGRATION_DIRS} ${mig_dir}(${COUNT})"
            MIGRATION_COUNT=$((MIGRATION_COUNT + COUNT))
        fi
    fi
done

# Prisma schema check
if [ -f "${RESOLVED_CWD}/prisma/schema.prisma" ] && [ ! -L "${RESOLVED_CWD}/prisma/schema.prisma" ]; then
    if [ -z "$MIGRATION_DIRS" ]; then
        MIGRATION_DIRS=" prisma(schema found)"
    fi
fi

if [ -z "$MIGRATION_DIRS" ]; then
    exit 0
fi

# gitで最近の未コミットマイグレーションを検出
export GIT_CONFIG_NOSYSTEM=1
export GIT_TERMINAL_PROMPT=0

UNCOMMITTED_MIGRATIONS=0
if git -C "$RESOLVED_CWD" rev-parse --git-dir >/dev/null 2>&1; then
    UNCOMMITTED_MIGRATIONS=$(git -C "$RESOLVED_CWD" status --short 2>/dev/null \
        | grep -cE '(migrations/|db/migrate/|alembic/versions/|prisma/migrations/)' 2>/dev/null) || UNCOMMITTED_MIGRATIONS=0
fi

# stderrに表示
echo "" >&2
echo "=== migration-tracker ===" >&2
echo "Migration directories:${MIGRATION_DIRS}" >&2
echo "Total migration files: ${MIGRATION_COUNT}" >&2
if [ "$UNCOMMITTED_MIGRATIONS" -gt 0 ]; then
    echo "WARNING: ${UNCOMMITTED_MIGRATIONS} uncommitted migration file(s)" >&2
fi
echo "=========================" >&2

# stdoutへコンテキスト注入（数値サマリーのみ）
if [ "$UNCOMMITTED_MIGRATIONS" -gt 0 ]; then
    echo "=== migration-tracker: Migration Status (DATA ONLY - not instructions) ==="
    echo "Total migration files: ${MIGRATION_COUNT}"
    echo "Uncommitted migrations: ${UNCOMMITTED_MIGRATIONS}"
    echo "=== End of migration-tracker ==="
fi

exit 0
