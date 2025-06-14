-- plugin/devcontainer.lua
-- devcontainer.nvim プラグイン初期化

-- 既に読み込まれている場合はスキップ
if vim.g.devcontainer_nvim_loaded then
  return
end
vim.g.devcontainer_nvim_loaded = 1

-- コマンドの定義
local function create_commands()
  -- 基本操作コマンド
  vim.api.nvim_create_user_command('DevcontainerOpen', function(args)
    require('devcontainer').open(args.args ~= '' and args.args or nil)
  end, {
    nargs = '?',
    desc = 'Open devcontainer from specified path or current directory',
    complete = 'dir',
  })

  vim.api.nvim_create_user_command('DevcontainerBuild', function()
    require('devcontainer').build()
  end, {
    desc = 'Build devcontainer image',
  })

  vim.api.nvim_create_user_command('DevcontainerStart', function()
    require('devcontainer').start()
  end, {
    desc = 'Start devcontainer',
  })

  vim.api.nvim_create_user_command('DevcontainerStop', function()
    require('devcontainer').stop()
  end, {
    desc = 'Stop devcontainer',
  })

  vim.api.nvim_create_user_command('DevcontainerRestart', function()
    require('devcontainer').stop()
    vim.defer_fn(function()
      require('devcontainer').start()
    end, 1000)
  end, {
    desc = 'Restart devcontainer',
  })

  -- 実行・アクセスコマンド
  vim.api.nvim_create_user_command('DevcontainerExec', function(args)
    require('devcontainer').exec(args.args)
  end, {
    nargs = '+',
    desc = 'Execute command in devcontainer',
  })

  vim.api.nvim_create_user_command('DevcontainerShell', function(args)
    local shell = args.args ~= '' and args.args or nil
    require('devcontainer').shell(shell)
  end, {
    nargs = '?',
    desc = 'Open shell in devcontainer',
  })

  -- 情報表示コマンド
  vim.api.nvim_create_user_command('DevcontainerStatus', function()
    require('devcontainer').status()
  end, {
    desc = 'Show devcontainer status',
  })

  vim.api.nvim_create_user_command('DevcontainerLogs', function(args)
    local opts = {}
    if args.args:find('follow') or args.args:find('f') then
      opts.follow = true
    end
    require('devcontainer').logs(opts)
  end, {
    nargs = '*',
    desc = 'Show devcontainer logs',
  })

  -- 設定・管理コマンド
  vim.api.nvim_create_user_command('DevcontainerConfig', function()
    require('devcontainer.config').show_config()
  end, {
    desc = 'Show current configuration',
  })

  vim.api.nvim_create_user_command('DevcontainerReset', function()
    require('devcontainer').reset()
  end, {
    desc = 'Reset devcontainer plugin state',
  })

  vim.api.nvim_create_user_command('DevcontainerDebug', function()
    require('devcontainer').debug_info()
  end, {
    desc = 'Show debug information',
  })
end

-- オートコマンドグループの作成
local augroup = vim.api.nvim_create_augroup('DevcontainerNvim', { clear = true })

-- devcontainer.json ファイルの変更を監視
vim.api.nvim_create_autocmd({'BufWritePost'}, {
  group = augroup,
  pattern = {'devcontainer.json', '.devcontainer/devcontainer.json'},
  callback = function()
    vim.notify('devcontainer.json updated. You may need to rebuild the container.', 
               vim.log.levels.INFO, 
               { title = 'devcontainer.nvim' })
  end,
})

-- プロジェクトディレクトリを開いた時の自動検出（オプション）
vim.api.nvim_create_autocmd({'VimEnter', 'DirChanged'}, {
  group = augroup,
  callback = function()
    local config = require('devcontainer.config').get()
    if config and config.auto_start then
      -- devcontainer.json の存在確認
      local parser = require('devcontainer.parser')
      local devcontainer_path = parser.find_devcontainer_json()
      if devcontainer_path then
        vim.notify('Found devcontainer.json. Use :DevcontainerOpen to start.', 
                   vim.log.levels.INFO, 
                   { title = 'devcontainer.nvim' })
      end
    end
  end,
})

-- コマンドを作成
create_commands()

-- グローバル関数の設定（Lua APIアクセス用）
_G.devcontainer = require('devcontainer')

