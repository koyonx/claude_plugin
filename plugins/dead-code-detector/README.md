# dead-code-detector

関数/クラスの削除・リネーム後に、プロジェクト内に残存する参照を検出するプラグイン。

## 機能

- **PostToolUse (Edit)**: Edit操作のold_string/new_stringを比較し、削除・リネームされた識別子を検出。プロジェクト内の残存参照を警告。

## 検出対象

- 関数定義 (`def`, `function`, `func`, `fn`)
- クラス/構造体定義 (`class`, `struct`, `type`, `trait`)
- 変数定義 (`const`, `let`, `var`)
- モジュール定義 (`module`, `enum`, `impl`)

## 対応言語

Python, JavaScript, TypeScript, Go, Rust, Ruby, Java, PHP, C/C++, C#, Swift, Kotlin

## データ保存

このプラグインはデータを保存しません（リアルタイム検出のみ）。
