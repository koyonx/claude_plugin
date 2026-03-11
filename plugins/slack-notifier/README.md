# slack-notifier

長時間コマンドの完了やエラー発生時に Slack/Discord Webhook で通知するプラグイン。

## 機能

- **エラー通知**: コマンド失敗時に即座に Webhook 通知
- **長時間コマンド通知**: 閾値（デフォルト30秒）を超えるコマンド完了時に通知
- **セッション終了通知**: セッション終了時にサマリーを送信（オプション）

## 設定

`~/.claude/slack-notifier/config.json` を作成:

```json
{
    "webhook_url": "https://hooks.slack.com/services/T.../B.../xxx",
    "duration_threshold_ms": 30000,
    "notify_on_error": true,
    "notify_on_long_running": true,
    "notify_on_session_end": false
}
```

## フック

| イベント | トリガー |
|---------|---------|
| PostToolUse(Bash) | コマンド実行後にエラー/長時間チェック |
| Stop | セッション終了時にサマリー通知 |
| SessionStart | 設定状態を表示 |
