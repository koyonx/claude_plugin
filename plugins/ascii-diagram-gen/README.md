# ascii-diagram-gen

コード変更時にクラス・関数・import構造を自動抽出し、ASCIIアート図を生成するプラグイン。

## 機能

- **構造自動抽出**: Write/Edit時にクラス名、関数名、import先を自動記録
- **ASCII図生成**: `/diagram` コマンドで収集した構造データからアーキテクチャ図を生成
- Python, JavaScript/TypeScript, Go, Rust, Ruby, Java, Kotlin, Swift, C# 対応

## コマンド

| コマンド | 説明 |
|---------|------|
| `/diagram` | 収集済みデータからASCIIアーキテクチャ図を生成 |
| `/diagram list` | 構造データ収集済みファイル一覧 |
| `/diagram clear` | 収集データを全削除 |

## フック

| イベント | トリガー |
|---------|---------|
| PostToolUse(Write\|Edit) | ファイル変更時に構造を自動抽出 |
| UserPromptSubmit | `/diagram` コマンド処理 |

## データ保存先

`~/.claude/ascii-diagram-gen/`
