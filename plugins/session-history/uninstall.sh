#!/bin/bash
# session-history プラグインのアンインストールスクリプト
# Claude Codeの設定ファイルからhooksを削除する
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOKS_DIR="${SCRIPT_DIR}/hooks"
SETTINGS_FILE="$HOME/.claude/settings.json"

if [ ! -f "$SETTINGS_FILE" ]; then
    echo "Settings file not found. Nothing to uninstall."
    exit 0
fi

python3 - "$SETTINGS_FILE" "$HOOKS_DIR" <<'PYTHON_SCRIPT'
import json
import sys

settings_file = sys.argv[1]
hooks_dir = sys.argv[2]

try:
    with open(settings_file, "r") as f:
        settings = json.load(f)
except (json.JSONDecodeError, OSError) as e:
    print(f"Failed to read settings: {e}")
    sys.exit(1)

if "hooks" not in settings:
    print("No hooks found. Nothing to uninstall.")
    sys.exit(0)

removed = []
for event in list(settings["hooks"].keys()):
    entries = settings["hooks"][event]
    filtered = []
    for entry in entries:
        keep = True
        for hook in entry.get("hooks", []):
            if hooks_dir in hook.get("command", ""):
                keep = False
                break
        if keep:
            filtered.append(entry)
        else:
            removed.append(event)
    if filtered:
        settings["hooks"][event] = filtered
    else:
        del settings["hooks"][event]

if not settings["hooks"]:
    del settings["hooks"]

with open(settings_file, "w") as f:
    json.dump(settings, f, indent=4, ensure_ascii=False)

if removed:
    print(f"Removed hooks for: {', '.join(set(removed))}")
else:
    print("No session-history hooks found to remove.")
PYTHON_SCRIPT

echo ""
echo "=== session-history plugin uninstalled ==="
echo "Note: Session logs in ~/.claude/session-history/ are preserved."
echo "Delete them manually if no longer needed."
