# context-loader

セッション開始時にプロジェクト固有の重要ファイルを自動でコンテキストに読み込むプラグイン。

## 使い方

プロジェクトルートに `.context-loader.json` を作成します。

```json
{
    "files": [
        "docs/architecture.md",
        "API_SPEC.md",
        "CLAUDE.md"
    ],
    "globs": [
        "src/**/*.proto",
        "docs/**/*.md"
    ]
}
```

セッション開始時に指定されたファイルが自動的に読み込まれます。

## インストール

```bash
claude --plugin-dir ./plugins/context-loader
```

## 設定

| フィールド | 説明 |
|-----------|------|
| `files` | 読み込むファイルパスのリスト（プロジェクトルートからの相対パス） |
| `globs` | globパターンのリスト（再帰的マッチ対応） |

## 制限

- 1ファイルあたり最大5MB
- 合計最大20MB
- プロジェクトルート外のファイルは読み込み不可（パストラバーサル防止）

## 依存関係

- Python 3.9+
