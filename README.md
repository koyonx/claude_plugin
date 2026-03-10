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
| [error-memory](#error-memory) | コマンドエラーの学習・過去の解決策を自動提案 | PostToolUse, SessionStart |
| [smart-context-injector](#smart-context-injector) | プロンプトから関連ファイルを自動検出・コンテキスト注入 | UserPromptSubmit |
| [change-impact-analyzer](#change-impact-analyzer) | ファイル変更時の影響範囲（import元・テスト・型定義）を分析 | PostToolUse |
| [workflow-replay](#workflow-replay) | 操作手順の記録・再生 | PostToolUse, UserPromptSubmit |
| [session-handoff](#session-handoff) | セッション間の引き継ぎメモ自動生成 | Stop, UserPromptSubmit, SessionStart |
| [secret-scanner](#secret-scanner) | シークレット（APIキー・トークン・パスワード）の検出・ブロック | PreToolUse |
| [test-auto-runner](#test-auto-runner) | ソースファイル変更時のテスト自動実行 | PostToolUse |
| [performance-monitor](#performance-monitor) | コマンド実行時間の追跡・異常検知・ビルド時間トレンド | PostToolUse, SessionStart |
| [env-sync](#env-sync) | .env ファイルと .env.example の同期チェック | PostToolUse |
| [git-conflict-resolver](#git-conflict-resolver) | マージコンフリクトの検出・ブランチコンテキスト提供 | SessionStart, PostToolUse |
| [code-convention-learner](#code-convention-learner) | コーディング規約の学習・スタイルガイド注入 | PostToolUse, SessionStart |
| [dependency-watchdog](#dependency-watchdog) | 依存パッケージの脆弱性監査 | PostToolUse, SessionStart |
| [file-complexity-guard](#file-complexity-guard) | ファイル複雑度（行数・関数長・ネスト深度）の警告 | PostToolUse |
| [dead-code-detector](#dead-code-detector) | 削除/リネーム後の残存参照検出 | PostToolUse |
| [api-doc-sync](#api-doc-sync) | API エンドポイント変更時のドキュメント同期チェック | PostToolUse |
| [migration-tracker](#migration-tracker) | DB マイグレーションの管理・モデル変更追跡 | PostToolUse, SessionStart |
| [framework-vuln-scanner](#framework-vuln-scanner) | フレームワーク/ランタイムのバージョン脆弱性チェック | SessionStart |

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

### error-memory

コマンドエラーを記録し、同様のエラー再発時に過去の解決策を自動提案するプラグイン。

- **コマンド失敗時**: エラーパターンと後続の成功コマンド（解決策）をペアで記録
- **セッション開始時**: 頻出エラーパターンと解決策 Top5 をコンテキストに注入

保存先: `~/.claude/error-memory/`

---

### smart-context-injector

ユーザーのプロンプトからファイル参照や識別子を抽出し、関連ファイルを自動検出してコンテキストに注入するプラグイン。

- プロンプト中のファイルパス・関数名・クラス名を認識
- 関連テストファイル・最近の git 変更も自動検出
- CWD は HOME 配下に制限

---

### change-impact-analyzer

ファイル変更時に影響範囲（import 元・テストファイル・型定義）を自動分析するプラグイン。

- **ファイル変更時**: エクスポートされた関数/クラスの参照元を `grep -Frl` で検索
- テストファイル・型定義ファイルの存在も自動チェック

---

### workflow-replay

操作手順を記録し、後から再生できるプラグイン。

```
/replay start   # 記録開始
/replay stop    # 記録停止
/replay save    # レシピとして保存
/replay list    # 保存済みレシピ一覧
/replay run     # レシピを再生（参照のみ）
```

保存先: `~/.claude/workflow-replay/`

---

### session-handoff

セッション終了時に引き継ぎメモ（git 状態・プロジェクト情報）を自動生成するプラグイン。

```
/handoff latest       # 同一プロジェクトの最新メモをロード
/handoff <session-id> # 特定セッションのメモをロード
/handoff list         # メモ一覧
```

- 30 日超のメモは自動クリーンアップ

保存先: `~/.claude/session-handoff/`

---

### secret-scanner

Write/Edit 操作時にコード内のシークレットを検出してブロックするプラグイン。

- AWS Access Key、GitHub Token、秘密鍵、API キー、パスワード等を検出
- 検出時は操作をブロックし、環境変数の使用を推奨
- テスト・モックファイルは精密なパターンで除外

---

### test-auto-runner

ソースファイル変更時に対応するテストを自動検出・実行し、結果をコンテキストに注入するプラグイン。

- Python（pytest）、JavaScript/TypeScript（Jest/Vitest）、Go、Rust、Ruby 対応
- テストファイル自体の変更ではスキップ（無限ループ防止）
- タイムアウト 30 秒

---

### performance-monitor

コマンド実行時間を記録し、異常検知とビルド時間トレンドを表示するプラグイン。

- **コマンド実行後**: 実行時間を記録、平均の 2 倍超で異常警告
- **セッション開始時**: ビルド/テストコマンドのトレンドを表示
- 1000 エントリ超過時に古いものを自動削除

保存先: `~/.claude/performance-monitor/`

---

### env-sync

`.env` ファイルの変更を検出し、`.env.example` との同期状態をチェックするプラグイン。

- 新規キー・不足キーの件数を検出して警告
- `.gitignore` での `.env` 除外状態も確認
- 環境変数の値は一切読み取らない（キー名のみ）

---

### git-conflict-resolver

マージコンフリクトを検出し、ブランチコンテキストを提供するプラグイン。

- **セッション開始時**: 未解決コンフリクトを検出
- **git merge/rebase/pull 後**: コンフリクト発生を検知
- ファイル一覧とコンフリクト数をコンテキストに注入

---

### code-convention-learner

プロジェクトのコーディング規約を既存コードから学習し、セッション開始時にスタイルガイドとして注入するプラグイン。

- インデント、クォート、セミコロン、命名規則、トレーリングカンマを分析
- JS/TS、Python、Go、Rust、Ruby、Java 対応
- 5 ファイル以上分析した言語のみ規約を表示

保存先: `~/.claude/code-convention-learner/`

---

### dependency-watchdog

依存パッケージファイルの変更を検出し、脆弱性チェックを自動実行するプラグイン。

- npm audit / pip-audit / govulncheck / bundler-audit / cargo-audit / composer audit 対応
- **依存ファイル変更時**: 監査ツールを自動実行
- **セッション開始時**: npm audit を自動チェック（package-lock.json 存在時）

---

### file-complexity-guard

ファイルの複雑度を分析し、閾値超過時に分割・リファクタリングを推奨するプラグイン。

- ファイル行数（デフォルト 300 行）、関数の長さ（50 行）、ネスト深度（5 レベル）をチェック
- 環境変数 `COMPLEXITY_MAX_LINES` 等で閾値カスタマイズ可能
- 多言語対応（Python, JS/TS, Go, Rust, Ruby, Java, C/C++, PHP 等）

---

### dead-code-detector

関数/クラスの削除・リネーム後に、プロジェクト内に残存する参照を検出するプラグイン。

- Edit 操作の old_string/new_string を比較し、削除された識別子を抽出
- `grep -Frl` でプロジェクト全体の残存参照を検索
- 一般的すぎる名前（if, for, self 等）は自動スキップ

---

### api-doc-sync

API エンドポイントの変更を検出し、API 仕様書（OpenAPI/Swagger）との同期を促すプラグイン。

- FastAPI, Express, Gin, Rails, Spring, Laravel 等のルート定義を自動検出
- `openapi.yaml` / `swagger.json` の存在をチェック
- ドキュメント未作成の場合は作成を推奨

---

### migration-tracker

DB マイグレーションファイルの作成を検出し、モデル変更との整合性をチェックするプラグイン。

- Django, SQLAlchemy/Alembic, Rails, Prisma, TypeORM, Sequelize, GORM 対応
- **モデル変更時**: マイグレーション作成をリマインド
- **セッション開始時**: 未コミットのマイグレーションファイルを通知

---

### framework-vuln-scanner

フレームワーク・ランタイムのバージョンをチェックし、EOL や脆弱性リスクを警告するプラグイン。

- **ランタイム**: Node.js, Python, Ruby, Go のバージョンチェック
- **フレームワーク**: React, Next.js, Express, Vue.js, Angular, Django, Flask, Rails
- `package.json` / `requirements.txt` / `Gemfile` からバージョンを自動抽出

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
├── command-audit/            # command-audit
├── error-memory/             # error-memory (エラーパターン DB)
├── session-handoff/          # session-handoff (引き継ぎデータ)
├── workflow-replay/          # workflow-replay (ワークフロー記録)
├── performance-monitor/      # performance-monitor (ビルド時間記録)
└── code-convention-learner/  # code-convention-learner (コーディング規約)
```

## ライセンス

MIT
