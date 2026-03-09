# Claude Code Plugin Collection

Claude Code の開発体験を向上させるプラグイン集です。
全プラグインは Claude Code の `/plugin` コマンドからインストールでき、hooks ベースで動作します。

## 前提条件

- [Claude Code](https://claude.com/claude-code) がインストール済みであること
- **jq** がインストール済みであること（全プラグインで使用）
- **Python 3.9+**（session-history, cost-tracker, context-loader で使用）
- **git 2.22+**（branch-guard で使用）

### jq のインストール

```bash
# macOS
brew install jq

# Ubuntu / Debian
sudo apt install jq
```

## プラグイン一覧

| プラグイン | 概要 | 使用 Hook |
|-----------|------|----------|
| [session-history](#session-history) | セッション会話履歴の自動保存・コンパクト前バックアップ | PreCompact, Stop, SessionStart |
| [auto-commit-suggestion](#auto-commit-suggestion) | ファイル変更数に応じたコミット提案 | PostToolUse |
| [cost-tracker](#cost-tracker) | トークン使用量の記録・コスト可視化 | Stop, SessionStart |
| [diff-snapshot](#diff-snapshot) | ファイル変更前後のスナップショット・ロールバック | PreToolUse, PostToolUse |
| [prompt-template](#prompt-template) | プロンプトテンプレートの保存・呼び出し | UserPromptSubmit |
| [context-loader](#context-loader) | セッション開始時のコンテキスト自動読み込み | SessionStart |
| [branch-guard](#branch-guard) | 保護ブランチへの直接コミット・プッシュ防止 | PreToolUse, SessionStart |
| [todo-tracker](#todo-tracker) | TODO/FIXME/HACK コメントの自動検出・管理 | PostToolUse, SessionStart |
| [command-audit](#command-audit) | コマンド実行ログ・危険コマンド警告 | PreToolUse, Stop |

## クイックスタート

### 1. リポジトリをクローン

```bash
git clone https://github.com/koyonx/claude_plugin.git
cd claude_plugin
```

### 2. プラグインを試す

```bash
# 単体で試す場合
claude --plugin-dir ./plugins/<plugin-name>

# 例: session-history を試す
claude --plugin-dir ./plugins/session-history
```

### 3. 複数プラグインを同時に使う

```bash
claude \
  --plugin-dir ./plugins/session-history \
  --plugin-dir ./plugins/branch-guard \
  --plugin-dir ./plugins/diff-snapshot
```

### 4. 恒久的にインストール

Claude Code 内で `/plugin` コマンドを使用し、マーケットプレイスとしてローカルパスを追加してインストールできます。

## 各プラグインの詳細

### session-history

セッション会話履歴を自動保存するプラグイン。コンパクト（会話圧縮）による過去の会話消失を防ぎます。

- **コンパクト前**: トランスクリプト JSONL をバックアップ
- **応答完了時**: 会話を読みやすい Markdown 形式で保存
- **セッション開始時**: 前回のセッションログパスを表示

保存先: `~/.claude/session-history/`

---

### auto-commit-suggestion

ファイル変更が一定数（デフォルト 5）に達したら、git コミットを提案します。作業中のコード消失を防ぎます。

- 環境変数 `AUTO_COMMIT_THRESHOLD` で閾値を変更可能
- `git commit` 検出時にカウンターをリセット

---

### cost-tracker

セッションごとのトークン使用量を記録し、プロジェクト単位でコストを可視化します。

- **応答完了時**: トランスクリプトからトークン使用量を抽出・記録
- **セッション開始時**: 累計使用量サマリーを表示

保存先: `~/.claude/cost-tracker/`

---

### diff-snapshot

Write/Edit 実行前後のファイルスナップショットを自動保存します。意図しない変更を簡単にロールバックできます。

- **変更前**: ファイルのスナップショットを保存
- **変更後**: 変更前後の diff を保存
- **CLI ツール**: `./scripts/restore.sh` でスナップショットの一覧・復元・差分確認

```bash
# スナップショット一覧
./plugins/diff-snapshot/scripts/restore.sh list

# 復元
./plugins/diff-snapshot/scripts/restore.sh restore <snapshot-file>
```

保存先: `~/.claude/diff-snapshots/`

---

### prompt-template

よく使うプロンプトをテンプレートとして保存・呼び出しできます。

```
/template review     # コードレビュー依頼
/template refactor   # リファクタリング依頼
/template test       # テスト作成依頼
```

カスタムテンプレートは `~/.claude/prompt-templates/` に Markdown ファイルを追加するだけで利用できます。

---

### context-loader

セッション開始時にプロジェクト固有の重要ファイルを自動読み込みします。

プロジェクトルートに `.context-loader.json` を配置してください:

```json
{
    "files": ["docs/architecture.md", "API_SPEC.md"],
    "globs": ["src/**/*.proto"]
}
```

制限: 1 ファイル 5MB、合計 20MB まで。

---

### branch-guard

保護ブランチ（main/master）への直接コミット・プッシュをブロックします。

- セッション開始時に現在のブランチと保護状態を表示
- `.branch-guard.json` で保護対象ブランチをカスタマイズ可能

```json
{
    "protected_branches": ["main", "master", "production"]
}
```

> **Note**: テキストベースのコマンド検出のため、高度な回避手法には対応していません。GitHub Branch Protection との併用を推奨します。

---

### todo-tracker

ファイル変更時に TODO/FIXME/HACK/XXX コメントを自動検出し、プロジェクト単位で管理します。技術的負債の可視化に。

- **ファイル変更時**: 変更ファイルをスキャンして TODO マーカーを JSON に記録
- **セッション開始時**: 未解決 TODO 一覧を表示（FIXME は優先表示）
- 存在しなくなったファイルの TODO は自動通知

保存先: `~/.claude/todo-tracker/`

---

### command-audit

全 Bash コマンドをセッション単位で JSONL ログに記録し、危険なコマンドを検出して警告します。

- **コマンド実行前**: コマンドをログに記録、危険パターン検出時に警告表示
- **セッション終了時**: コマンド実行サマリーを表示
- 30 日超の古いログを自動クリーンアップ

検出対象: `rm -rf`、`git push --force`、`git reset --hard`、`DROP TABLE`、`chmod 777` 等

> **Note**: テキストベースのパターンマッチによるベストエフォート検出です。変数展開や間接実行は検出できません。Claude Code 本体の承認フローと併用してください。

保存先: `~/.claude/command-audit/`

---

## データの保存先

全プラグインのデータは `~/.claude/` 配下に保存されます。

```
~/.claude/
├── session-history/          # session-history
│   ├── sessions/             #   セッションログ (Markdown)
│   └── compaction-backups/   #   コンパクト前バックアップ (JSONL)
├── auto-commit-suggestion/   # auto-commit-suggestion
├── cost-tracker/             # cost-tracker
├── diff-snapshots/           # diff-snapshot
├── prompt-templates/         # prompt-template (カスタムテンプレート)
├── todo-tracker/             # todo-tracker
└── command-audit/            # command-audit
```

## ライセンス

MIT
