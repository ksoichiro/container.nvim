-- lua/devcontainer/test_runner.lua
-- Integration with test runner plugins for devcontainer environments

local M = {}

local log = require('devcontainer.utils.log')

-- Supported test plugins configuration
local test_plugins = {
  -- vim-test/vim-test
  vim_test = {
    name = 'vim-test',
    available = function()
      return vim.fn.exists(':TestNearest') == 2
    end,
    commands = {
      'TestNearest',
      'TestFile',
      'TestSuite',
      'TestLast',
      'TestVisit',
    },
  },
  -- klen/nvim-test
  nvim_test = {
    name = 'nvim-test',
    available = function()
      return vim.fn.exists(':TestNearest') == 2 and vim.g.test_runner ~= nil
    end,
    commands = {
      'TestNearest',
      'TestFile',
      'TestSuite',
      'TestLast',
      'TestEdit',
      'TestInfo',
    },
  },
  -- nvim-neotest/neotest
  neotest = {
    name = 'neotest',
    available = function()
      local ok = pcall(require, 'neotest')
      return ok
    end,
    commands = {}, -- Neotest uses Lua API rather than commands
  },
}

-- Command wrapper configuration (exported for extensibility)
M.wrapper_config = {
  -- Language-specific test command patterns
  go = {
    test_nearest = 'go test -v -run "^%s$" ./...',
    test_file = 'go test -v ./%s',
    test_suite = 'go test -v ./...',
  },
  python = {
    test_nearest = 'python -m pytest -xvs %s::%s',
    test_file = 'python -m pytest -xvs %s',
    test_suite = 'python -m pytest',
  },
  javascript = {
    test_nearest = 'npm test -- %s -t "%s"',
    test_file = 'npm test %s',
    test_suite = 'npm test',
  },
  typescript = {
    test_nearest = 'npm test -- %s -t "%s"',
    test_file = 'npm test %s',
    test_suite = 'npm test',
  },
  rust = {
    test_nearest = 'cargo test %s',
    test_file = 'cargo test --test %s',
    test_suite = 'cargo test',
  },
}

-- Get the current container and configuration
local function get_container_info()
  local devcontainer = require('devcontainer')
  local state = devcontainer.get_state()

  if not state or not state.current_container then
    return nil, nil
  end

  return state.current_container, state.current_config
end

