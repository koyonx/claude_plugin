# pair-programming-log

人間とClaudeの意思決定ログをADR（Architecture Decision Record）形式で自動記録するプラグイン。

## 機能

- **ADR自動生成**: `/decision` で意思決定の記録を開始
- **ファイル変更追跡**: アクティブなADR期間中のファイル変更を自動記録
- **セッション終了時**: ADRのステータスを自動更新（Proposed → Accepted）
- **エクスポート**: `/decision export` でプロジェクトの `docs/decisions/` にADRを出力

## コマンド

| コマンド | 説明 |
|---------|------|
| `/decision [title]` | 新しいADRを開始（タイトル省略可） |
| `/decision list` | 記録済みADR一覧 |
| `/decision show [id]` | ADR内容を表示 |
| `/decision export` | プロジェクトにADRファイルを出力 |

## ADRテンプレート

- Status（Proposed/Accepted）
- Date / Branch
- Context（背景・課題）
- Decision（決定内容と理由）
- Alternatives Considered（検討した代替案）
- Consequences（トレードオフ・影響）
- Files Changed（変更ファイル一覧、自動記録）

## データ保存先

`~/.claude/pair-programming-log/`
