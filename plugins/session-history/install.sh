#!/bin/bash
# session-history プラグインのインストールスクリプト
# Claude Codeの設定ファイルにhooksを追加する
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOKS_DIR="${SCRIPT_DIR}/hooks"
SETTINGS_FILE="$HOME/.claude/settings.json"

# hooksスクリプトに実行権限を付与
chmod +x "${HOOKS_DIR}/backup-before-compact.sh"
chmod +x "${HOOKS_DIR}/save-session.sh"
chmod +x "${HOOKS_DIR}/on-session-start.sh"

# バックアップディレクトリを作成
mkdir -p "$HOME/.claude/session-history/sessions"
mkdir -p "$HOME/.claude/session-history/compaction-backups"

# python3で既存設定とhooks設定をマージ
python3 - "$SETTINGS_FILE" "$HOOKS_DIR" <<'PYTHON_SCRIPT'
import json
import sys

settings_file = sys.argv[1]
hooks_dir = sys.argv[2]

try:
    with open(settings_file, "r") as f:
        settings = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    settings = {}

hooks_config = {
    "PreCompact": [
        {
            "matcher": "",
            "hooks": [
                {
                    "type": "command",
                    "command": f"{hooks_dir}/backup-before-compact.sh"
                }
            ]
        }
    ],
    "Stop": [
        {
            "matcher": "",
            "hooks": [
                {
                    "type": "command",
                    "command": f"{hooks_dir}/save-session.sh"
                }
            ]
        }
    ],
    "SessionStart": [
        {
            "matcher": "startup|resume",
            "hooks": [
                {
                    "type": "command",
                    "command": f"{hooks_dir}/on-session-start.sh"
                }
            ]
        }
    ]
}

# 既存のhooksとマージ
if "hooks" not in settings:
    settings["hooks"] = {}

for event, config in hooks_config.items():
    if event not in settings["hooks"]:
        settings["hooks"][event] = config
    else:
        # 既に同じコマンドがあるか確認
        existing_commands = set()
        for entry in settings["hooks"][event]:
            for hook in entry.get("hooks", []):
                existing_commands.add(hook.get("command", ""))

        for entry in config:
            for hook in entry.get("hooks", []):
                if hook.get("command", "") not in existing_commands:
                    settings["hooks"][event].append(entry)
                    break

with open(settings_file, "w") as f:
    json.dump(settings, f, indent=4, ensure_ascii=False)

print(f"Hooks configuration written to {settings_file}")
PYTHON_SCRIPT

echo ""
echo "=== session-history plugin installed ==="
echo ""
echo "Hooks registered:"
echo "  - PreCompact  : Backs up transcript before compaction"
echo "  - Stop        : Saves session log as readable Markdown"
echo "  - SessionStart: Shows path to previous session log"
echo ""
echo "Session logs: ~/.claude/session-history/sessions/"
echo "Compaction backups: ~/.claude/session-history/compaction-backups/"
