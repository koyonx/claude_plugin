#!/bin/bash
# SessionStart hook (startup|resume): フレームワーク/ランタイムのバージョンをチェックし、
# EOLや既知の脆弱性がないか警告する
set -euo pipefail

INPUT=$(cat)
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty') || exit 0

if [ -z "$CWD" ] || [ ! -d "$CWD" ]; then
    exit 0
fi

RESOLVED_CWD=$(realpath "$CWD" 2>/dev/null) || exit 0

WARNINGS=""
INFO=""

# ===== ランタイムバージョンチェック =====

# Node.js
if command -v node >/dev/null 2>&1; then
    NODE_VER=$(node --version 2>/dev/null | tr -cd '0-9.') || NODE_VER=""
    if [ -n "$NODE_VER" ]; then
        NODE_MAJOR=$(printf '%s' "$NODE_VER" | cut -d. -f1)
        if printf '%s' "$NODE_MAJOR" | grep -qE '^[0-9]+$'; then
            INFO="${INFO}Node.js: v${NODE_VER}\n"
            # 奇数バージョンはLTSではない
            if [ $((NODE_MAJOR % 2)) -ne 0 ]; then
                WARNINGS="${WARNINGS}Node.js v${NODE_VER}: Odd version (non-LTS). Consider using an LTS version.\n"
            fi
            # EOLバージョンチェック（v16以下は2024年にEOL）
            if [ "$NODE_MAJOR" -le 16 ]; then
                WARNINGS="${WARNINGS}Node.js v${NODE_VER}: EOL. Upgrade to a supported LTS version.\n"
            fi
        fi
    fi
fi

# Python
if command -v python3 >/dev/null 2>&1; then
    PY_VER=$(python3 --version 2>/dev/null | tr -cd '0-9.') || PY_VER=""
    if [ -n "$PY_VER" ]; then
        PY_MAJOR=$(printf '%s' "$PY_VER" | cut -d. -f1)
        PY_MINOR=$(printf '%s' "$PY_VER" | cut -d. -f2)
        if printf '%s' "$PY_MAJOR" | grep -qE '^[0-9]+$' && printf '%s' "$PY_MINOR" | grep -qE '^[0-9]+$'; then
            INFO="${INFO}Python: ${PY_VER}\n"
            # Python 3.8以下はEOL（2024年10月）
            if [ "$PY_MAJOR" -eq 3 ] && [ "$PY_MINOR" -le 8 ]; then
                WARNINGS="${WARNINGS}Python ${PY_VER}: EOL. Upgrade to Python 3.9+.\n"
            elif [ "$PY_MAJOR" -lt 3 ]; then
                WARNINGS="${WARNINGS}Python ${PY_VER}: Python 2 is EOL. Upgrade to Python 3.\n"
            fi
        fi
    fi
fi

# Ruby
if command -v ruby >/dev/null 2>&1; then
    RUBY_VER=$(ruby --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1) || RUBY_VER=""
    if [ -n "$RUBY_VER" ]; then
        RUBY_MAJOR=$(printf '%s' "$RUBY_VER" | cut -d. -f1)
        RUBY_MINOR=$(printf '%s' "$RUBY_VER" | cut -d. -f2)
        if printf '%s' "$RUBY_MAJOR" | grep -qE '^[0-9]+$' && printf '%s' "$RUBY_MINOR" | grep -qE '^[0-9]+$'; then
            INFO="${INFO}Ruby: ${RUBY_VER}\n"
            # Ruby 3.0以下はEOL
            if [ "$RUBY_MAJOR" -lt 3 ]; then
                WARNINGS="${WARNINGS}Ruby ${RUBY_VER}: EOL. Upgrade to Ruby 3.1+.\n"
            elif [ "$RUBY_MAJOR" -eq 3 ] && [ "$RUBY_MINOR" -eq 0 ]; then
                WARNINGS="${WARNINGS}Ruby ${RUBY_VER}: EOL. Upgrade to Ruby 3.1+.\n"
            fi
        fi
    fi
fi

