# session-history

Claude Codeのセッション会話履歴を自動保存するプラグイン。

コンパクト（会話圧縮）によって過去の会話が失われることを防ぎ、セッションごとに読みやすいMarkdown形式でログを保存します。

## 機能

| Hook | タイミング | 動作 |
|------|-----------|------|
| `PreCompact` | コンパクト実行前 | トランスクリプトJSONLをバックアップ |
| `Stop` | Claude応答完了時 | 会話をMarkdown形式で保存 |
| `SessionStart` | セッション開始時 | 前回のセッションログパスを表示 |

## インストール

### `/plugin` コマンドから（推奨）

```bash
# ローカルテスト
claude --plugin-dir ./plugins/session-history

# マーケットプレイスとして追加
/plugin marketplace add ./plugins/session-history
```

### 構成

```
session-history/
├── .claude-plugin/
│   └── plugin.json        # プラグインマニフェスト
├── hooks/
│   └── hooks.json         # hook定義
├── scripts/
│   ├── backup-before-compact.sh
│   ├── save-session.sh
│   ├── on-session-start.sh
│   └── transcript_parser.py
└── README.md
```

## 保存先

- セッションログ（Markdown）: `~/.claude/session-history/sessions/<project>/`
- コンパクト前バックアップ（JSONL）: `~/.claude/session-history/compaction-backups/`

## セッションログの形式

```markdown
# Session Log: abc12345

- **Session ID**: `abc12345-xxxx-xxxx-xxxx`
- **Project**: `/path/to/project`
- **Saved at**: 2026-03-09 15:30:00

---

## User (2026-03-09 15:00:00)

ユーザーのプロンプト

## Assistant (2026-03-09 15:00:05)

Claudeの応答
[Tool: Bash] `git status`

---
*Total messages: 4*
```

## 依存関係

- Python 3.9+
- jq（シェルスクリプトで使用）
