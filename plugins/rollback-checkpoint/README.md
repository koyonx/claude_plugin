# rollback-checkpoint

明示的チェックポイントを保存し、ワンコマンドで作業状態を復元するプラグイン。

## 機能

- **チェックポイント保存**: git diff + 未追跡ファイルを丸ごとスナップショット
- **ワンコマンド復元**: コミット・差分・未追跡ファイルを一括リストア
- プロジェクトごとに最大20チェックポイント

## コマンド

| コマンド | 説明 |
|---------|------|
| `/checkpoint save [name]` | 現在の作業状態を保存 |
| `/checkpoint restore name` | チェックポイントを復元 |
| `/checkpoint list` | 保存済みチェックポイント一覧 |
| `/checkpoint delete name` | チェックポイントを削除 |

## 保存内容

- 現在のコミットハッシュ・ブランチ名
- 未コミット変更（`git diff HEAD`）
- ステージ済み変更（`git diff --cached`）
- 未追跡ファイル（tarアーカイブ）

## データ保存先

`~/.claude/rollback-checkpoint/`
