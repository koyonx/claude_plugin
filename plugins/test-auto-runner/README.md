# test-auto-runner

ソースファイルの変更時に対応するテストを自動検出・実行し、結果をコンテキストに注入するプラグイン。

## 機能

- **PostToolUse (Write|Edit)**: ファイル変更後に対応するテストファイルを探して自動実行

## 対応言語・テストフレームワーク

| 言語 | テストファイルパターン | テストランナー |
|------|----------------------|--------------|
| Python | `test_*.py`, `*_test.py` | pytest |
| JavaScript | `*.test.js`, `*.spec.js` | Jest |
| TypeScript | `*.test.ts`, `*.spec.ts` | Vitest / Jest |
| Go | `*_test.go` | go test |
| Rust | `#[cfg(test)]` | cargo test |
| Ruby | `*_spec.rb`, `test_*.rb` | RSpec / Minitest |

## 動作

1. 変更されたファイルの拡張子を確認
2. 一般的な命名規則でテストファイルを探索
3. テストランナーを自動検出して実行（タイムアウト30秒）
4. 結果をClaudeのコンテキストに注入

## データ保存

このプラグインはデータを保存しません（リアルタイム実行のみ）。