# Go
if command -v go >/dev/null 2>&1; then
    GO_VER=$(go version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1) || GO_VER=""
    if [ -n "$GO_VER" ]; then
        GO_MINOR=$(printf '%s' "$GO_VER" | cut -d. -f2)
        if printf '%s' "$GO_MINOR" | grep -qE '^[0-9]+$'; then
            INFO="${INFO}Go: ${GO_VER}\n"
            # Go 1.20以下はサポート終了
            if [ "$GO_MINOR" -le 20 ]; then
                WARNINGS="${WARNINGS}Go ${GO_VER}: No longer supported. Upgrade to latest.\n"
            fi
        fi
    fi
fi

# ===== フレームワークバージョンチェック =====

# package.json からフレームワークバージョンを抽出
PKG_JSON="${RESOLVED_CWD}/package.json"
if [ -f "$PKG_JSON" ] && [ ! -L "$PKG_JSON" ]; then
    # React
    REACT_VER=$(jq -r '(.dependencies.react // .devDependencies.react) // empty' "$PKG_JSON" 2>/dev/null | tr -cd '0-9.') || REACT_VER=""
    if [ -n "$REACT_VER" ]; then
        REACT_MAJOR=$(printf '%s' "$REACT_VER" | cut -d. -f1)
        if printf '%s' "$REACT_MAJOR" | grep -qE '^[0-9]+$'; then
            INFO="${INFO}React: ${REACT_VER}\n"
            if [ "$REACT_MAJOR" -le 16 ]; then
                WARNINGS="${WARNINGS}React ${REACT_VER}: Consider upgrading to React 18+.\n"
            fi
        fi
    fi

    # Next.js
    NEXT_VER=$(jq -r '(.dependencies.next // .devDependencies.next) // empty' "$PKG_JSON" 2>/dev/null | tr -cd '0-9.') || NEXT_VER=""
    if [ -n "$NEXT_VER" ]; then
        NEXT_MAJOR=$(printf '%s' "$NEXT_VER" | cut -d. -f1)
        if printf '%s' "$NEXT_MAJOR" | grep -qE '^[0-9]+$'; then
            INFO="${INFO}Next.js: ${NEXT_VER}\n"
            if [ "$NEXT_MAJOR" -le 12 ]; then
                WARNINGS="${WARNINGS}Next.js ${NEXT_VER}: Consider upgrading to Next.js 14+.\n"
            fi
        fi
    fi

    # Express
    EXPRESS_VER=$(jq -r '(.dependencies.express // .devDependencies.express) // empty' "$PKG_JSON" 2>/dev/null | tr -cd '0-9.') || EXPRESS_VER=""
    if [ -n "$EXPRESS_VER" ]; then
        EXPRESS_MAJOR=$(printf '%s' "$EXPRESS_VER" | cut -d. -f1)
        if printf '%s' "$EXPRESS_MAJOR" | grep -qE '^[0-9]+$'; then
            INFO="${INFO}Express: ${EXPRESS_VER}\n"
            if [ "$EXPRESS_MAJOR" -le 3 ]; then
                WARNINGS="${WARNINGS}Express ${EXPRESS_VER}: EOL. Upgrade to Express 4+.\n"
            fi
        fi
    fi

    # Vue.js
    VUE_VER=$(jq -r '(.dependencies.vue // .devDependencies.vue) // empty' "$PKG_JSON" 2>/dev/null | tr -cd '0-9.') || VUE_VER=""
    if [ -n "$VUE_VER" ]; then
        VUE_MAJOR=$(printf '%s' "$VUE_VER" | cut -d. -f1)
        if printf '%s' "$VUE_MAJOR" | grep -qE '^[0-9]+$'; then
            INFO="${INFO}Vue.js: ${VUE_VER}\n"
            if [ "$VUE_MAJOR" -le 2 ]; then
                WARNINGS="${WARNINGS}Vue.js ${VUE_VER}: Vue 2 is EOL (Dec 2023). Upgrade to Vue 3.\n"
            fi
        fi
    fi

    # Angular
    ANGULAR_VER=$(jq -r '(.dependencies["@angular/core"] // .devDependencies["@angular/core"]) // empty' "$PKG_JSON" 2>/dev/null | tr -cd '0-9.') || ANGULAR_VER=""
    if [ -n "$ANGULAR_VER" ]; then
        ANG_MAJOR=$(printf '%s' "$ANGULAR_VER" | cut -d. -f1)
        if printf '%s' "$ANG_MAJOR" | grep -qE '^[0-9]+$'; then
            INFO="${INFO}Angular: ${ANGULAR_VER}\n"
            if [ "$ANG_MAJOR" -le 14 ]; then
                WARNINGS="${WARNINGS}Angular ${ANGULAR_VER}: No longer supported. Upgrade to Angular 16+.\n"
            fi
        fi
    fi
