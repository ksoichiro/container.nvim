-- plugin/container.lua
-- container.nvim plugin initialization

-- Skip if already loaded
if vim.g.container_nvim_loaded then
  return
end
vim.g.container_nvim_loaded = 1

-- Command definitions
local function create_commands()
  -- Basic operation commands
  vim.api.nvim_create_user_command('ContainerOpen', function(args)
    require('container').open(args.args ~= '' and args.args or nil)
  end, {
    nargs = '?',
    desc = 'Open container from specified path or current directory',
    complete = 'dir',
  })

  vim.api.nvim_create_user_command('ContainerBuild', function()
    require('container').build()
  end, {
    desc = 'Build container image',
  })

  vim.api.nvim_create_user_command('ContainerStart', function()
    require('container').start()
  end, {
    desc = 'Start container',
  })

  vim.api.nvim_create_user_command('ContainerStop', function()
    require('container').stop()
  end, {
    desc = 'Stop container',
  })

  vim.api.nvim_create_user_command('ContainerKill', function(args)
    if args.bang then
      -- Skip confirmation with :ContainerKill!
      require('container').kill()
    else
      local choice = vim.fn.confirm(
        'Kill container? This will immediately terminate the container and may cause data loss.',
        '&Yes\n&No',
        2 -- Default to No
      )
      if choice == 1 then
        require('container').kill()
      end
    end
  end, {
    bang = true,
    desc = 'Kill container (immediate termination). Use ! to skip confirmation.',
  })

  vim.api.nvim_create_user_command('ContainerTerminate', function(args)
    if args.bang then
      -- Skip confirmation with :ContainerTerminate!
      require('container').terminate()
    else
      local choice = vim.fn.confirm(
        'Terminate container? This will immediately stop the container and may cause data loss.',
        '&Yes\n&No',
        2 -- Default to No
      )
      if choice == 1 then
        require('container').terminate()
      end
    end
  end, {
    bang = true,
    desc = 'Terminate container (immediate termination). Use ! to skip confirmation.',
  })

  vim.api.nvim_create_user_command('ContainerRemove', function(args)
    if args.bang then
      -- Skip confirmation with :ContainerRemove!
      require('container').remove()
    else
      local choice = vim.fn.confirm(
        'Remove container? This will permanently delete the container.',
        '&Yes\n&No',
        2 -- Default to No
      )
      if choice == 1 then
        require('container').remove()
      end
    end
  end, {
    bang = true,
    desc = 'Remove container. Use ! to skip confirmation.',
  })

  vim.api.nvim_create_user_command('ContainerStopRemove', function(args)
    if args.bang then
      -- Skip confirmation with :ContainerStopRemove!
      require('container').stop_and_remove()
    else
      local choice = vim.fn.confirm(
        'Stop and remove container? This will stop the container and permanently delete it.',
        '&Yes\n&No',
        2 -- Default to No
      )
      if choice == 1 then
        require('container').stop_and_remove()
      end
    end
  end, {
    bang = true,
    desc = 'Stop and remove container. Use ! to skip confirmation.',
  })

  vim.api.nvim_create_user_command('ContainerRestart', function()
    require('container').restart()
  end, {
    desc = 'Restart current DevContainer',
  })

  -- Execution and access commands
  vim.api.nvim_create_user_command('ContainerExec', function(args)
    local command_args = vim.split(args.args, ' ', { plain = false, trimempty = true })
    local command = table.concat(command_args, ' ')

    local output, err = require('container').execute(command)
    if output then
      print(output)
    else
      print('Error: ' .. (err or 'Command failed'))
    end
  end, {
    nargs = '+',
    desc = 'Execute command in container (sync)',
  })

  vim.api.nvim_create_user_command('ContainerRun', function(args)
    local opts = {}
    local command_parts = {}
    local i = 1
    local args_list = vim.split(args.args, ' ', { plain = false, trimempty = true })

    -- Parse options
    while i <= #args_list do
      local arg = args_list[i]
      if arg == '--workdir' or arg == '-w' then
        i = i + 1
        if i <= #args_list then
          opts.workdir = args_list[i]
        end
      elseif arg == '--user' or arg == '-u' then
        i = i + 1
        if i <= #args_list then
          opts.user = args_list[i]
        end
      elseif arg == '--env' or arg == '-e' then
        i = i + 1
        if i <= #args_list then
          opts.env = opts.env or {}
          local env_pair = args_list[i]
          local key, value = env_pair:match('([^=]+)=(.*)')
          if key and value then
            opts.env[key] = value
          end
        end
      elseif arg == '--shell' then
        i = i + 1
        if i <= #args_list then
          opts.shell = args_list[i]
        end
      elseif arg == '--timeout' then
        i = i + 1
        if i <= #args_list then
          opts.timeout = tonumber(args_list[i]) * 1000 -- Convert to milliseconds
        end
      elseif arg == '--async' then
        opts.mode = 'async'
        opts.callback = function(result)
          if result.success then
            print('Command completed successfully')
            if result.stdout and result.stdout ~= '' then
              print(result.stdout)
            end
          else
            print('Command failed: ' .. (result.stderr or 'unknown error'))
          end
        end
      elseif arg == '--bg' then
        opts.mode = 'fire_and_forget'
      elseif arg == '--stream' then
        opts.stream = true
      elseif not arg:match('^%-') then
        -- This is part of the command
        table.insert(command_parts, arg)
      end
      i = i + 1
    end

    local command = table.concat(command_parts, ' ')
    if command == '' then
      print('Error: No command specified')
      return
    end

    if opts.stream then
      local job_id = require('container').execute_stream(
        command,
        vim.tbl_extend('force', opts, {
          on_stdout = function(line)
            print('[OUT] ' .. line)
          end,
          on_stderr = function(line)
            print('[ERR] ' .. line)
          end,
          on_exit = function(exit_code)
            print('Command exited with code: ' .. exit_code)
          end,
        })
      )
      if job_id then
        print('Started streaming job: ' .. job_id)
      end
    else
      local result = require('container').execute(command, opts)
      if opts.mode == 'sync' or not opts.mode then
        -- Sync mode - result is output
        if result then
          print(result)
        end
      else
        -- Async/bg mode - result is job ID
        if result then
          print('Started job: ' .. result)
        end
      end
    end
  end, {
    nargs = '+',
    desc = 'Execute command with advanced options',
    complete = function(arg_lead, cmd_line, cursor_pos)
      local completions = {
        '--workdir',
        '-w',
        '--user',
        '-u',
        '--env',
        '-e',
        '--shell',
        '--timeout',
        '--async',
        '--bg',
        '--stream',
      }
      return vim.tbl_filter(function(item)
        return item:match('^' .. vim.pesc(arg_lead))
      end, completions)
    end,
  })

  -- Enhanced terminal commands
  vim.api.nvim_create_user_command('ContainerTerminal', function(args)
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

    require('container').terminal(opts)
  end, {
    nargs = '*',
    desc = 'Open enhanced terminal in container',
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

  vim.api.nvim_create_user_command('ContainerTerminalNew', function(args)
    local name = args.args ~= '' and args.args or nil
    require('container').terminal_new(name)
  end, {
    nargs = '?',
    desc = 'Create new terminal session',
  })

  vim.api.nvim_create_user_command('ContainerTerminalList', function()
    require('container').terminal_list()
  end, {
    desc = 'List all terminal sessions',
  })

  vim.api.nvim_create_user_command('ContainerTerminalClose', function(args)
    local name = args.args ~= '' and args.args or nil
    require('container').terminal_close(name)
  end, {
    nargs = '?',
    desc = 'Close terminal session',
  })

  vim.api.nvim_create_user_command('ContainerTerminalCloseAll', function()
    require('container').terminal_close_all()
  end, {
    desc = 'Close all terminal sessions',
  })

  vim.api.nvim_create_user_command('ContainerTerminalRename', function(args)
    local args_list = vim.split(args.args, ' ')
    local old_name = args_list[1]
    local new_name = args_list[2]
    require('container').terminal_rename(old_name, new_name)
  end, {
    nargs = '*',
    desc = 'Rename terminal session',
  })

  vim.api.nvim_create_user_command('ContainerTerminalNext', function()
    require('container').terminal_next()
  end, {
    desc = 'Switch to next terminal session',
  })

  vim.api.nvim_create_user_command('ContainerTerminalPrev', function()
    require('container').terminal_prev()
  end, {
    desc = 'Switch to previous terminal session',
  })

  vim.api.nvim_create_user_command('ContainerTerminalStatus', function()
    require('container').terminal_status()
  end, {
    desc = 'Show terminal system status',
  })

  vim.api.nvim_create_user_command('ContainerTerminalCleanup', function(args)
    local days = tonumber(args.args) or 30
    require('container').terminal_cleanup_history(days)
  end, {
    nargs = '?',
    desc = 'Clean up old terminal history files',
  })

  -- Information display commands
  vim.api.nvim_create_user_command('ContainerStatus', function()
    require('container').status()
  end, {
    desc = 'Show container status',
  })

  vim.api.nvim_create_user_command('ContainerLogs', function(args)
    local opts = {}
    if args.args:find('follow') or args.args:find('f') then
      opts.follow = true
    end
    require('container').logs(opts)
  end, {
    nargs = '*',
    desc = 'Show container logs',
  })

  -- Configuration and management commands
  vim.api.nvim_create_user_command('ContainerConfig', function(args)
    local config = require('container.config')

    if args.args == '' then
      config.show_config()
    elseif args.args == 'reload' then
      local success = config.reload()
      if success then
        require('container.utils.notify').status('Configuration reloaded successfully')
      else
        require('container.utils.notify').critical('Failed to reload configuration')
      end
    elseif args.args == 'reset' then
      config.reset()
      require('container.utils.notify').status('Configuration reset to defaults')
    elseif args.args == 'env' then
      -- Show environment variable configuration
      local env_vars = config.env.get_supported_vars()
      print('Environment variable configuration options:')
      print('')
      for _, var in ipairs(env_vars) do
        local current = vim.env[var.name]
        if current then
          print(string.format('%s=%s (%s) [ACTIVE]', var.name, current, var.path))
        else
          print(string.format('%s (%s -> %s)', var.name, var.type, var.path))
        end
      end
    elseif args.args == 'validate' then
      local c = config.get()
      local valid, errors = config.validator.validate(c)
      if valid then
        require('container.utils.notify').status('Configuration is valid')
      else
        require('container.utils.notify').critical('Configuration validation failed:')
        for _, err in ipairs(errors) do
          print('  - ' .. err)
        end
      end
    elseif args.args:match('^save ') then
      local filepath = args.args:gsub('^save ', '')
      local success, err = config.save_to_file(filepath)
      if success then
        require('container.utils.notify').status('Configuration saved to ' .. filepath)
      else
        require('container.utils.notify').critical('Failed to save configuration: ' .. (err or 'unknown error'))
      end
    elseif args.args:match('^load ') then
      local filepath = args.args:gsub('^load ', '')
      local success, err = config.load_from_file(filepath)
      if success then
        require('container.utils.notify').status('Configuration loaded from ' .. filepath)
      else
        require('container.utils.notify').critical('Failed to load configuration: ' .. (err or 'unknown error'))
      end
    elseif args.args == 'watch' then
      config.watch_config_file()
      require('container.utils.notify').status('Watching configuration file for changes')
    else
      -- Try to get/set specific value
      local path = args.args
      local value = config.get_value(path)
      if value ~= nil then
        print(string.format('%s = %s', path, vim.inspect(value)))
      else
        print('Configuration path not found: ' .. path)
      end
    end
  end, {
    desc = 'Show or manage container configuration',
    nargs = '*',
    complete = function(arg_lead, cmd_line, cursor_pos)
      -- First argument completions
      if not cmd_line:match('ContainerConfig%s+%S+%s') then
        local completions = {
          'reload',
          'reset',
          'env',
          'validate',
          'save',
          'load',
          'watch',
        }

        -- Add configuration paths
        local schema = require('container.config').get_schema()
        for path, _ in pairs(schema) do
          table.insert(completions, path)
        end

        return vim.tbl_filter(function(item)
          return item:match('^' .. vim.pesc(arg_lead))
        end, completions)
      end

      -- File path completion for save/load
      if cmd_line:match('save%s') or cmd_line:match('load%s') then
        return vim.fn.getcompletion(arg_lead, 'file')
      end

      return {}
    end,
  })

  vim.api.nvim_create_user_command('ContainerConfigSet', function(args)
    local parts = vim.split(args.args, ' ', { plain = false, trimempty = true })
    if #parts < 2 then
      require('container.utils.notify').critical('Usage: ContainerConfigSet <path> <value>')
      return
    end

    local path = parts[1]
    table.remove(parts, 1)
    local value_str = table.concat(parts, ' ')

    -- Try to parse value
    local value
    if value_str == 'true' then
      value = true
    elseif value_str == 'false' then
      value = false
    elseif value_str:match('^%d+$') then
      value = tonumber(value_str)
    elseif value_str:match('^%[.*%]$') then
      -- Try to parse as array
      local ok, parsed = pcall(vim.fn.json_decode, value_str)
      value = ok and parsed or value_str
    else
      value = value_str
    end

    require('container.config').set_value(path, value)
    require('container.utils.notify').status(string.format('Set %s = %s', path, vim.inspect(value)))
  end, {
    desc = 'Set configuration value',
    nargs = '+',
    complete = function(arg_lead, cmd_line, cursor_pos)
      -- Complete configuration paths
      if not cmd_line:match('ContainerConfigSet%s+%S+%s') then
        local schema = require('container.config').get_schema()
        local paths = vim.tbl_keys(schema)
        return vim.tbl_filter(function(item)
          return item:match('^' .. vim.pesc(arg_lead))
        end, paths)
      end
      return {}
    end,
  })

  vim.api.nvim_create_user_command('ContainerAutoOpen', function(args)
    local config = require('container.config')
    local mode = args.args

    if mode == '' then
      local current_mode = config.get_value('auto_open')
      print('Current auto-open configuration:')
      print('  auto_open: ' .. current_mode)
      print('')
      print('Available modes: off, immediate')
      print('Usage: :ContainerAutoOpen <mode>')
    elseif vim.tbl_contains({ 'off', 'immediate' }, mode) then
      config.set_value('auto_open', mode)
      if mode == 'off' then
        require('container.utils.notify').status('Auto-open disabled')
      else
        require('container.utils.notify').status('Auto-open mode set to: ' .. mode)
      end
    else
      require('container.utils.notify').critical('Invalid mode. Available: off, immediate')
    end
  end, {
    nargs = '?',
    desc = 'Configure auto-open behavior when devcontainer.json is detected',
    complete = function()
      return { 'off', 'immediate' }
    end,
  })

  vim.api.nvim_create_user_command('ContainerReset', function()
    require('container').reset()
  end, {
    desc = 'Reset container plugin state',
  })

  vim.api.nvim_create_user_command('ContainerDebug', function()
    require('container').debug_info()
  end, {
    desc = 'Show comprehensive debug information',
  })

  -- LSP handler fix command
  vim.api.nvim_create_user_command('ContainerLspFix', function()
    local proxy_fix = require('container.lsp.strategies.proxy_fix')
    if proxy_fix.auto_enable_if_needed() then
      vim.notify('Container LSP handler fix applied', vim.log.levels.INFO)
    else
      vim.notify('No container_gopls client found', vim.log.levels.WARN)
    end
  end, { desc = 'Apply LSP handler fix for container_gopls' })

  -- LSP related commands
  vim.api.nvim_create_user_command('ContainerLspStatus', function(args)
    local detailed = args.args == 'true' or args.args == 'detailed' or args.args == '-v'
    require('container').lsp_status(detailed)
  end, {
    desc = 'Show LSP status in container (add "true" for detailed info)',
    nargs = '?',
    complete = function()
      return { 'true', 'detailed', '-v' }
    end,
  })

  vim.api.nvim_create_user_command('ContainerLspSetup', function()
    require('container').lsp_setup()
  end, {
    desc = 'Setup LSP in container',
  })

  vim.api.nvim_create_user_command('ContainerLspDebug', function()
    local lsp = require('container.lsp.init')
    local debug_info = lsp.get_debug_info()
    print(vim.inspect(debug_info))
  end, {
    desc = 'Show detailed LSP debugging information',
  })

  vim.api.nvim_create_user_command('ContainerLspAnalyze', function(args)
    local client_name = args.args ~= '' and args.args or 'container_gopls'
    local lsp = require('container.lsp.init')
    local analysis = lsp.analyze_client(client_name)
    print(vim.inspect(analysis))
  end, {
    desc = 'Analyze specific LSP client (default: container_gopls)',
    nargs = '?',
  })

  vim.api.nvim_create_user_command('ContainerLspDiagnose', function()
    require('container').diagnose_lsp()
  end, {
    desc = 'Diagnose LSP server issues',
  })

  vim.api.nvim_create_user_command('ContainerLspRecover', function()
    require('container').recover_lsp()
  end, {
    desc = 'Recover failed LSP servers',
  })

  vim.api.nvim_create_user_command('ContainerLspRetry', function(args)
    if args.args == '' then
      print('Usage: ContainerLspRetry <server_name>')
      print('Available servers: gopls, pylsp, pyright, tsserver, lua_ls, rust_analyzer, clangd, etc.')
    else
      require('container').retry_lsp_server(args.args)
    end
  end, {
    desc = 'Retry specific LSP server setup',
    nargs = '*',
    complete = function()
      return {
        'gopls',
        'pylsp',
        'pyright',
        'tsserver',
        'lua_ls',
        'rust_analyzer',
        'clangd',
        'jdtls',
        'solargraph',
        'intelephense',
      }
    end,
  })

  -- Port management commands
  vim.api.nvim_create_user_command('ContainerPorts', function()
    require('container').show_ports()
  end, {
    desc = 'Show detailed port forwarding information',
  })

  vim.api.nvim_create_user_command('ContainerPortStats', function()
    require('container').show_port_stats()
  end, {
    desc = 'Show port allocation statistics',
  })

  -- Utility commands
  vim.api.nvim_create_user_command('ContainerReconnect', function()
    require('container').reconnect()
  end, {
    desc = 'Reconnect to existing container',
  })

  -- Picker integration commands (supports telescope, fzf-lua, vim.ui.select)
  vim.api.nvim_create_user_command('ContainerPicker', function()
    local picker = require('container.ui.picker')
    picker.containers()
  end, {
    desc = 'Open container picker',
  })

  vim.api.nvim_create_user_command('ContainerSessionPicker', function()
    local picker = require('container.ui.picker')
    picker.sessions()
  end, {
    desc = 'Open terminal session picker',
  })

  vim.api.nvim_create_user_command('ContainerPortPicker', function()
    local picker = require('container.ui.picker')
    picker.ports()
  end, {
    desc = 'Open port management picker',
  })

  vim.api.nvim_create_user_command('ContainerHistoryPicker', function()
    local picker = require('container.ui.picker')
    picker.history()
  end, {
    desc = 'Open command history picker',
  })

  -- Test runner commands
  vim.api.nvim_create_user_command('ContainerTestNearest', function(args)
    local opts = {}
    if args.args and args.args ~= '' then
      opts.output_mode = args.args
    end
    require('container.test_runner').run_nearest_test(opts)
  end, {
    desc = 'Run nearest test in container',
    nargs = '?',
    complete = function()
      return { 'buffer', 'terminal' }
    end,
  })

  vim.api.nvim_create_user_command('ContainerTestFile', function(args)
    local opts = {}
    if args.args and args.args ~= '' then
      opts.output_mode = args.args
    end
    require('container.test_runner').run_file_tests(opts)
  end, {
    desc = 'Run all tests in current file in container',
    nargs = '?',
    complete = function()
      return { 'buffer', 'terminal' }
    end,
  })

  vim.api.nvim_create_user_command('ContainerTestSuite', function(args)
    local opts = {}
    if args.args and args.args ~= '' then
      opts.output_mode = args.args
    end
    require('container.test_runner').run_suite_tests(opts)
  end, {
    desc = 'Run entire test suite in container',
    nargs = '?',
    complete = function()
      return { 'buffer', 'terminal' }
    end,
  })

  vim.api.nvim_create_user_command('ContainerTestSetup', function()
    require('container.test_runner').setup()
  end, {
    desc = 'Setup test plugin integrations',
  })

  -- DAP (Debug Adapter Protocol) commands
  vim.api.nvim_create_user_command('ContainerDapStart', function(args)
    local opts = {}
    if args.args and args.args ~= '' then
      opts.language = args.args
    end
    require('container').dap_start(opts)
  end, {
    desc = 'Start debugging in container',
    nargs = '?',
    complete = function()
      return { 'python', 'javascript', 'typescript', 'go', 'rust', 'cpp', 'java' }
    end,
  })

  vim.api.nvim_create_user_command('ContainerDapStop', function()
    require('container').dap_stop()
  end, {
    desc = 'Stop debugging session',
  })

  vim.api.nvim_create_user_command('ContainerDapStatus', function()
    local status = require('container').dap_status()
    require('container.utils.notify').info('DAP Status: ' .. status)
  end, {
    desc = 'Show DAP debugging status',
  })

  vim.api.nvim_create_user_command('ContainerDapSessions', function()
    local sessions = require('container').dap_list_sessions()
    if #sessions == 0 then
      require('container.utils.notify').info('No active debug sessions')
    else
      local notify = require('container.utils.notify')
      notify.info('Active Debug Sessions:')
      for _, session in ipairs(sessions) do
        notify.info(
          string.format(
            '  [%s] %s - %s (started: %s)',
            session.id,
            session.container,
            session.language,
            os.date('%Y-%m-%d %H:%M:%S', session.started_at)
          )
        )
      end
    end
  end, {
    desc = 'List active debug sessions',
  })

  -- Force remove container (for shell compatibility issues)
  vim.api.nvim_create_user_command('ContainerRemove', function(args)
    local docker = require('container.docker.init')

    if args.bang then
      -- Force remove current container
      local current = require('container').get_current_container()
      if current then
        local success = docker.force_remove_container(current.id)
        if success then
          print('✓ Removed container: ' .. current.name)
        else
          print('✗ Failed to remove container: ' .. current.name)
        end
      else
        print('No active container found')
      end
    else
      print('Use :ContainerRemove! to force remove the current container')
      print('This will permanently delete the container and all its data.')
    end
  end, {
    bang = true,
    desc = 'Force remove current container. Use ! to confirm removal.',
  })
end

-- Create autocommand group
local augroup = vim.api.nvim_create_augroup('ContainerNvim', { clear = true })

-- Monitor changes to devcontainer.json file
vim.api.nvim_create_autocmd({ 'BufWritePost' }, {
  group = augroup,
  pattern = { 'devcontainer.json', '.devcontainer/devcontainer.json' },
  callback = function()
    require('container.utils.notify').status('devcontainer.json updated. You may need to rebuild the container.')
  end,
})

-- Auto-detection when opening project directory (optional)
vim.api.nvim_create_autocmd({ 'VimEnter', 'DirChanged' }, {
  group = augroup,
  callback = function()
    local config = require('container.config').get()
    if config and config.auto_open == 'immediate' then
      -- Check for devcontainer.json existence
      local parser = require('container.parser')
      local container_path = parser.find_devcontainer_json()
      if container_path then
        vim.defer_fn(function()
          -- Check if container is already running first
          local container = require('container')
          local state = container.get_state()
          if not state.current_container then
            require('container.utils.notify').status('Auto-opening container...')
            container.open()
          end
        end, config.auto_open_delay or 2000)
      end
    end
  end,
})

-- Create commands
create_commands()

-- Set global function (for Lua API access)
_G.container = require('container')
