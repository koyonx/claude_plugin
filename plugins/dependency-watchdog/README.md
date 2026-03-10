# dependency-watchdog

依存パッケージファイルの変更を検出し、脆弱性チェックを自動実行するプラグイン。

## 機能

- **PostToolUse (Write|Edit)**: 依存ファイル変更時にセキュリティ監査を実行
- **SessionStart**: セッション開始時にnpm auditを自動実行（package-lock.json存在時）

## 対応パッケージマネージャ

| 言語 | ファイル | 監査ツール |
|------|---------|-----------|
| Node.js | package.json, package-lock.json | npm audit |
| Python | requirements.txt, pyproject.toml | pip-audit |
| Go | go.mod | govulncheck |
| Ruby | Gemfile | bundler-audit |
| Rust | Cargo.toml | cargo-audit |
| PHP | composer.json | composer audit |

## データ保存

このプラグインはデータを保存しません（リアルタイム監査のみ）。
