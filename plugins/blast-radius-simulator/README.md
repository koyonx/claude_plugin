# blast-radius-simulator

破壊的コマンドの実行前に影響範囲をシミュレーション表示するプラグイン。

## 検出対象

| カテゴリ | コマンド |
|---------|---------|
| ファイル削除 | `rm`, `rm -rf` — 対象ファイル数・サイズを表示 |
| Git破壊操作 | `git reset --hard` — 失われる変更行数を表示 |
| Git強制Push | `git push --force` — 上書きされるコミット数を表示 |
| Git Clean | `git clean -f` — 削除される未追跡ファイル数 |
| Git変更破棄 | `git checkout -- .` / `git restore .` — 失われる変更量 |
| SQL | `DROP TABLE/DATABASE`, `TRUNCATE`, `DELETE FROM`(WHERE無し) |
| Docker | `docker system prune`, `docker rm -f` |
| Kubernetes | `kubectl delete` — 削除リソースを表示 |

## 動作

- コマンド実行前（PreToolUse）に影響をシミュレーション
- 実際にはブロックしない（情報提供のみ）
- Claude にはユーザー確認を推奨するコンテキストを注入
- ユーザーには stderr 経由で警告表示

## フック

| イベント | トリガー |
|---------|---------|
| PreToolUse(Bash) | 破壊的コマンド検出時に影響分析 |
