# migration-tracker

DBマイグレーションファイルの作成を検出し、モデル変更との整合性をチェックするプラグイン。

## 機能

- **PostToolUse (Write|Edit)**: モデル/スキーマファイル変更時にマイグレーション作成をリマインド
- **SessionStart**: 未コミットのマイグレーションファイルを通知

## 対応ORM/フレームワーク

| フレームワーク | モデル検出パターン |
|--------------|------------------|
| Django | `models.py`, `class Foo(Model)` |
| SQLAlchemy/Alembic | `Column`, `mapped_column`, `ForeignKey` |
| Rails/ActiveRecord | `ApplicationRecord`, `ActiveRecord::Base` |
| Prisma | `schema.prisma` |
| TypeORM | `@Entity()`, `@Column()` |
| Sequelize | `sequelize.define`, `DataTypes` |
| GORM (Go) | `gorm.Model`, `gorm:"` |

## データ保存

このプラグインはデータを保存しません（リアルタイム検出のみ）。
