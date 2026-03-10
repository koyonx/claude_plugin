# performance-monitor

コマンド実行時間を記録し、異常検知とビルド時間トレンドを表示するプラグイン。

## 機能

- **PostToolUse (Bash)**: コマンド実行時間を記録、異常検知時に警告
- **SessionStart**: ビルド時間のトレンドをコンテキストに注入

## 異常検知

同じベースコマンドの過去の平均実行時間の2倍を超えた場合に警告を表示します。

## トラッキング対象

ビルド・テストコマンドを自動識別:
- `npm/yarn/pnpm build/test`
- `make`, `cmake`
- `cargo build/test`
- `go build/test`
- `pytest`, `jest`, `vitest`
- `gradle`, `mvn`

## データ保存

保存先: `~/.claude/performance-monitor/`
- プロジェクトごとにJSONLファイルで記録
- 1000エントリを超過すると古いものを自動削除
