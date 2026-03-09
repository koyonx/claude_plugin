# cost-tracker

セッションごとのトークン使用量を記録し、コストを可視化するプラグイン。

## 機能

| Hook | タイミング | 動作 |
|------|-----------|------|
| `Stop` | 応答完了時 | トランスクリプトからトークン使用量を抽出・記録 |
| `SessionStart` | セッション開始時 | プロジェクトの累計使用量サマリーを表示 |

## インストール

```bash
claude --plugin-dir ./plugins/cost-tracker
```

## 保存先

- 使用量データ: `~/.claude/cost-tracker/<project>/`
- 各セッションのデータはJSON形式で保存

## 記録データ

```json
{
  "total_input_tokens": 12345,
  "total_output_tokens": 6789,
  "total_cache_read_tokens": 1000,
  "total_cache_create_tokens": 500,
  "request_count": 15,
  "session_id": "abc12345",
  "timestamp": "2026-03-09T15:00:00"
}
```

## 依存関係

- Python 3.9+
- jq
