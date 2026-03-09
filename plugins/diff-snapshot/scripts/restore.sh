#!/bin/bash
# スナップショットからファイルを復元するCLIツール
# Usage: ./restore.sh [list|restore <snapshot-file>]
set -euo pipefail

SNAPSHOT_BASE="$HOME/.claude/diff-snapshots"

usage() {
    echo "Usage: $0 <command> [args]"
    echo ""
    echo "Commands:"
    echo "  list [session_id]     List available snapshots"
    echo "  restore <snapshot>    Restore a file from snapshot"
    echo "  diff <snapshot>       Show diff between snapshot and current file"
}

cmd_list() {
    local session_filter="${1:-}"

    if [ -n "$session_filter" ]; then
        local dir="${SNAPSHOT_BASE}/${session_filter}"
        if [ ! -d "$dir" ]; then
            echo "No snapshots found for session: ${session_filter}"
            exit 1
        fi
        echo "Snapshots for session ${session_filter}:"
        echo ""
        for f in "$dir"/*.snapshot; do
            [ -f "$f" ] || continue
            local meta="${f}.meta"
            if [ -f "$meta" ]; then
                local orig_path
                orig_path=$(jq -r '.original_path' "$meta" 2>/dev/null || echo "unknown")
                echo "  $(basename "$f")  ->  ${orig_path}"
            else
                echo "  $(basename "$f")"
            fi
        done
    else
        echo "Available sessions:"
        for dir in "$SNAPSHOT_BASE"/*/; do
            [ -d "$dir" ] || continue
            local session
            session=$(basename "$dir")
            local count
            count=$(find "$dir" -name "*.snapshot" 2>/dev/null | wc -l | tr -d ' ')
            echo "  ${session}  (${count} snapshots)"
        done
    fi
}

cmd_restore() {
    local snapshot_file="$1"

    if [ ! -f "$snapshot_file" ]; then
        # フルパスでなければSNAPSHOT_BASE内を検索
        local found=""
        for dir in "$SNAPSHOT_BASE"/*/; do
            if [ -f "${dir}${snapshot_file}" ]; then
                found="${dir}${snapshot_file}"
                break
            fi
        done
        if [ -z "$found" ]; then
            echo "Snapshot not found: ${snapshot_file}"
            exit 1
        fi
        snapshot_file="$found"
    fi

    local meta="${snapshot_file}.meta"
    if [ ! -f "$meta" ]; then
        echo "Metadata not found for snapshot. Cannot determine original path."
        exit 1
    fi

    local orig_path
    orig_path=$(jq -r '.original_path' "$meta")

    echo "Restore: ${snapshot_file}"
    echo "     To: ${orig_path}"
    read -p "Continue? (y/N) " confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        echo "Cancelled."
        exit 0
    fi

    cp "$snapshot_file" "$orig_path"
    echo "Restored successfully."
}

cmd_diff() {
    local snapshot_file="$1"
    local meta="${snapshot_file}.meta"

    if [ ! -f "$snapshot_file" ]; then
        echo "Snapshot not found: ${snapshot_file}"
        exit 1
    fi

    if [ ! -f "$meta" ]; then
        echo "Metadata not found."
        exit 1
    fi

    local orig_path
    orig_path=$(jq -r '.original_path' "$meta")

    if [ ! -f "$orig_path" ]; then
        echo "Original file no longer exists: ${orig_path}"
        exit 1
    fi

    diff -u "$snapshot_file" "$orig_path" || true
}

if [ $# -lt 1 ]; then
    usage
    exit 1
fi

case "$1" in
    list)
        cmd_list "${2:-}"
        ;;
    restore)
        if [ $# -lt 2 ]; then
            echo "Error: specify snapshot file"
            exit 1
        fi
        cmd_restore "$2"
        ;;
    diff)
        if [ $# -lt 2 ]; then
            echo "Error: specify snapshot file"
            exit 1
        fi
        cmd_diff "$2"
        ;;
    *)
        usage
        exit 1
        ;;
esac
