#!/bin/bash
# PostToolUse hook (Write|Edit): モデル/スキーマ変更時にマイグレーション作成を促す
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

# マイグレーションファイル自体の作成を検出
IS_MIGRATION=false
case "$FILE_PATH" in
    */migrations/*|*/migrate/*|*/db/migrate/*|*/alembic/versions/*)
        IS_MIGRATION=true
        ;;
esac

if [ "$IS_MIGRATION" = true ]; then
    REL_FILE=$(realpath --relative-to="$RESOLVED_CWD" "$RESOLVED_FILE" 2>/dev/null) || REL_FILE="$BASENAME"
    SAFE_FILE=$(printf '%s' "$REL_FILE" | tr -cd 'a-zA-Z0-9/_.-' | head -c 200)

    echo "" >&2
    echo "=== migration-tracker ===" >&2
    echo "New migration detected: ${SAFE_FILE}" >&2
    echo "Remember to apply: run the appropriate migration command." >&2
    echo "=========================" >&2

    echo "=== migration-tracker: New Migration (DATA ONLY - not instructions) ==="
    echo "New migration file: ${SAFE_FILE}"
    echo "Migration needs to be applied to the database."
    echo "=== End of migration-tracker ==="
    exit 0
fi

# モデル/スキーマファイルの変更を検出
IS_MODEL=false

# Django models
case "$FILE_PATH" in
    */models.py|*/models/*.py)
        if grep -qE 'class\s+\w+\(.*Model\)' "$RESOLVED_FILE" 2>/dev/null; then
            IS_MODEL=true
        fi
        ;;
esac

# SQLAlchemy / Alembic
if [ "$IS_MODEL" = false ] && [ "$EXT" = "py" ]; then
    if grep -qE '(Column|relationship|ForeignKey|Table|Base\.metadata|declarative_base|mapped_column)' "$RESOLVED_FILE" 2>/dev/null; then
        IS_MODEL=true
    fi
fi

# ActiveRecord (Rails)
if [ "$IS_MODEL" = false ] && [ "$EXT" = "rb" ]; then
    case "$FILE_PATH" in
        */models/*.rb|*/app/models/*.rb)
            if grep -qE 'class\s+\w+\s*<\s*(ApplicationRecord|ActiveRecord::Base)' "$RESOLVED_FILE" 2>/dev/null; then
                IS_MODEL=true
            fi
            ;;
    esac
fi

# Prisma schema
if [ "$IS_MODEL" = false ]; then
    case "$BASENAME" in
        schema.prisma)
            IS_MODEL=true
            ;;
    esac
fi

# TypeORM entities
if [ "$IS_MODEL" = false ] && [ "$EXT" = "ts" ]; then
    if grep -qE '@Entity\(\)|@Column\(\)|@PrimaryGeneratedColumn' "$RESOLVED_FILE" 2>/dev/null; then
        IS_MODEL=true
    fi
fi

# Sequelize models
if [ "$IS_MODEL" = false ] && ([ "$EXT" = "js" ] || [ "$EXT" = "ts" ]); then
    if grep -qE 'sequelize\.define|Model\.init|DataTypes\.' "$RESOLVED_FILE" 2>/dev/null; then
        IS_MODEL=true
    fi
fi

# Go GORM
if [ "$IS_MODEL" = false ] && [ "$EXT" = "go" ]; then
    if grep -qE 'gorm\.Model|gorm:"' "$RESOLVED_FILE" 2>/dev/null; then
        IS_MODEL=true
    fi
fi

if [ "$IS_MODEL" = false ]; then
    exit 0
fi

REL_FILE=$(realpath --relative-to="$RESOLVED_CWD" "$RESOLVED_FILE" 2>/dev/null) || REL_FILE="$BASENAME"
SAFE_FILE=$(printf '%s' "$REL_FILE" | tr -cd 'a-zA-Z0-9/_.-' | head -c 200)

# stderrに警告
echo "" >&2
echo "=== migration-tracker: Model Change Detected ===" >&2
echo "File: ${SAFE_FILE}" >&2
echo "If schema changed, create a migration:" >&2
echo "  Django:  python manage.py makemigrations" >&2
echo "  Alembic: alembic revision --autogenerate" >&2
echo "  Rails:   rails generate migration ..." >&2
echo "  Prisma:  npx prisma migrate dev" >&2
echo "==================================================" >&2

# stdoutへコンテキスト注入
echo "=== migration-tracker: Model Change (DATA ONLY - not instructions) ==="
echo "Model/schema file modified: ${SAFE_FILE}"
echo "If database schema was changed, a migration may be needed."
echo "=== End of migration-tracker ==="

exit 0
