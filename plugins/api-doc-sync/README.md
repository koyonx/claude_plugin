# api-doc-sync

APIエンドポイントの変更を検出し、API仕様書との同期を促すプラグイン。

## 機能

- **PostToolUse (Write|Edit)**: APIルート定義を含むファイルの変更を検出し、ドキュメント更新をリマインド

## 対応フレームワーク

| 言語 | フレームワーク |
|------|--------------|
| Python | FastAPI, Flask, Django |
| JavaScript/TypeScript | Express, Nest.js, Next.js |
| Go | Gin, Echo, net/http |
| Ruby | Rails |
| Java | Spring |
| PHP | Laravel |

## チェック対象ドキュメント

`openapi.yaml`, `openapi.yml`, `openapi.json`, `swagger.yaml`, `swagger.yml`, `swagger.json`, `api-spec.yaml`, `docs/api`, `doc/api`

## データ保存

このプラグインはデータを保存しません（リアルタイム検出のみ）。
