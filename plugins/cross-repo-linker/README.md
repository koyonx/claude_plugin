# cross-repo-linker

複数リポジトリ間の依存関係を追跡し、変更時に影響を通知するプラグイン。

## 機能

- **リポジトリリンク**: `/repo link <path>` で関連リポジトリを登録
- **共有依存検出**: リンク時にnpm/pip等の共通パッケージを自動検出
- **依存ファイル変更通知**: package.json等の変更時にリンク先への影響を通知
- **ステータス確認**: `/repo check` で全リンク先のgit状態を一括確認

## コマンド

| コマンド | 説明 |
|---------|------|
| `/repo link <path>` | リポジトリをリンク |
| `/repo unlink <name>` | リンク解除 |
| `/repo list` | リンク一覧 |
| `/repo check` | 全リンク先のステータス確認 |

## 自動チェック対象

- `package.json` (npm)
- `requirements.txt` / `pyproject.toml` (pip)
- `Gemfile` (Ruby)
- `go.mod` (Go)
- `Cargo.toml` (Rust)

## フック

| イベント | トリガー |
|---------|---------|
| PostToolUse(Write\|Edit) | 依存ファイル変更時にクロスリポ影響チェック |
| SessionStart | リンク済みリポジトリのステータス表示 |
| UserPromptSubmit | `/repo` コマンド処理 |

## データ保存先

`~/.claude/cross-repo-linker/`
