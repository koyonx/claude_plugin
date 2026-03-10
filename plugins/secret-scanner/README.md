# secret-scanner

Write/Edit 操作時にコード内のシークレット（APIキー、トークン、パスワード）を検出してブロックするプラグイン。

## 機能

- **PreToolUse (Write|Edit)**: ファイル書き込み前にコンテンツをスキャンし、シークレットが含まれていればブロック

## 検出対象

| パターン | 例 |
|---------|---|
| AWS Access Key | `AKIA` で始まる20文字のキー |
| GitHub Token | `ghp_`, `gho_`, `ghu_`, `ghs_`, `ghr_` |
| Private Key | `-----BEGIN PRIVATE KEY-----` |
| API Key/Secret | `api_key = "..."`, `apiSecret: "..."` |
| Token/Secret 代入 | `secret_key = "..."`, `access_token = "..."` |
| パスワード代入 | `password = "..."` (プレースホルダー除外) |
| Bearer/Basic 認証 | `Bearer <長いトークン>` |
| 長い16進文字列 | 40文字以上の hex 文字列 |

## スキップ対象

- ドキュメント・画像ファイル (.md, .txt, .png, etc.)
- テスト・モックファイル (test, mock, fixture, example)
- テストディレクトリ内のファイル

## データ保存

このプラグインはデータを保存しません（リアルタイムスキャンのみ）。