-- Execute test command in container
function M.run_test_in_container(test_command, opts)
  opts = opts or {}

  local container_id, config = get_container_info()
  if not container_id then
    log.warn('No active devcontainer found, running test locally')
    vim.cmd(test_command)
    return
  end

  -- Get test integration config
  local global_config = require('devcontainer.config').get()
  local test_config = global_config.test_integration or {}
  local output_mode = opts.output_mode or test_config.output_mode or 'buffer'

  log.info('Running test in container: %s', test_command)

  if output_mode == 'terminal' then
    -- Run in devcontainer terminal for interactive output
    local devcontainer = require('devcontainer')
    if devcontainer.terminal then
      -- Silent execution for terminal mode - output will appear in terminal

      -- Use consistent session name for test terminal
      local session_name = 'test'

      -- Try to get existing test session first
      local session_manager = require('devcontainer.terminal.session')
      local existing_session = session_manager.get_session(session_name)

      local success = false
      if existing_session then
        -- Switch to existing terminal and clear it
        local display = require('devcontainer.terminal.display')
        success = display.switch_to_session(existing_session)
        if success then
          -- Clear the terminal and send new command
          vim.defer_fn(function()
            if existing_session.job_id then
              -- Clear terminal
              vim.fn.chansend(existing_session.job_id, 'clear\n')
              -- Send test command
              vim.fn.chansend(existing_session.job_id, test_command .. '\n')
              log.info('Sent test command to existing terminal session: %s', session_name)
            end
          end, 100)
        end
      else
        -- Create new terminal session
        success = devcontainer.terminal({
          name = session_name,
          title = 'DevContainer Tests',
          position = 'split', -- Use split for better visibility
        })

        if success then
          -- Send the test command to the new terminal after a short delay
          vim.defer_fn(function()
            local session = session_manager.get_session(session_name)
            if session and session.job_id then
              -- Send command to the terminal
              vim.fn.chansend(session.job_id, test_command .. '\n')
              log.info('Sent test command to new terminal session: %s', session_name)
            else
              log.warn('Could not find terminal session or job_id for: %s', session_name)
            end
          end, 500) -- 500ms delay to ensure terminal is ready
        end
      end

      return -- Exit early - don't run buffer mode
    else
      -- Terminal not available, fall back to buffer mode
      log.warn('Terminal mode requested but devcontainer terminal not available, falling back to buffer mode')
      -- Show fallback message only once
      print('⚠️  Terminal not available, running in buffer mode')
      -- Fall through to buffer mode
    end
  end

  -- Buffer mode: Build Docker exec command and execute
  -- Show where test is running (only for buffer mode)
  local container_name = vim.fn.fnamemodify(container_id, ':t:r')
  print('🐳 Running test in container: ' .. container_name)
  print('📦 Command: ' .. test_command)
  print('---')

  local docker = require('devcontainer.docker.init')
  local environment = require('devcontainer.environment')

  local exec_args = {
    'exec',
    '-i',
  }

  -- Add environment-specific args (includes user and env vars)
  local env_args = environment.build_exec_args(config)
  for _, arg in ipairs(env_args) do
    table.insert(exec_args, arg)
  end

  -- Set working directory
  local workspace_folder = config.workspaceFolder or '/workspace'
  table.insert(exec_args, '-w')
  table.insert(exec_args, workspace_folder)

  -- Add container and test command
  table.insert(exec_args, container_id)
  table.insert(exec_args, 'bash')
  table.insert(exec_args, '-c')
  table.insert(exec_args, test_command)

  -- Buffer mode: execute and show results in Neovim
  print('---')

  -- Execute test asynchronously
  docker.run_docker_command_async(exec_args, {}, function(result)
    vim.schedule(function()
      if result.success then
        -- Display test output
        local lines = vim.split(result.stdout or '', '\n')
        for _, line in ipairs(lines) do
          if line ~= '' then
            print(line)
          end
        end

        if result.stderr and result.stderr ~= '' then
          vim.api.nvim_err_writeln('Test stderr: ' .. result.stderr)
        end

        -- Show completion message
        print('---')
        print('✅ Test execution completed in container')
      else
        vim.api.nvim_err_writeln('Test failed with exit code: ' .. (result.code or 'unknown'))
        if result.stderr then
          vim.api.nvim_err_writeln('Error: ' .. result.stderr)
        end
        print('---')
        print('❌ Test execution failed in container')
      end
    end)
  end)
end

-- Hook into vim-test commands
function M.setup_vim_test()
  if not test_plugins.vim_test.available() then
    return false
  end

  log.info('Setting up vim-test integration')

  -- Override test strategies
  vim.g.test_strategy = 'custom'
  vim.g['test#custom_strategies'] = vim.g['test#custom_strategies'] or {}
  vim.g['test#custom_strategies']['devcontainer'] = function(cmd)
    M.run_test_in_container(cmd)
  end

  -- Set devcontainer as the custom strategy
  vim.g.test_strategy = 'devcontainer'

  return true
end

-- Hook into nvim-test commands
function M.setup_nvim_test()
  if not test_plugins.nvim_test.available() then
    return false
  end

  log.info('Setting up nvim-test integration')

  -- nvim-test uses similar strategy system
  vim.g.test_strategy = 'custom'
  vim.g.test_custom_strategies = vim.g.test_custom_strategies or {}
  vim.g.test_custom_strategies.devcontainer = function(cmd)
    M.run_test_in_container(cmd)
  end

  return true
end

-- Hook into neotest
function M.setup_neotest()
  local ok, neotest = pcall(require, 'neotest')
  if not ok then
    return false
  end

  log.info('Setting up neotest integration')

  -- Create a custom neotest strategy
  local devcontainer_strategy = function(spec)
    local container_id, config = get_container_info()
    if not container_id then
      -- Fallback to default strategy
      return spec
    end

    -- Modify the command to run in container
    local original_command = spec.command
    local docker_command = {
      'docker',
      'exec',
      '-i',
    }

    -- Add user if specified
    if config.remoteUser or config.remote_user then
      table.insert(docker_command, '-u')
      table.insert(docker_command, config.remoteUser or config.remote_user)
    end

    -- Add working directory
    table.insert(docker_command, '-w')
    table.insert(docker_command, config.workspaceFolder or '/workspace')

    -- Add container ID
    table.insert(docker_command, container_id)

    -- Add original command
    for _, part in ipairs(original_command) do
      table.insert(docker_command, part)
    end

    spec.command = docker_command
    return spec
  end

  -- Wrap existing strategies
  local original_get_strategy = neotest.get_strategy
  neotest.get_strategy = function(name)
    local strategy = original_get_strategy(name)
    return function(spec)
      return devcontainer_strategy(strategy(spec))
    end
  end

  return true
