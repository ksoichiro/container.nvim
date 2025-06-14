# LSP統合機能 - クイックテスト手順

修正したLSP統合機能をテストするための手順です。

## 前提条件
- Docker が動作している
- Neovim (0.8+) がインストールされている
- nvim-lspconfig プラグインがインストールされている

## ステップ1: プラグインの初期化テスト

### Neovimでプラグインを読み込み
```lua
-- Neovim内で実行
require('devcontainer').setup({
  log_level = 'debug',
  lsp = {
    auto_setup = true,
    timeout = 10000
  }
})
```

### 初期化確認
```vim
:DevcontainerDebug
```

期待される出力:
```
=== DevContainer Debug Info ===
Initialized: true
Current container: none
Current config: none
```

## ステップ2: LSP状態の確認（コンテナなし）

```vim
:DevcontainerLspStatus
```

期待される出力:
```
=== DevContainer LSP Status ===
Container ID: none
Auto setup: true
No servers detected (container may not be running)
No active LSP clients
```

## ステップ3: Python例でのテスト

### Python例ディレクトリに移動
```bash
cd examples/python-example
nvim main.py
```

### devcontainerを開始
```vim
:DevcontainerOpen
:DevcontainerStart
```

### LSP状態を再確認
```vim
:DevcontainerLspStatus
```

期待される動作:
- Container IDが表示される
- Python関連のLSPサーバーが検出される
- 自動セットアップが実行される

## ステップ4: LSP機能のテスト

### コード補完テスト
1. `main.py`を開く
2. 新しい行で`calc.`と入力
3. `<C-x><C-o>`で補完候補を確認

### 定義ジャンプテスト
1. `hello_world("test")`の`hello_world`にカーソルを置く
2. `gd`で定義にジャンプできるか確認

### ホバー情報テスト
1. 関数名にカーソルを置く
2. `K`でドキュメントが表示されるか確認

## トラブルシューティング

### エラー1: "LSP not initialized"
**解決方法:**
```vim
:lua require('devcontainer').setup({log_level = 'debug'})
:DevcontainerLspStatus
```

### エラー2: "No active container"
**解決方法:**
```vim
:DevcontainerStart
:DevcontainerLspSetup
```

### エラー3: LSPサーバーが検出されない
**解決方法:**
```vim
:DevcontainerExec which pylsp
:DevcontainerExec python -m pip install python-lsp-server
:DevcontainerLspSetup
```

### エラー4: パス変換の問題
**解決方法:**
```vim
:lua print(vim.inspect(require('devcontainer.lsp.path').get_mappings()))
```

## デバッグ用コマンド

### 詳細ログの確認
```vim
:messages
:DevcontainerLogs
```

### 手動でのLSP再起動
```vim
:DevcontainerLspSetup
:LspRestart
```

### Docker情報の確認
```vim
:DevcontainerExec ps aux
:DevcontainerStatus
```

## 期待される最終状態

すべてが正常に動作している場合:

1. `:DevcontainerLspStatus`で以下が表示される:
   ```
   === DevContainer LSP Status ===
   Container ID: <container_id>
   Auto setup: true
   Detected servers:
     pylsp: pylsp (available: true)
   Active clients:
     pylsp
   ```

2. `:LspInfo`でpylspクライアントが表示される

3. Python ファイルでLSP機能（補完、診断、定義ジャンプ）が動作する

## 最小限のテスト

時間がない場合の最小限テスト:

```vim
:lua require('devcontainer').setup()
:DevcontainerDebug
:cd examples/python-example
:DevcontainerStart
:DevcontainerLspStatus
:edit main.py
```

main.pyで`K`（ホバー）が動作すれば基本的な統合は成功しています。