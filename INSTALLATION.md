# devcontainer.nvim インストールガイド

## Lazy.nvimでの組み込み方法

### 1. ローカル開発版を使用する場合

現在のディレクトリがdevcontainer.nvimプラグインのソースなので、ローカルパスを指定してインストールできます。

```lua
-- ~/.config/nvim/lua/plugins/devcontainer.lua または適切な設定ファイル
return {
  {
    -- ローカルパスを指定（このプロジェクトのパスに変更してください）
    dir = "/path/to/devcontainer.nvim",
    name = "devcontainer.nvim",
    config = function()
      require('devcontainer').setup({
        -- 基本設定
        log_level = 'info',
        container_runtime = 'docker', -- 'docker' or 'podman'
        auto_start = false,
        
        -- UI設定
        ui = {
          show_notifications = true,
          icons = {
            container = "🐳",
            running = "✅",
            stopped = "⏹️",
            building = "🔨",
          },
        },
        
        -- ターミナル設定
        terminal = {
          shell = '/bin/bash',
          height = 15,
          direction = 'horizontal',
        },
      })
    end,
  }
}
```

### 2. GitHubリポジトリから使用する場合

```lua
return {
  {
    'ksoichiro/devcontainer.nvim',
    config = function()
      require('devcontainer').setup({
        log_level = 'info',
        container_runtime = 'docker',
        auto_start = false,
      })
    end,
  }
}
```

### 3. 開発用の設定例（推奨）

```lua
-- ~/.config/nvim/lua/plugins/devcontainer.lua
return {
  {
    -- 開発中はローカルパスを使用
    dir = vim.fn.expand("~/path/to/devcontainer.nvim"), -- 実際のパスに変更
    name = "devcontainer.nvim",
    
    -- 開発モードでは遅延読み込みを無効にする
    lazy = false,
    
    config = function()
      require('devcontainer').setup({
        -- 開発用設定
        log_level = 'debug', -- デバッグ情報を表示
        
        -- Docker設定
        container_runtime = 'docker',
        
        -- 自動開始を無効（手動でテストしたい場合）
        auto_start = false,
        
        -- UI設定
        ui = {
          show_notifications = true,
          status_line = true,
          icons = {
            container = "🐳",
            running = "✅",
            stopped = "⏹️", 
            building = "🔨",
            error = "❌",
          },
        },
        
        -- ターミナル設定
        terminal = {
          shell = '/bin/bash',
          height = 15,
          direction = 'horizontal',
          close_on_exit = false,
        },
        
        -- 開発設定
        dev = {
          reload_on_change = true,
          debug_mode = true,
        },
      })
    end,
    
    -- キーマッピングの設定例
    keys = {
      { "<leader>co", "<cmd>DevcontainerOpen<cr>", desc = "Open devcontainer" },
      { "<leader>cb", "<cmd>DevcontainerBuild<cr>", desc = "Build devcontainer" },
      { "<leader>cs", "<cmd>DevcontainerStart<cr>", desc = "Start devcontainer" },
      { "<leader>cx", "<cmd>DevcontainerStop<cr>", desc = "Stop devcontainer" },
      { "<leader>ct", "<cmd>DevcontainerShell<cr>", desc = "Open shell" },
      { "<leader>cl", "<cmd>DevcontainerLogs<cr>", desc = "Show logs" },
      { "<leader>ci", "<cmd>DevcontainerStatus<cr>", desc = "Show status" },
      { "<leader>cr", "<cmd>DevcontainerReset<cr>", desc = "Reset state" },
    },
  }
}
```

## 設定手順

### 1. プラグインファイルの作成

```bash
# Neovim設定ディレクトリに移動
cd ~/.config/nvim

# プラグイン設定ファイルを作成
mkdir -p lua/plugins
touch lua/plugins/devcontainer.lua
```

### 2. 設定の記述

上記の設定例を `lua/plugins/devcontainer.lua` に記述します。

### 3. パスの調整

`dir` パラメータを実際のdevcontainer.nvimプロジェクトのパスに変更してください：

```lua
dir = "/Users/yourname/path/to/devcontainer.nvim",
```

### 4. Neovimの再起動

設定を保存してNeovimを再起動すると、プラグインが読み込まれます。

## 動作確認

### 1. プラグインの読み込み確認

```vim
:DevcontainerDebug
```

プラグインの状態とデバッグ情報が表示されます。

### 2. 設定確認

```vim
:DevcontainerConfig
```

現在の設定が表示されます。

### 3. Docker確認

```vim
:DevcontainerOpen
```

Dockerの可用性がチェックされます。

## トラブルシューティング

### プラグインが読み込まれない場合

1. パスが正しいか確認
```lua
:lua print(vim.fn.expand("~/path/to/devcontainer.nvim"))
```

2. Lazy.nvimのログを確認
```vim
:Lazy log
```

3. エラーメッセージを確認
```vim
:messages
```

### Docker関連のエラー

1. Dockerが起動しているか確認
```bash
docker --version
docker info
```

2. 権限の確認
```bash
# Dockerグループに追加されているか確認
groups $USER
```

## 開発用の便利設定

### ホットリロード設定

```lua
-- 開発中にプラグインを再読み込みする関数
vim.api.nvim_create_user_command('DevcontainerReload', function()
  -- モジュールキャッシュをクリア
  for module_name, _ in pairs(package.loaded) do
    if module_name:match("^devcontainer") then
      package.loaded[module_name] = nil
    end
  end
  
  -- プラグインを再読み込み
  require('devcontainer').setup()
  print("devcontainer.nvim reloaded!")
end, {})
```

### ログファイル設定

```lua
config = function()
  require('devcontainer').setup({
    log_level = 'debug',
    -- ログファイルを設定
    log_file = vim.fn.stdpath('data') .. '/devcontainer.log',
  })
  
  -- ログファイルを開くコマンド
  vim.api.nvim_create_user_command('DevcontainerLogFile', function()
    vim.cmd('edit ' .. vim.fn.stdpath('data') .. '/devcontainer.log')
  end, {})
end,
```

これでdevcontainer.nvimプラグインをLazy.nvimで組み込んでテストすることができます！