end

-- Setup all available test integrations
function M.setup()
  local integrations = {
    { name = 'vim-test', setup = M.setup_vim_test },
    { name = 'nvim-test', setup = M.setup_nvim_test },
    { name = 'neotest', setup = M.setup_neotest },
  }

  local setup_count = 0
  for _, integration in ipairs(integrations) do
    if integration.setup() then
      setup_count = setup_count + 1
      log.info('Successfully set up %s integration', integration.name)
    end
  end

  if setup_count == 0 then
    log.debug('No test plugins found to integrate with')
  else
    log.info('Set up %d test plugin integration(s)', setup_count)
  end

  return setup_count > 0
end

-- Manual test runner for when no plugin is available
function M.run_nearest_test(opts)
  local container_id, config = get_container_info()
  if not container_id then
    vim.api.nvim_err_writeln('No active devcontainer')
    return
  end

  -- Detect language and get test pattern
  local ft = vim.bo.filetype
  local test_config = M.wrapper_config[ft]

  if not test_config then
    vim.api.nvim_err_writeln('No test configuration for filetype: ' .. ft)
    return
  end

  -- Get current test name (simple pattern matching)
  local current_line = vim.api.nvim_get_current_line()
  local test_name = nil

  -- Language-specific test detection
  if ft == 'go' then
    test_name = current_line:match('func%s+(Test%w+)')
    -- If not found on current line, search nearby lines
    if not test_name then
      local current_line_num = vim.fn.line('.')
      for i = -3, 3 do
        local line_content = vim.fn.getline(current_line_num + i)
        test_name = line_content:match('func%s+(Test%w+)')
        if test_name then
          break
        end
      end
    end
  elseif ft == 'python' then
    test_name = current_line:match('def%s+(test_%w+)')
  elseif ft == 'javascript' or ft == 'typescript' then
    test_name = current_line:match('it%s*%([\'"](.-)[\'"]')
      or current_line:match('test%s*%([\'"](.-)[\'"]')
      or current_line:match('describe%s*%([\'"](.-)[\'"]')
  elseif ft == 'rust' then
    test_name = current_line:match('#%[test%]')
    if test_name then
      -- Look for the function name on the next line
      local next_line = vim.api.nvim_buf_get_lines(0, vim.fn.line('.'), vim.fn.line('.') + 1, false)[1]
      test_name = next_line and next_line:match('fn%s+(%w+)')
    end
  end

  if not test_name then
    vim.api.nvim_err_writeln('Could not detect test name at cursor position')
    return
  end

  -- Build test command
  local test_command = string.format(test_config.test_nearest, test_name)

  -- Run test in container
  M.run_test_in_container(test_command, opts)
end

-- Run all tests in current file
function M.run_file_tests(opts)
  local container_id, config = get_container_info()
  if not container_id then
    vim.api.nvim_err_writeln('No active devcontainer')
    return
  end

  local ft = vim.bo.filetype
  local test_config = M.wrapper_config[ft]

  if not test_config then
    vim.api.nvim_err_writeln('No test configuration for filetype: ' .. ft)
    return
  end

  local relative_file = vim.fn.fnamemodify(vim.fn.expand('%:p'), ':.')
  local dir_path = vim.fn.fnamemodify(relative_file, ':h')
  local test_command = string.format(test_config.test_file, dir_path)

  M.run_test_in_container(test_command, opts)
end

-- Run entire test suite
function M.run_suite_tests(opts)
  local container_id, config = get_container_info()
  if not container_id then
    vim.api.nvim_err_writeln('No active devcontainer')
    return
  end

  local ft = vim.bo.filetype
  local test_config = M.wrapper_config[ft]

  if not test_config then
    -- Try to detect from project
    if vim.fn.filereadable('go.mod') == 1 then
      test_config = M.wrapper_config.go
    elseif vim.fn.filereadable('package.json') == 1 then
      test_config = M.wrapper_config.javascript
    elseif vim.fn.filereadable('Cargo.toml') == 1 then
      test_config = M.wrapper_config.rust
    elseif vim.fn.filereadable('setup.py') == 1 or vim.fn.filereadable('pyproject.toml') == 1 then
      test_config = M.wrapper_config.python
    else
      vim.api.nvim_err_writeln('Could not detect project type for test suite')
      return
    end
  end

  M.run_test_in_container(test_config.test_suite, opts)
end

return M
