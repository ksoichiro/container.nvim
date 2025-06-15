-- plugin/devcontainer.lua
-- devcontainer.nvim plugin initialization

-- Skip if already loaded
if vim.g.devcontainer_nvim_loaded then
  return
end
vim.g.devcontainer_nvim_loaded = 1

-- Command definitions
local function create_commands()
  -- Basic operation commands
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

  vim.api.nvim_create_user_command('DevcontainerKill', function()
    require('devcontainer').kill()
  end, {
    desc = 'Kill devcontainer (immediate termination)',
  })

  vim.api.nvim_create_user_command('DevcontainerTerminate', function()
    require('devcontainer').terminate()
  end, {
    desc = 'Terminate devcontainer (immediate termination)',
  })

  vim.api.nvim_create_user_command('DevcontainerRestart', function()
    require('devcontainer').stop()
    vim.defer_fn(function()
      require('devcontainer').start()
    end, 1000)
  end, {
    desc = 'Restart devcontainer',
  })

  -- Execution and access commands
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

  -- Information display commands
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

  -- Configuration and management commands
  vim.api.nvim_create_user_command('DevcontainerConfig', function()
    require('devcontainer.config').show_config()
  end, {
    desc = 'Show current configuration',
  })

  vim.api.nvim_create_user_command('DevcontainerAutoStart', function(args)
    local config = require('devcontainer.config')
    local mode = args.args

    if mode == '' then
      local current_mode = config.get_value('auto_start_mode')
      local auto_start = config.get_value('auto_start')
      print('Current auto-start configuration:')
      print('  auto_start: ' .. tostring(auto_start))
      print('  auto_start_mode: ' .. current_mode)
      print('')
      print('Available modes: off, notify, prompt, immediate')
      print('Usage: :DevcontainerAutoStart <mode>')
    elseif vim.tbl_contains({ 'off', 'notify', 'prompt', 'immediate' }, mode) then
      config.set_value('auto_start', mode ~= 'off')
      config.set_value('auto_start_mode', mode)
      if mode == 'off' then
        vim.notify('Auto-start disabled', vim.log.levels.INFO, { title = 'devcontainer.nvim' })
      else
        vim.notify('Auto-start mode set to: ' .. mode, vim.log.levels.INFO, { title = 'devcontainer.nvim' })
      end
    else
      vim.notify('Invalid mode. Available: off, notify, prompt, immediate', vim.log.levels.ERROR)
    end
  end, {
    nargs = '?',
    desc = 'Configure auto-start behavior',
    complete = function()
      return { 'off', 'notify', 'prompt', 'immediate' }
    end,
  })

  vim.api.nvim_create_user_command('DevcontainerReset', function()
    require('devcontainer').reset()
  end, {
    desc = 'Reset devcontainer plugin state',
  })

  vim.api.nvim_create_user_command('DevcontainerDebug', function()
    require('devcontainer').debug_info()
  end, {
    desc = 'Show comprehensive debug information',
  })

  -- LSP related commands
  vim.api.nvim_create_user_command('DevcontainerLspStatus', function()
    require('devcontainer').lsp_status()
  end, {
    desc = 'Show LSP status in devcontainer',
  })

  vim.api.nvim_create_user_command('DevcontainerLspSetup', function()
    require('devcontainer').lsp_setup()
  end, {
    desc = 'Setup LSP servers in devcontainer',
  })

  -- Port management commands
  vim.api.nvim_create_user_command('DevcontainerPorts', function()
    require('devcontainer').show_ports()
  end, {
    desc = 'Show detailed port forwarding information',
  })

  vim.api.nvim_create_user_command('DevcontainerPortStats', function()
    require('devcontainer').show_port_stats()
  end, {
    desc = 'Show port allocation statistics',
  })

  -- Utility commands
  vim.api.nvim_create_user_command('DevcontainerReconnect', function()
    require('devcontainer').reconnect()
  end, {
    desc = 'Reconnect to existing devcontainer',
  })
end

-- Create autocommand group
local augroup = vim.api.nvim_create_augroup('DevcontainerNvim', { clear = true })

-- Monitor changes to devcontainer.json file
vim.api.nvim_create_autocmd({ 'BufWritePost' }, {
  group = augroup,
  pattern = { 'devcontainer.json', '.devcontainer/devcontainer.json' },
  callback = function()
    vim.notify(
      'devcontainer.json updated. You may need to rebuild the container.',
      vim.log.levels.INFO,
      { title = 'devcontainer.nvim' }
    )
  end,
})

-- Auto-detection when opening project directory (optional)
vim.api.nvim_create_autocmd({ 'VimEnter', 'DirChanged' }, {
  group = augroup,
  callback = function()
    local config = require('devcontainer.config').get()
    if config and config.auto_start and config.auto_start_mode ~= 'off' then
      -- Check for devcontainer.json existence
      local parser = require('devcontainer.parser')
      local devcontainer_path = parser.find_devcontainer_json()
      if devcontainer_path then
        -- Handle different auto-start modes
        if config.auto_start_mode == 'notify' then
          vim.notify(
            'Found devcontainer.json. Use :DevcontainerOpen to start.',
            vim.log.levels.INFO,
            { title = 'devcontainer.nvim' }
          )
        elseif config.auto_start_mode == 'prompt' then
          vim.defer_fn(function()
            local choice =
              vim.fn.confirm('Found devcontainer.json. Start devcontainer?', '&Yes\n&No\n&Always (change config)', 1)
            if choice == 1 then
              require('devcontainer').open()
            elseif choice == 3 then
              require('devcontainer.config').set_value('auto_start_mode', 'immediate')
              vim.notify(
                'Auto-start mode changed to immediate. Restart Neovim to apply.',
                vim.log.levels.INFO,
                { title = 'devcontainer.nvim' }
              )
            end
          end, 500)
        elseif config.auto_start_mode == 'immediate' then
          vim.defer_fn(function()
            -- Check if container is already running first
            local devcontainer = require('devcontainer')
            local state = devcontainer.get_state()
            if not state.current_container then
              vim.notify('Auto-starting devcontainer...', vim.log.levels.INFO, { title = 'devcontainer.nvim' })
              devcontainer.open()
            end
          end, config.auto_start_delay or 2000)
        end
      end
    end
  end,
})

-- Create commands
create_commands()

-- Set global function (for Lua API access)
_G.devcontainer = require('devcontainer')
