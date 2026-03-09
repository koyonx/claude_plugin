# prompt-template

よく使うプロンプトをテンプレートとして保存・呼び出しできるプラグイン。

## 使い方

Claudeのプロンプトに `/template <name>` と入力すると、テンプレートの内容に展開されます。

```
/template review
/template refactor
/template test
```

## デフォルトテンプレート

| 名前 | 内容 |
|------|------|
| `review` | コードレビュー（セキュリティ・バグ・品質チェック） |
| `refactor` | リファクタリング依頼 |
| `test` | テスト作成依頼 |

## カスタムテンプレートの追加

`~/.claude/prompt-templates/` にMarkdownファイルを追加すると、カスタムテンプレートとして利用できます。

```bash
# 例: deployテンプレートを追加
echo "デプロイ手順を確認してください。" > ~/.claude/prompt-templates/deploy.md
```

ユーザーカスタムテンプレートはビルトインテンプレートより優先されます。

## インストール

```bash
claude --plugin-dir ./plugins/prompt-template
```

## 依存関係

- jq
