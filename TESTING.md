# devcontainer.nvim LSP Integration Testing Guide

このガイドでは、v0.2.0で実装されたLSP統合機能をテストする方法を説明します。

## 前提条件

### 必要なツール
- Docker または Podman
- Neovim (0.8+)
- nvim-lspconfig プラグイン
- Lazy.nvim または他のプラグインマネージャー

### プラグインのセットアップ
```lua
-- Lazy.nvim の場合
{
  dir = "/path/to/devcontainer.nvim", -- ローカルパス
  dependencies = {
    "neovim/nvim-lspconfig",
  },
  config = function()
    require('devcontainer').setup({
      log_level = 'debug', -- デバッグ用
      lsp = {
        auto_setup = true,
        timeout = 10000, -- テスト用に長めに設定
      }
    })
  end,
}
```

## テスト手順

### 1. 基本的な動作確認

#### ステップ1: プラグインの初期化確認
```vim
:DevcontainerDebug
```
- プラグインが正しく初期化されているか確認
- 設定が正しく読み込まれているか確認

#### ステップ2: Docker の確認
```bash
docker --version
docker ps
```

### 2. Python LSP テスト

#### ステップ1: Python 例に移動
```bash
cd examples/python-example
nvim main.py
```

#### ステップ2: devcontainer を開始
```vim
:DevcontainerOpen
:DevcontainerStart
```

#### ステップ3: LSP 状態確認
```vim
:DevcontainerLspStatus
```
期待される出力:
```
=== DevContainer LSP Status ===
Container ID: <container_id>
Auto setup: true
Detected servers:
  pylsp: pylsp (available: true)
Active clients:
  pylsp
```

#### ステップ4: LSP 機能のテスト

1. **コード補完テスト**
   - `main.py` を開く
   - 新しい行で `calc.` と入力
   - `<C-x><C-o>` または補完プラグインで補完候補が表示されるか確認

2. **定義ジャンプテスト**
   - `hello_world("test")` の `hello_world` にカーソルを置く
   - `gd` または `:lua vim.lsp.buf.definition()` で定義にジャンプできるか確認

3. **診断テスト**
   - 意図的に構文エラーを作成（例: `print("test"`）
   - 診断メッセージが表示されるか確認

4. **ホバー情報テスト**
   - 関数名にカーソルを置く
   - `K` または `:lua vim.lsp.buf.hover()` でドキュメントが表示されるか確認

### 3. Node.js LSP テスト

#### ステップ1: Node.js 例に移動
```bash
cd examples/node-example
nvim index.js
```

#### ステップ2: devcontainer を開始
```vim
:DevcontainerOpen
:DevcontainerStart
```

#### ステップ3: 同様のLSPテストを実行
- コード補完
- 定義ジャンプ
- 診断
- ホバー情報

### 4. 手動テストスクリプト

以下のスクリプトで自動テストができます：

#### テスト用 Lua スクリプト
```lua
-- test_lsp.lua
local function test_lsp_integration()
  print("=== LSP Integration Test ===")
  
  -- 1. Basic functionality test
  local devcontainer = require('devcontainer')
  
  -- Check if plugin is initialized
  local debug_info = devcontainer.debug_info()
  
  -- 2. LSP status test
  local lsp_status = devcontainer.lsp_status()
  if not lsp_status then
    print("ERROR: LSP not initialized")
    return false
  end
  
  -- 3. Check active LSP clients
  local clients = vim.lsp.get_active_clients()
  print("Active LSP clients: " .. #clients)
  for _, client in ipairs(clients) do
    print("  - " .. client.name)
  end
  
  -- 4. Test path conversion
  local lsp_path = require('devcontainer.lsp.path')
  local test_path = vim.fn.expand('%:p')
  local container_path = lsp_path.to_container_path(test_path)
  local back_to_local = lsp_path.to_local_path(container_path)
  
  print("Path conversion test:")
  print("  Local: " .. test_path)
  print("  Container: " .. (container_path or "nil"))
  print("  Back to local: " .. (back_to_local or "nil"))
  
  return true
end

test_lsp_integration()
```

#### 実行方法
```vim
:luafile test_lsp.lua
```

### 5. トラブルシューティング

#### 一般的な問題と解決方法

1. **LSP サーバーが検出されない**
   ```vim
   :DevcontainerExec which pylsp
   :DevcontainerExec python -m pylsp --help
   ```

2. **通信エラー**
   ```vim
   :DevcontainerLogs
   :messages
   ```

3. **パス変換の問題**
   ```vim
   :lua print(require('devcontainer.lsp.path').get_mappings())
   ```

4. **手動での LSP セットアップ**
   ```vim
   :DevcontainerLspSetup
   ```

#### ログの確認
```vim
:DevcontainerLogs
:lua require('devcontainer.utils.log').show_logs()
```

### 6. デバッグ用コマンド

```vim
" 詳細なデバッグ情報
:DevcontainerDebug

" LSP固有の状態
:DevcontainerLspStatus

" コンテナ内でのコマンド実行
:DevcontainerExec ps aux | grep lsp

" 手動でのLSP再起動
:LspRestart

" LSP情報の表示
:LspInfo
```

### 7. 期待される動作

正常に動作している場合:
- `:DevcontainerStart` 実行後、自動的にLSPサーバーが検出・起動
- 通常のNeovim LSP機能がすべて動作
- ファイルパスがローカル⇔コンテナ間で正しく変換される
- 診断、補完、定義ジャンプなどがすべて機能

### 8. パフォーマンステスト

大きなプロジェクトでのテスト:
```bash
# 大きなPythonプロジェクトをクローン
git clone https://github.com/psf/requests.git
cd requests
# .devcontainer/devcontainer.json を作成
nvim
:DevcontainerStart
# LSP の応答速度をテスト
```

このテストガイドに従って、LSP統合機能の動作を確認してください。問題が発生した場合は、ログを確認し、必要に応じて設定を調整してください。