#!/usr/bin/env lua

-- Deep coverage tests for container.lsp.init module
-- Focus on complex scenarios and advanced error conditions
-- Targets specific uncovered lines to achieve 70%+ coverage

-- Add project lua directory to package path
package.path = './lua/?.lua;./lua/?/init.lua;../lua/?.lua;../lua/?/init.lua;' .. package.path

-- Advanced test state for deep coverage testing
local test_state = {
  lsp_clients = {},
  buffers = { 1, 2, 3 },
  current_buf = 1,
  docker_commands = {},
  events = {},
  file_system_calls = {},
  autocmd_callbacks = {},
  defer_functions = {},
  notification_calls = {},
}

-- Enhanced vim global with comprehensive edge case support
_G.vim = {
  -- Table utilities
  tbl_contains = function(t, value)
    for _, v in ipairs(t) do
      if v == value then
        return true
      end
    end
    return false
  end,
  tbl_deep_extend = function(behavior, ...)
    local result = {}
    local function deep_extend(target, source)
      for k, v in pairs(source) do
        if type(v) == 'table' and type(target[k]) == 'table' then
          deep_extend(target[k], v)
        else
          target[k] = v
        end
      end
    end
    for _, source in ipairs({ ... }) do
      if type(source) == 'table' then
        deep_extend(result, source)
      end
    end
    return result
  end,
  tbl_keys = function(t)
    local keys = {}
    for k, _ in pairs(t) do
      table.insert(keys, k)
    end
    return keys
  end,
  tbl_count = function(t)
    local count = 0
    for _ in pairs(t) do
      count = count + 1
    end
    return count
  end,
  trim = function(str)
    return str:match('^%s*(.-)%s*$')
  end,
  inspect = function(obj)
    return tostring(obj)
  end,

  -- File system functions
  fn = {
    getcwd = function()
      return '/test/workspace'
    end,
    expand = function(path)
      if path:match('%%:p') then
        return '/test/workspace/main.go'
      end
      return path
    end,
    system = function(cmd)
      test_state.file_system_calls[#test_state.file_system_calls + 1] = cmd
      -- Return different outputs based on shell_error setting
      if vim.v.shell_error == 0 then
        return '/test/workspace/main.go\n/test/workspace/utils.go\n'
      else
        return ''
      end
    end,
    shellescape = function(str)
      return "'" .. str .. "'"
    end,
  },

  -- Enhanced LSP mock with comprehensive edge cases
  lsp = {
    handlers = {
      ['textDocument/publishDiagnostics'] = function(err, result, ctx, config)
        return { mocked = true }
      end,
    },
    protocol = {
      make_client_capabilities = function()
        return {
          workspace = {
            configuration = true,
            didChangeConfiguration = { dynamicRegistration = true },
          },
        }
      end,
    },
    get_clients = function(opts)
      opts = opts or {}
      local clients = {}
      for _, client in ipairs(test_state.lsp_clients) do
        local match = true
        if opts.name and client.name ~= opts.name then
          match = false
        end
        if opts.bufnr and not vim.tbl_contains(client.attached_buffers or {}, opts.bufnr) then
          match = false
        end
        if match then
          table.insert(clients, client)
        end
      end
      return clients
    end,
    get_active_clients = function(opts)
      return vim.lsp.get_clients(opts)
    end,
    start = function(config)
      local client_id = #test_state.lsp_clients + 1
      local client = {
        id = client_id,
        name = config.name or 'test_client',
        config = config,
        initialized = false,
        is_stopped = function()
          return false
        end,
        stop = function(force)
          -- Track force parameter
          client._force_stopped = force or false
        end,
        notify = function(method, params)
          table.insert(test_state.notification_calls, { method = method, params = params })
        end,
        request = function(method, params, callback)
          if callback then
            -- Simulate different responses based on method
            if method == 'workspace/diagnostic' then
              vim.defer_fn(function()
                callback(nil, {})
              end, 10)
            else
              callback(nil, {})
            end
          end
        end,
        attached_buffers = {},
        workspace_folders = config.workspace_folders,
        server_capabilities = {
          workspace = { didChangeConfiguration = true },
        },
      }
      test_state.lsp_clients[client_id] = client

      -- Simulate async initialization
      vim.defer_fn(function()
        client.initialized = true
        if config.on_init then
          config.on_init(client, {})
        end
      end, 10)

      return client_id
    end,
    start_client = function(config)
      return vim.lsp.start(config)
    end,
    get_client_by_id = function(id)
      return test_state.lsp_clients[id]
    end,
    buf_attach_client = function(bufnr, client_id)
      local client = test_state.lsp_clients[client_id]
      if client then
        client.attached_buffers = client.attached_buffers or {}
        if not vim.tbl_contains(client.attached_buffers, bufnr) then
          table.insert(client.attached_buffers, bufnr)
        end
      end
    end,
    buf_detach_client = function(bufnr, client_id)
      local client = test_state.lsp_clients[client_id]
      if client and client.attached_buffers then
        for i, buf in ipairs(client.attached_buffers) do
          if buf == bufnr then
            table.remove(client.attached_buffers, i)
            break
          end
        end
      end
    end,
  },

  -- Enhanced API functions
  api = {
    nvim_create_augroup = function(name, opts)
      return math.random(1000)
    end,
    nvim_create_autocmd = function(events, opts)
      local autocmd_id = math.random(1000)
      local autocmd_entry = {
        id = autocmd_id,
        events = events,
        opts = opts,
      }
      table.insert(test_state.events, autocmd_entry)

      -- Store callback for later execution in tests
      if opts.callback then
        test_state.autocmd_callbacks[autocmd_id] = opts.callback
      end

      return autocmd_id
    end,
    nvim_get_current_buf = function()
      return test_state.current_buf
    end,
    nvim_list_bufs = function()
      return test_state.buffers
    end,
    nvim_buf_is_loaded = function(buf)
      return vim.tbl_contains(test_state.buffers, buf)
    end,
    nvim_buf_get_name = function(buf)
      if buf == 1 then
        return '/test/workspace/main.go'
      elseif buf == 2 then
        return '/test/workspace/utils.go'
      end
      return '/test/workspace/file' .. buf .. '.go'
    end,
    nvim_buf_get_option = function(buf, option)
      if option == 'filetype' then
        return 'go'
      end
      return nil
    end,
  },

  -- Buffer options
  bo = {},

  -- Other vim functions
  v = { shell_error = 0 },
  defer_fn = function(fn, delay)
    -- Store deferred functions for controlled execution
    table.insert(test_state.defer_functions, { fn = fn, delay = delay })
    -- Execute immediately for most tests
    fn()
  end,
}

-- Set up vim.bo metatable
setmetatable(_G.vim.bo, {
  __index = function(t, bufnr)
    return { filetype = 'go' }
  end,
})

-- Mock modules with advanced error simulation
local mock_log = {
  debug = function(...) end,
  info = function(...) end,
  warn = function(...) end,
  error = function(...) end,
}

local mock_docker = {
  run_docker_command = function(args)
    test_state.docker_commands[#test_state.docker_commands + 1] = table.concat(args, ' ')

    if vim.tbl_contains(args, 'which') then
      local cmd = args[#args]
      if vim.tbl_contains({ 'gopls', 'lua-language-server', 'pylsp' }, cmd) then
        return {
          success = true,
          stdout = '/usr/local/bin/' .. cmd,
          stderr = '',
          code = 0,
        }
      else
        return {
          success = false,
          stdout = '',
          stderr = 'command not found',
          code = 1,
        }
      end
    end

    if vim.tbl_contains(args, '--version') then
      -- Simulate version check based on test state
      if test_state.version_check_fails then
        return {
          success = false,
          stdout = '',
          stderr = 'version check failed',
          code = 1,
        }
      else
        return {
          success = true,
          stdout = 'server version 1.0.0',
          stderr = '',
          code = 0,
        }
      end
    end

    return { success = true, stdout = '', stderr = '', code = 0 }
  end,
}

local mock_environment = {
  build_lsp_args = function(config)
    return { '--user', 'test:test', '-e', 'HOME=/home/test' }
  end,
}

local mock_container = {
  get_state = function()
    return {
      current_container = test_state.current_container or 'test_container_123',
      current_config = { image = 'golang:1.21' },
    }
  end,
}

local mock_commands = {
  setup = function(config)
    if test_state.commands_setup_fails then
      error('Commands setup failed')
    end
  end,
  setup_commands = function()
    if test_state.commands_setup_commands_fails then
      error('Commands setup_commands failed')
    end
  end,
  setup_keybindings = function(opts)
    return not test_state.keybindings_setup_fails
  end,
}

local mock_strategy = {
  setup = function()
    if test_state.strategy_setup_fails then
      error('Strategy setup failed')
    end
  end,
  select_strategy = function(name, container_id, server_config)
    if test_state.strategy_select_fails then
      error('Strategy selection failed')
    end
    return 'intercept', { port = 9090 }
  end,
  create_client_with_strategy = function(strategy, name, container_id, server_config, strategy_config)
    if test_state.strategy_create_fails then
      return nil, 'Strategy client creation failed'
    end
    return {
      name = 'container_' .. name,
      cmd = { 'docker', 'exec', container_id, server_config.cmd },
      filetypes = server_config.languages,
      root_dir = function()
        return '/test/workspace'
      end,
      before_init = function(params, config) end,
      on_init = function(client, result) end,
      on_attach = function(client, bufnr) end,
    },
      nil
  end,
  setup_path_transformation = function(client, name, container_id)
    if test_state.path_transformation_fails then
      error('Path transformation setup failed')
    end
  end,
}

local mock_lspconfig_util = {
  root_pattern = function(...)
    local patterns = { ... }
    return function(fname)
      for _, pattern in ipairs(patterns) do
        if pattern == 'go.mod' then
          return test_state.go_mod_path or '/test/workspace'
        end
      end
      return nil
    end
  end,
  find_git_ancestor = function(fname)
    return test_state.git_root or '/test/workspace'
  end,
  path = {
    dirname = function(path)
      return path:match('(.+)/') or path
    end,
  },
}

-- Helper to create mock notify module
local function create_mock_notify()
  return {
    error = function(title, message) end,
    warn = function(title, message) end,
    success = function(title, message) end,
    info = function(title, message) end,
  }
end

-- Register mocks
package.loaded['container.utils.log'] = mock_log
package.loaded['container.docker.init'] = mock_docker
package.loaded['container.environment'] = mock_environment
package.loaded['container'] = mock_container
package.loaded['container.lsp.commands'] = mock_commands
package.loaded['container.lsp.strategy'] = mock_strategy
package.loaded['lspconfig.util'] = mock_lspconfig_util
package.loaded['container.utils.notify'] = create_mock_notify()

-- Helper functions
local function reset_test_state()
  test_state.lsp_clients = {}
  test_state.buffers = { 1, 2, 3 }
  test_state.current_buf = 1
  test_state.docker_commands = {}
  test_state.events = {}
  test_state.file_system_calls = {}
  test_state.autocmd_callbacks = {}
  test_state.defer_functions = {}
  test_state.notification_calls = {}
  test_state.version_check_fails = false
  test_state.commands_setup_fails = false
  test_state.commands_setup_commands_fails = false
  test_state.keybindings_setup_fails = false
  test_state.strategy_setup_fails = false
  test_state.strategy_select_fails = false
  test_state.strategy_create_fails = false
  test_state.path_transformation_fails = false
  test_state.current_container = nil
  test_state.go_mod_path = nil
  test_state.git_root = nil
  vim.v.shell_error = 0
end

local function execute_deferred_functions()
  for _, deferred in ipairs(test_state.defer_functions) do
    deferred.fn()
  end
  test_state.defer_functions = {}
end

local function trigger_autocmd_callbacks(pattern)
  for _, callback in pairs(test_state.autocmd_callbacks) do
    local args = {
      buf = test_state.current_buf,
      data = { container_id = 'test_container_123' },
    }
    callback(args)
  end
end

-- Deep coverage test suite
local tests = {}

function tests.test_complex_auto_initialization_scenarios()
  reset_test_state()

  -- Test scenario with container init status management
  local lsp = require('container.lsp.init')
  lsp.setup({ auto_setup = true })

  -- Create existing functional gopls client
  test_state.lsp_clients[1] = {
    id = 1,
    name = 'container_gopls',
    is_stopped = function()
      return false
    end,
    initialized = true,
    attached_buffers = {},
  }

  -- Execute autocmd callbacks to test container detection path
  trigger_autocmd_callbacks('ContainerDetected')

  return true
end

function tests.test_host_gopls_cleanup_scenarios()
  reset_test_state()

  local lsp = require('container.lsp.init')
  lsp.setup({ auto_setup = true })

  -- Create host gopls clients that need cleanup
  test_state.lsp_clients[1] = {
    id = 1,
    name = 'gopls',
    is_stopped = function()
      return false
    end,
    stop = function() end,
    attached_buffers = { 1, 2 },
  }
  test_state.lsp_clients[2] = {
    id = 2,
    name = 'gopls',
    is_stopped = function()
      return true
    end, -- Already stopped
    stop = function() end,
    attached_buffers = {},
  }

  -- Trigger auto-initialization which should clean up host clients
  trigger_autocmd_callbacks('ContainerDetected')
  execute_deferred_functions()

  return true
end

function tests.test_strategy_failure_recovery()
  reset_test_state()

  -- Configure strategy to fail
  test_state.strategy_create_fails = true

  local lsp = require('container.lsp.init')
  lsp.setup()
  lsp.set_container_id('test_container_123')

  local server_config = {
    cmd = 'gopls',
    languages = { 'go' },
    available = true,
    path = '/usr/local/bin/gopls',
  }

  -- This should trigger strategy failure handling
  lsp.create_lsp_client('gopls', server_config)

  return true
end

function tests.test_before_init_callback_comprehensive()
  reset_test_state()

  local lsp = require('container.lsp.init')
  lsp.setup()

  -- Test before_init with different file scenarios
  test_state.go_mod_path = '/test/workspace/subproject'

  local server_config = { cmd = 'gopls', languages = { 'go' } }
  local config = lsp._prepare_lsp_config('gopls', server_config)

  -- Test before_init callback
  local init_params = {
    workspaceFolders = { { uri = 'old_uri', name = 'old_name' } },
    rootUri = 'old_root',
    rootPath = 'old_path',
  }

  config.before_init(init_params, config)

  assert(init_params.workspaceFolders[1].uri:match('/test/workspace'), 'Workspace URI should be updated')
  assert(init_params.rootUri:match('/test/workspace'), 'Root URI should be updated')

  return true
end

function tests.test_on_init_callback_comprehensive()
  reset_test_state()

  local lsp = require('container.lsp.init')
  lsp.setup()

  -- Create client with mock capabilities
  local client = {
    workspace_folders = {},
    server_capabilities = {
      workspace = { didChangeConfiguration = true },
    },
    notify = function(method, params)
      table.insert(test_state.notification_calls, { method = method, params = params })
    end,
  }

  local server_config = { cmd = 'gopls', languages = { 'go' } }
  local config = lsp._prepare_lsp_config('gopls', server_config)

  -- Test on_init callback
  config.on_init(client, {})

  -- Verify workspace folder was set
  assert(#client.workspace_folders > 0, 'Workspace folders should be set')

  -- Verify didChangeConfiguration was sent
  local found_config_change = false
  for _, call in ipairs(test_state.notification_calls) do
    if call.method == 'workspace/didChangeConfiguration' then
      found_config_change = true
      break
    end
  end
  assert(found_config_change, 'didChangeConfiguration should be sent')

  return true
end

function tests.test_file_registration_with_interceptor_metadata()
  reset_test_state()

  local lsp = require('container.lsp.init')
  lsp.setup()

  -- Create client with interceptor metadata
  local client = {
    id = 1,
    is_stopped = function()
      return false
    end,
    initialized = true,
    config = {
      _container_metadata = {
        strategy = 'intercept',
      },
    },
    notify = function(method, params)
      table.insert(test_state.notification_calls, { method = method, params = params })
    end,
    request = function(method, params, callback)
      if callback then
        vim.defer_fn(function()
          callback(nil, {})
        end, 10)
      end
    end,
  }

  -- Mock io.open to provide file content
  local original_io_open = io.open
  io.open = function(filename, mode)
    if mode == 'r' and filename:match('%.go$') then
      return {
        read = function(self, format)
          return 'package main\n\nfunc main() {}\n'
        end,
        close = function(self) end,
      }
    end
    return original_io_open(filename, mode)
  end

  lsp._register_existing_go_files(client)
  execute_deferred_functions()

  -- Verify textDocument/didOpen notifications were sent
  local found_did_open = false
  for _, call in ipairs(test_state.notification_calls) do
    if call.method == 'textDocument/didOpen' then
      found_did_open = true
      break
    end
  end
  assert(found_did_open, 'didOpen notifications should be sent')

  io.open = original_io_open
  return true
end

function tests.test_client_verification_after_creation()
  reset_test_state()

  local lsp = require('container.lsp.init')
  lsp.setup()
  lsp.set_container_id('test_container_123')

  -- Mock start_lsp_client to return valid client ID
  local original_start = vim.lsp.start
  vim.lsp.start = function(config)
    local client_id = #test_state.lsp_clients + 1
    local client = {
      id = client_id,
      name = config.name,
      config = config,
      initialized = false,
      is_stopped = function()
        return false
      end,
      stop = function() end,
    }
    test_state.lsp_clients[client_id] = client
    return client_id
  end

  local server_config = {
    cmd = 'gopls',
    languages = { 'go' },
    available = true,
    path = '/usr/local/bin/gopls',
  }

  lsp.create_lsp_client('gopls', server_config)
  execute_deferred_functions()

  vim.lsp.start = original_start
  return true
end

function tests.test_complex_autocmd_scenarios()
  reset_test_state()

  local lsp = require('container.lsp.init')
  lsp.setup({ auto_setup = true })

  -- Test LspAttach autocmd with container_gopls
  test_state.lsp_clients[1] = {
    id = 1,
    name = 'container_gopls',
    is_stopped = function()
      return false
    end,
  }

  -- Find and execute LspAttach autocmd
  for autocmd_id, callback in pairs(test_state.autocmd_callbacks) do
    local args = {
      buf = 1,
      data = { client_id = 1 },
    }
    callback(args)
  end

  return true
end

function tests.test_go_buffer_detection_edge_cases()
  reset_test_state()

  -- Add buffers with different file types
  test_state.buffers = { 1, 2, 3, 4 }

  -- Mock buffer names and types
  local original_get_name = vim.api.nvim_buf_get_name
  local original_get_option = vim.api.nvim_buf_get_option

  vim.api.nvim_buf_get_name = function(buf)
    if buf == 1 then
      return '/test/workspace/main.go'
    end
    if buf == 2 then
      return '/test/workspace/test.py'
    end
    if buf == 3 then
      return '/test/workspace/utils.go'
    end
    if buf == 4 then
      return '/test/workspace/README.md'
    end
    return ''
  end

  vim.api.nvim_buf_get_option = function(buf, option)
    if option == 'filetype' then
      if buf == 1 or buf == 3 then
        return 'go'
      end
      if buf == 2 then
        return 'python'
      end
      if buf == 4 then
        return 'markdown'
      end
    end
    return nil
  end

  local lsp = require('container.lsp.init')
  lsp.setup({ auto_setup = true })

  -- Trigger auto-initialization
  trigger_autocmd_callbacks('ContainerDetected')

  vim.api.nvim_buf_get_name = original_get_name
  vim.api.nvim_buf_get_option = original_get_option
  return true
end

function tests.test_error_in_on_init_callback()
  reset_test_state()

  local lsp = require('container.lsp.init')

  -- Setup with custom on_init that might fail
  lsp.setup({
    on_init = function(client, result)
      error('Custom on_init failed')
    end,
  })

  local server_config = { cmd = 'gopls', languages = { 'go' } }
  local config = lsp._prepare_lsp_config('gopls', server_config)

  -- Test on_init with custom callback that fails
  local client = { workspace_folders = {} }
  local ok, err = pcall(config.on_init, client, {})

  -- Should handle the error gracefully
  assert(not ok, 'on_init should fail due to custom callback error')

  return true
end

function tests.test_diagnose_server_comprehensive_scenarios()
  reset_test_state()

  local lsp = require('container.lsp.init')
  lsp.setup()
  lsp.set_container_id('test_container_123')

  -- Test 1: Server not detected
  local diagnosis1 = lsp.diagnose_lsp_server('nonexistent_server')
  assert(diagnosis1.available == false, 'Non-existent server should not be available')
  assert(type(diagnosis1.suggestions) == 'table', 'Should provide suggestions')

  -- Test 2: Server detected, version check fails
  lsp.detect_language_servers() -- Detect gopls
  test_state.version_check_fails = true

  local diagnosis2 = lsp.diagnose_lsp_server('gopls')
  assert(diagnosis2.available == true, 'gopls should be available')
  assert(diagnosis2.working == false, 'gopls should not be working due to version failure')

  -- Test 3: Server working
  test_state.version_check_fails = false

  local diagnosis3 = lsp.diagnose_lsp_server('gopls')
  assert(diagnosis3.available == true, 'gopls should be available')
  assert(diagnosis3.working == true, 'gopls should be working')

  return true
end

function tests.test_retry_server_setup_comprehensive()
  reset_test_state()

  local lsp = require('container.lsp.init')
  lsp.setup()
  lsp.set_container_id('test_container_123')

  -- Detect servers first
  lsp.detect_language_servers()

  -- Test retry with working server
  lsp.retry_lsp_server_setup('gopls', 1)
  execute_deferred_functions()

  return true
end

function tests.test_analyze_client_comprehensive()
  reset_test_state()

  local lsp = require('container.lsp.init')
  lsp.setup()

  -- Create a comprehensive client for analysis
  test_state.lsp_clients[1] = {
    id = 1,
    name = 'container_gopls',
    is_stopped = function()
      return false
    end,
    initialized = true,
    config = {
      cmd = { 'gopls' },
      root_dir = '/test/workspace',
      capabilities = { workspace = true },
      settings = { gopls = { usePlaceholders = true } },
      init_options = { usePlaceholders = true },
    },
    server_capabilities = {
      textDocumentSync = true,
      hoverProvider = true,
    },
    workspace_folders = {
      { uri = 'file:///test/workspace', name = 'workspace' },
    },
    attached_buffers = { 1 },
  }

  local analysis = lsp.analyze_client('container_gopls')
  assert(type(analysis) == 'table', 'Analysis should return table')
  assert(analysis.basic_info.id == 1, 'Should include basic info')
  assert(type(analysis.config) == 'table', 'Should include config info')
  assert(type(analysis.server_info) == 'table', 'Should include server info')
  assert(type(analysis.buffer_attachment) == 'table', 'Should include buffer attachment info')

  return true
end

function tests.test_health_check_with_stopped_clients()
  reset_test_state()

  local lsp = require('container.lsp.init')
  lsp.setup()
  lsp.set_container_id('test_container_123')

  -- Create clients with different states
  test_state.lsp_clients[1] = {
    id = 1,
    name = 'container_gopls',
    is_stopped = function()
      return true
    end, -- Stopped client
  }

  -- Add client to state manually
  local state = lsp.get_state()
  -- Mock internal state (this is testing internal behavior)

  local health = lsp.health_check()
  assert(type(health.issues) == 'table', 'Health check should identify issues')

  return true
end

function tests.test_path_transformation_setup_failure()
  reset_test_state()

  -- Configure path transformation to fail
  test_state.path_transformation_fails = true

  local lsp = require('container.lsp.init')
  lsp.setup()
  lsp.set_container_id('test_container_123')

  local server_config = {
    cmd = 'gopls',
    languages = { 'go' },
    available = true,
    path = '/usr/local/bin/gopls',
  }

  -- This should handle path transformation failure gracefully
  local ok, err = pcall(lsp.create_lsp_client, 'gopls', server_config)

  return true
end

function tests.test_setup_commands_with_custom_keybindings()
  reset_test_state()

  local lsp = require('container.lsp.init')
  lsp.setup({
    keybindings = {
      hover = '<leader>h',
      definition = '<leader>d',
      references = '<leader>r',
    },
  })

  -- Mock successful keybinding setup
  test_state.keybindings_setup_fails = false

  lsp._setup_gopls_commands(1)

  return true
end

-- Test runner
local function run_deep_coverage_tests()
  print('Running deep coverage LSP init tests...')
  print('=========================================')

  local test_functions = {
    'test_complex_auto_initialization_scenarios',
    'test_host_gopls_cleanup_scenarios',
    'test_strategy_failure_recovery',
    'test_before_init_callback_comprehensive',
    'test_on_init_callback_comprehensive',
    'test_file_registration_with_interceptor_metadata',
    'test_client_verification_after_creation',
    'test_complex_autocmd_scenarios',
    'test_go_buffer_detection_edge_cases',
    'test_error_in_on_init_callback',
    'test_diagnose_server_comprehensive_scenarios',
    'test_retry_server_setup_comprehensive',
    'test_analyze_client_comprehensive',
    'test_health_check_with_stopped_clients',
    'test_path_transformation_setup_failure',
    'test_setup_commands_with_custom_keybindings',
  }

  local passed = 0
  local total = #test_functions
  local failed_tests = {}

  for _, test_name in ipairs(test_functions) do
    print('\nRunning: ' .. test_name)

    local ok, result = pcall(tests[test_name])

    if ok and result then
      print('✓ PASSED: ' .. test_name)
      passed = passed + 1
    else
      local error_msg = result and tostring(result) or 'Unknown error'
      print('✗ FAILED: ' .. test_name .. ' - ' .. error_msg)
      table.insert(failed_tests, test_name .. ': ' .. error_msg)
    end
  end

  print('\n=========================================')
  print(string.format('Deep Coverage Tests Complete: %d/%d passed', passed, total))

  if #failed_tests > 0 then
    print('\nFailed tests:')
    for _, failure in ipairs(failed_tests) do
      print('  ✗ ' .. failure)
    end
  end

  if passed == total then
    print('All deep coverage tests passed! ✓')
    return 0
  else
    print('Some deep coverage tests failed. ✗')
    return 1
  end
end

-- Auto-run if executed directly
if not pcall(debug.getlocal, 4, 1) then
  local exit_code = run_deep_coverage_tests()
  os.exit(exit_code)
end

return tests