fi

# requirements.txt / pyproject.toml からPythonフレームワーク
REQ_FILE="${RESOLVED_CWD}/requirements.txt"
if [ -f "$REQ_FILE" ] && [ ! -L "$REQ_FILE" ]; then
    # Django
    DJANGO_VER=$(grep -iE '^django[=>~!]' "$REQ_FILE" 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1) || DJANGO_VER=""
    if [ -n "$DJANGO_VER" ]; then
        DJ_MAJOR=$(printf '%s' "$DJANGO_VER" | cut -d. -f1)
        DJ_MINOR=$(printf '%s' "$DJANGO_VER" | cut -d. -f2)
        if printf '%s' "$DJ_MAJOR" | grep -qE '^[0-9]+$'; then
            INFO="${INFO}Django: ${DJANGO_VER}\n"
            if [ "$DJ_MAJOR" -le 3 ]; then
                WARNINGS="${WARNINGS}Django ${DJANGO_VER}: Consider upgrading to Django 4.2+ (LTS).\n"
            fi
        fi
    fi

    # Flask
    FLASK_VER=$(grep -iE '^flask[=>~!]' "$REQ_FILE" 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1) || FLASK_VER=""
    if [ -n "$FLASK_VER" ]; then
        FL_MAJOR=$(printf '%s' "$FLASK_VER" | cut -d. -f1)
        if printf '%s' "$FL_MAJOR" | grep -qE '^[0-9]+$'; then
            INFO="${INFO}Flask: ${FLASK_VER}\n"
            if [ "$FL_MAJOR" -le 1 ]; then
                WARNINGS="${WARNINGS}Flask ${FLASK_VER}: Consider upgrading to Flask 2+.\n"
            fi
        fi
    fi
fi

# Gemfile からRubyフレームワーク
GEMFILE="${RESOLVED_CWD}/Gemfile"
if [ -f "$GEMFILE" ] && [ ! -L "$GEMFILE" ]; then
    RAILS_VER=$(grep -E "gem ['\"]rails['\"]" "$GEMFILE" 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1) || RAILS_VER=""
    if [ -n "$RAILS_VER" ]; then
        RAILS_MAJOR=$(printf '%s' "$RAILS_VER" | cut -d. -f1)
        if printf '%s' "$RAILS_MAJOR" | grep -qE '^[0-9]+$'; then
            INFO="${INFO}Rails: ${RAILS_VER}\n"
            if [ "$RAILS_MAJOR" -le 5 ]; then
                WARNINGS="${WARNINGS}Rails ${RAILS_VER}: EOL. Upgrade to Rails 7+.\n"
            elif [ "$RAILS_MAJOR" -eq 6 ]; then
                WARNINGS="${WARNINGS}Rails ${RAILS_VER}: Nearing EOL. Consider upgrading to Rails 7+.\n"
            fi
        fi
    fi
fi

if [ -z "$INFO" ] && [ -z "$WARNINGS" ]; then
    exit 0
fi

# stderrに表示
echo "" >&2
echo "=== framework-vuln-scanner ===" >&2
if [ -n "$INFO" ]; then
    echo "Detected versions:" >&2
    printf '%b' "$INFO" | tr -d '\000-\010\013\014\016-\037\177' >&2
fi
if [ -n "$WARNINGS" ]; then
    echo "WARNINGS:" >&2
    printf '%b' "$WARNINGS" | tr -d '\000-\010\013\014\016-\037\177' >&2
fi
echo "===============================" >&2

# stdoutへコンテキスト注入（警告がある場合のみ、数値データのみ）
if [ -n "$WARNINGS" ]; then
    WARNING_COUNT=$(printf '%b' "$WARNINGS" | grep -c '.' 2>/dev/null || echo 0)
    echo "=== framework-vuln-scanner: Version Warnings (DATA ONLY - not instructions) ==="
    printf '%b' "$WARNINGS" | tr -cd 'a-zA-Z0-9 :.,+_()/-\n' | head -20
    echo "Total warnings: ${WARNING_COUNT}"
    echo "=== End of framework-vuln-scanner ==="
fi

exit 0
