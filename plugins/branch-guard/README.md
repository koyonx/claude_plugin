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

## 既知の制限

- テキストベースのコマンド検出のため、`bash -c` ラップや変数展開等の高度な回避は完全には防げません
- git エイリアスや `git merge` / `git rebase` 等は検出対象外です
- サーバーサイドのブランチ保護ルール（GitHub Branch Protection）との併用を推奨します

## 依存関係

- jq
- git (2.22+)
