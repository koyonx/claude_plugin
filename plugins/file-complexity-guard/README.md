# file-complexity-guard

ファイルの複雑度を分析し、閾値超過時に警告するプラグイン。

## 機能

- **PostToolUse (Write|Edit)**: ファイル変更後に複雑度をチェック

## チェック項目

| 項目 | デフォルト閾値 | 環境変数 |
|------|-------------|---------|
| ファイル行数 | 300行 | `COMPLEXITY_MAX_LINES` |
| 関数の長さ | 50行 | `COMPLEXITY_MAX_FUNC_LINES` |
| ネスト深度 | 5レベル | `COMPLEXITY_MAX_NESTING` |

## 対応言語

Python, JavaScript, TypeScript, Go, Rust, Ruby, Java, PHP, C/C++, C#, Swift, Kotlin

## データ保存

このプラグインはデータを保存しません（リアルタイム分析のみ）。
