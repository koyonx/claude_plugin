# branch-guard

保護ブランチ（main/master）への直接コミット・プッシュを防止するプラグイン。

CLAUDE.mdのブランチ運用ルールを自動で強制します。

## 機能

| Hook | タイミング | 動作 |
|------|-----------|------|
| `PreToolUse` | Bash実行前 | git commit/pushが保護ブランチで実行されようとしたらブロック |
| `SessionStart` | セッション開始時 | 現在のブランチと保護状態を表示 |

## インストール

```bash
claude --plugin-dir ./plugins/branch-guard
```

## 設定

プロジェクトルートに `.branch-guard.json` を作成すると、保護ブランチをカスタマイズできます。

```json
{
    "protected_branches": ["main", "master", "production"]
}
```

設定ファイルがない場合は `main` と `master` がデフォルトで保護されます。

## 動作例

```
# mainブランチでgit commitを実行しようとした場合:
# -> "Direct commit to protected branch 'main' is not allowed.
#     Create a feature branch first."

# featureブランチでは通常通り動作します
```

## 依存関係

- jq
- git
