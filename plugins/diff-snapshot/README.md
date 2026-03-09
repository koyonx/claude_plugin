# diff-snapshot

ファイル変更前後のスナップショットを自動保存し、簡単にロールバックできるプラグイン。

## 機能

| Hook | タイミング | 動作 |
|------|-----------|------|
| `PreToolUse` | Write/Edit実行前 | 変更前のファイルをスナップショットとして保存 |
| `PostToolUse` | Write/Edit実行後 | 変更前後のdiffを保存 |

## インストール

```bash
claude --plugin-dir ./plugins/diff-snapshot
```

## スナップショットの管理

```bash
# スナップショット一覧
./scripts/restore.sh list

# セッション指定で一覧
./scripts/restore.sh list <session_id>

# ファイルを復元
./scripts/restore.sh restore <snapshot-file>

# 差分を確認
./scripts/restore.sh diff <snapshot-file>
```

## 保存先

- スナップショット: `~/.claude/diff-snapshots/<session_id>/`
- 各スナップショットに `.meta` ファイル（元のパス情報）と `.diff` ファイル（差分）が付属

## 制限

- スナップショット対象のファイルサイズ上限: 50MB

## 依存関係

- jq
- diff
