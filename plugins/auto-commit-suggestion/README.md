# auto-commit-suggestion

ファイル変更が一定数に達したら、gitコミットを提案するプラグイン。

作業中のコード消失を防ぎます。

## 機能

- `PostToolUse` hookでWrite/Editによるファイル変更を追跡
- 変更数が閾値（デフォルト5）に達したらコミットを提案
- `git commit` を検出するとカウンターをリセット

## インストール

```bash
claude --plugin-dir ./plugins/auto-commit-suggestion
```

## 設定

環境変数 `AUTO_COMMIT_THRESHOLD` でコミット提案の閾値を変更できます（デフォルト: 5）。

## 保存先

- カウンターファイル: `~/.claude/auto-commit-suggestion/<session_id>.count`

## 依存関係

- jq
