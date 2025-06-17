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

  vim.api.nvim_create_user_command('DevcontainerKill', function(args)
    if args.bang then
      -- Skip confirmation with :DevcontainerKill!
      require('devcontainer').kill()
    else
      local choice = vim.fn.confirm(
        'Kill devcontainer? This will immediately terminate the container and may cause data loss.',
        '&Yes\n&No',
        2 -- Default to No
      )
      if choice == 1 then
        require('devcontainer').kill()
      end
    end
  end, {
    bang = true,
    desc = 'Kill devcontainer (immediate termination). Use ! to skip confirmation.',
  })

  vim.api.nvim_create_user_command('DevcontainerTerminate', function(args)
    if args.bang then
      -- Skip confirmation with :DevcontainerTerminate!
      require('devcontainer').terminate()
    else
      local choice = vim.fn.confirm(
        'Terminate devcontainer? This will immediately stop the container and may cause data loss.',
        '&Yes\n&No',
        2 -- Default to No
      )
      if choice == 1 then
        require('devcontainer').terminate()
      end
    end
  end, {
    bang = true,
    desc = 'Terminate devcontainer (immediate termination). Use ! to skip confirmation.',
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

  -- Enhanced terminal commands
  vim.api.nvim_create_user_command('DevcontainerTerminal', function(args)
    local opts = {}
    local remaining_args = {}

    -- Parse arguments
    for _, arg in ipairs(vim.split(args.args, ' ')) do
      if arg:match('^%-%-position=') then
        opts.position = arg:gsub('^%-%-position=', '')
      elseif arg:match('^%-%-name=') then
        opts.name = arg:gsub('^%-%-name=', '')
      elseif arg:match('^%-%-shell=') then
        opts.shell = arg:gsub('^%-%-shell=', '')
      elseif arg:match('^%-%-size=') then
        local size = tonumber(arg:gsub('^%-%-size=', ''))
        if size then
          opts.width = size
          opts.height = size
        end
      elseif arg == '--split' then
        opts.position = 'split'
      elseif arg == '--vsplit' then
        opts.position = 'vsplit'
      elseif arg == '--tab' then
        opts.position = 'tab'
      elseif arg == '--float' then
        opts.position = 'float'
      elseif arg ~= '' then
        table.insert(remaining_args, arg)
      end
    end

    -- First remaining arg is session name if provided
    if #remaining_args > 0 then
      opts.name = remaining_args[1]
    end

    require('devcontainer').terminal(opts)
  end, {
    nargs = '*',
    desc = 'Open enhanced terminal in devcontainer',
    complete = function(arg_lead, cmd_line, cursor_pos)
      local completions = {
        '--position=split',
        '--position=vsplit',
        '--position=tab',
        '--position=float',
        '--split',
        '--vsplit',
        '--tab',
        '--float',
        '--name=',
        '--shell=',
        '--size=',
      }
      return vim.tbl_filter(function(item)
        return item:match('^' .. vim.pesc(arg_lead))
      end, completions)
    end,
  })

  vim.api.nvim_create_user_command('DevcontainerTerminalNew', function(args)
    local name = args.args ~= '' and args.args or nil
    require('devcontainer').terminal_new(name)
  end, {
    nargs = '?',
    desc = 'Create new terminal session',
  })

  vim.api.nvim_create_user_command('DevcontainerTerminalList', function()
    require('devcontainer').terminal_list()
  end, {
    desc = 'List all terminal sessions',
  })

  vim.api.nvim_create_user_command('DevcontainerTerminalClose', function(args)
    local name = args.args ~= '' and args.args or nil
    require('devcontainer').terminal_close(name)
  end, {
    nargs = '?',
    desc = 'Close terminal session',
  })

  vim.api.nvim_create_user_command('DevcontainerTerminalCloseAll', function()
    require('devcontainer').terminal_close_all()
  end, {
    desc = 'Close all terminal sessions',
  })

  vim.api.nvim_create_user_command('DevcontainerTerminalRename', function(args)
    local args_list = vim.split(args.args, ' ')
    local old_name = args_list[1]
    local new_name = args_list[2]
    require('devcontainer').terminal_rename(old_name, new_name)
  end, {
    nargs = '*',
    desc = 'Rename terminal session',
  })

  vim.api.nvim_create_user_command('DevcontainerTerminalNext', function()
    require('devcontainer').terminal_next()
  end, {
    desc = 'Switch to next terminal session',
  })

  vim.api.nvim_create_user_command('DevcontainerTerminalPrev', function()
    require('devcontainer').terminal_prev()
  end, {
    desc = 'Switch to previous terminal session',
  })

  vim.api.nvim_create_user_command('DevcontainerTerminalStatus', function()
    require('devcontainer').terminal_status()
  end, {
    desc = 'Show terminal system status',
  })

  vim.api.nvim_create_user_command('DevcontainerTerminalCleanup', function(args)
    local days = tonumber(args.args) or 30
    require('devcontainer').terminal_cleanup_history(days)
  end, {
    nargs = '?',
    desc = 'Clean up old terminal history files',
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
        require('devcontainer.utils.notify').status('Auto-start disabled')
      else
        require('devcontainer.utils.notify').status('Auto-start mode set to: ' .. mode)
      end
    else
      require('devcontainer.utils.notify').critical('Invalid mode. Available: off, notify, prompt, immediate')
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

  -- Picker integration commands (supports telescope, fzf-lua, vim.ui.select)
  vim.api.nvim_create_user_command('DevcontainerPicker', function()
    local picker = require('devcontainer.ui.picker')
    picker.containers()
  end, {
    desc = 'Open devcontainer picker',
  })

  vim.api.nvim_create_user_command('DevcontainerSessionPicker', function()
    local picker = require('devcontainer.ui.picker')
    picker.sessions()
  end, {
    desc = 'Open terminal session picker',
  })

  vim.api.nvim_create_user_command('DevcontainerPortPicker', function()
    local picker = require('devcontainer.ui.picker')
    picker.ports()
  end, {
    desc = 'Open port management picker',
  })

  vim.api.nvim_create_user_command('DevcontainerHistoryPicker', function()
    local picker = require('devcontainer.ui.picker')
    picker.history()
  end, {
    desc = 'Open command history picker',
  })

  -- Test runner commands
  vim.api.nvim_create_user_command('DevcontainerTestNearest', function()
    require('devcontainer.test_runner').run_nearest_test()
  end, {
    desc = 'Run nearest test in devcontainer',
  })

  vim.api.nvim_create_user_command('DevcontainerTestFile', function()
    require('devcontainer.test_runner').run_file_tests()
  end, {
    desc = 'Run all tests in current file in devcontainer',
  })

  vim.api.nvim_create_user_command('DevcontainerTestSuite', function()
    require('devcontainer.test_runner').run_suite_tests()
  end, {
    desc = 'Run entire test suite in devcontainer',
  })

  vim.api.nvim_create_user_command('DevcontainerTestSetup', function()
    require('devcontainer.test_runner').setup()
  end, {
    desc = 'Setup test plugin integrations',
  })

  -- Terminal-based test commands
  vim.api.nvim_create_user_command('DevcontainerTestNearestTerminal', function()
    local test_runner = require('devcontainer.test_runner')
    test_runner.run_nearest_test({ output_mode = 'terminal' })
  end, {
    desc = 'Run nearest test in container terminal',
  })

  vim.api.nvim_create_user_command('DevcontainerTestFileTerminal', function()
    local test_runner = require('devcontainer.test_runner')
    test_runner.run_file_tests({ output_mode = 'terminal' })
  end, {
    desc = 'Run file tests in container terminal',
  })

  vim.api.nvim_create_user_command('DevcontainerTestSuiteTerminal', function()
    local test_runner = require('devcontainer.test_runner')
    test_runner.run_suite_tests({ output_mode = 'terminal' })
  end, {
    desc = 'Run test suite in container terminal',
  })
end

-- Create autocommand group
local augroup = vim.api.nvim_create_augroup('DevcontainerNvim', { clear = true })

-- Monitor changes to devcontainer.json file
vim.api.nvim_create_autocmd({ 'BufWritePost' }, {
  group = augroup,
  pattern = { 'devcontainer.json', '.devcontainer/devcontainer.json' },
  callback = function()
    require('devcontainer.utils.notify').status('devcontainer.json updated. You may need to rebuild the container.')
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
          require('devcontainer.utils.notify').status('Found devcontainer.json. Use :DevcontainerOpen to start.')
        elseif config.auto_start_mode == 'prompt' then
          vim.defer_fn(function()
            local choice =
              vim.fn.confirm('Found devcontainer.json. Start devcontainer?', '&Yes\n&No\n&Always (change config)', 1)
            if choice == 1 then
              require('devcontainer').open()
            elseif choice == 3 then
              require('devcontainer.config').set_value('auto_start_mode', 'immediate')
              require('devcontainer.utils.notify').status(
                'Auto-start mode changed to immediate. Restart Neovim to apply.'
              )
            end
          end, 500)
        elseif config.auto_start_mode == 'immediate' then
          vim.defer_fn(function()
            -- Check if container is already running first
            local devcontainer = require('devcontainer')
            local state = devcontainer.get_state()
            if not state.current_container then
              require('devcontainer.utils.notify').status('Auto-starting devcontainer...')
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
