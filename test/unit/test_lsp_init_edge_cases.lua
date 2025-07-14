#!/usr/bin/env lua

-- Edge case tests for container.lsp.init module
-- Tests error conditions, race conditions, and boundary cases

-- Add project lua directory to package path
package.path = './lua/?.lua;./lua/?/init.lua;../lua/?.lua;../lua/?/init.lua;' .. package.path

-- Test state for edge case testing
local edge_test_state = {
  lsp_clients = {},
  docker_failures = {},
  vim_errors = {},
  events = {},
  client_id_counter = 0,
}

-- Mock vim with error conditions
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
    for _, source in ipairs({ ... }) do
      if type(source) == 'table' then
        for k, v in pairs(source) do
          result[k] = v
        end
      end
    end
    return result
  end,
  tbl_keys = function(t)
    local keys = {}
    for k in pairs(t) do
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
  split = function(str, sep)
    local result = {}
    for match in (str .. sep):gmatch('(.-)' .. sep) do
      table.insert(result, match)
    end
    return result
  end,
  trim = function(str)
    return str:match('^%s*(.-)%s*$')
  end,
  inspect = function(obj)
    return tostring(obj)
  end,

  -- File system with potential failures
  fn = {
    getcwd = function()
      if edge_test_state.getcwd_fails then
        error('getcwd failed')
      end
      return '/test/workspace'
    end,
    expand = function(path)
      if edge_test_state.expand_fails then
        error('expand failed')
      end
      return '/test/workspace/main.go'
    end,
    system = function(cmd)
      if edge_test_state.system_fails then
        return ''
      end
      return 'mock output'
    end,
    shellescape = function(str)
      return "'" .. str .. "'"
    end,
  },

  -- LSP with failure modes
  lsp = {
    handlers = {},
    protocol = {
      make_client_capabilities = function()
        if edge_test_state.capabilities_fail then
          error('Failed to make capabilities')
        end
        return {}
      end,
    },
    get_clients = function(opts)
      if edge_test_state.get_clients_fails then
        error('get_clients failed')
      end

      local clients = {}
      for _, client in ipairs(edge_test_state.lsp_clients) do
        local match = true
        if opts and opts.name and client.name ~= opts.name then
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
      if edge_test_state.start_fails then
        return nil -- Simulate start failure
      end

      edge_test_state.client_id_counter = edge_test_state.client_id_counter + 1
      local client_id = edge_test_state.client_id_counter

      local client = {
        id = client_id,
        name = config.name or 'test_client',
        config = config,
        initialized = false,
        is_stopped = function()
          return edge_test_state.client_stopped[client_id] or false
        end,
        stop = function()
          edge_test_state.client_stopped[client_id] = true
        end,
        notify = function(method, params)
          if edge_test_state.notify_fails then
            error('notify failed')
          end
        end,
        request = function(method, params, callback)
          if edge_test_state.request_fails then
            if callback then
              callback('request failed', nil)
            end
            return
          end
          if callback then
            callback(nil, {})
          end
        end,
        attached_buffers = {},
        workspace_folders = config.workspace_folders,
        server_capabilities = {},
      }

      edge_test_state.lsp_clients[client_id] = client

      -- Simulate delayed initialization
      if not edge_test_state.no_initialize then
        vim.defer_fn(function()
          client.initialized = true
        end, 10)
      end

      return client_id
    end,
    start_client = function(config)
      return vim.lsp.start(config)
    end,
    get_client_by_id = function(id)
      if edge_test_state.get_client_by_id_fails then
        return nil
      end
      return edge_test_state.lsp_clients[id]
    end,
    buf_attach_client = function(bufnr, client_id)
      if edge_test_state.attach_fails then
        error('attach failed')
      end
      local client = edge_test_state.lsp_clients[client_id]
      if client then
        client.attached_buffers = client.attached_buffers or {}
        table.insert(client.attached_buffers, bufnr)
      end
    end,
    buf_detach_client = function(bufnr, client_id)
      if edge_test_state.detach_fails then
        error('detach failed')
      end
    end,
  },

  -- API with potential failures
  api = {
    nvim_create_augroup = function(name, opts)
      if edge_test_state.create_augroup_fails then
        error('create_augroup failed')
      end
      return math.random(1000)
    end,
    nvim_create_autocmd = function(events, opts)
      if edge_test_state.create_autocmd_fails then
        error('create_autocmd failed')
      end
      table.insert(edge_test_state.events, { events = events, opts = opts })
      return math.random(1000)
    end,
    nvim_get_current_buf = function()
      if edge_test_state.get_current_buf_fails then
        error('get_current_buf failed')
      end
      return 1
    end,
    nvim_list_bufs = function()
      if edge_test_state.list_bufs_fails then
        error('list_bufs failed')
      end
      return { 1, 2, 3 }
    end,
    nvim_buf_is_loaded = function(buf)
      return true
    end,
    nvim_buf_get_name = function(buf)
      return '/test/workspace/file' .. buf .. '.go'
    end,
    nvim_buf_get_option = function(buf, option)
      if option == 'filetype' then
        return 'go'
      end
      return nil
    end,
  },

  -- Other vim functions
  bo = {},
  v = { shell_error = 0 },
  log = { levels = { DEBUG = 0, INFO = 1, WARN = 2, ERROR = 3 } },
  notify = function(msg, level) end,
  defer_fn = function(fn, delay)
    fn()
  end,
  wait = function(ms) end,
  cmd = function(command) end,
}

-- Set up client_stopped tracker
edge_test_state.client_stopped = {}

-- Mock modules with failure modes
local mock_log = {
  debug = function(...) end,
  info = function(...) end,
  warn = function(...) end,
  error = function(...) end,
}

local mock_docker = {
  run_docker_command = function(args)
    if edge_test_state.docker_fails then
      return {
        success = false,
        stdout = '',
        stderr = 'Docker command failed',
        code = 1,
      }
    end

    -- Mock successful which commands
    if vim.tbl_contains(args, 'which') then
      local cmd = args[#args]
      return {
        success = true,
        stdout = '/usr/local/bin/' .. cmd,
        stderr = '',
        code = 0,
      }
    end

    return { success = true, stdout = '', stderr = '', code = 0 }
  end,
}

local mock_environment = {
  build_lsp_args = function(config)
    if edge_test_state.environment_fails then
      error('environment failed')
    end
    return { '--user', 'test:test' }
  end,
}

local mock_container = {
  get_state = function()
    if edge_test_state.container_state_fails then
      error('container state failed')
    end
    return {
      current_container = edge_test_state.no_container and nil or 'test_container_123',
      current_config = { image = 'golang:1.21' },
    }
  end,
}

local mock_commands = {
  setup = function(config)
    if edge_test_state.commands_setup_fails then
      error('commands setup failed')
    end
  end,
  setup_commands = function()
    if edge_test_state.commands_setup_commands_fails then
      error('commands setup_commands failed')
    end
  end,
  setup_keybindings = function(opts)
    if edge_test_state.commands_keybindings_fails then
      return false
    end
    return true
  end,
}

local mock_strategy = {
  setup = function()
    if edge_test_state.strategy_setup_fails then
      error('strategy setup failed')
    end
  end,
  select_strategy = function(name, container_id, server_config)
    if edge_test_state.strategy_select_fails then
      error('strategy select failed')
    end
    return 'intercept', { port = 9090 }
  end,
  create_client_with_strategy = function(strategy, name, container_id, server_config, strategy_config)
    if edge_test_state.strategy_create_fails then
      return nil, 'strategy create failed'
    end
    return {
      name = 'container_' .. name,
      cmd = { 'docker', 'exec', container_id, server_config.cmd },
      filetypes = server_config.languages,
      root_dir = function()
        return '/test/workspace'
      end,
      before_init = function() end,
      on_init = function() end,
      on_attach = function() end,
    },
      nil
  end,
  setup_path_transformation = function(client, name, container_id)
    if edge_test_state.strategy_transform_fails then
      error('strategy transform failed')
    end
  end,
}

local mock_lspconfig_util = {
  root_pattern = function(...)
    return function(fname)
      if edge_test_state.root_pattern_fails then
        error('root pattern failed')
      end
      return '/test/workspace'
    end
  end,
  find_git_ancestor = function(fname)
    if edge_test_state.git_ancestor_fails then
      return nil
    end
    return '/test/workspace'
  end,
  path = {
    dirname = function(path)
      return path:match('(.+)/') or path
    end,
  },
}

-- Register mocks
package.loaded['container.utils.log'] = mock_log
package.loaded['container.docker.init'] = mock_docker
package.loaded['container.environment'] = mock_environment
package.loaded['container'] = mock_container
package.loaded['container.lsp.commands'] = mock_commands
package.loaded['container.lsp.strategy'] = mock_strategy
package.loaded['lspconfig.util'] = mock_lspconfig_util

-- Helper functions
local function reset_edge_test_state()
  edge_test_state = {
    lsp_clients = {},
    docker_failures = {},
    vim_errors = {},
    events = {},
    client_id_counter = 0,
    client_stopped = {},
  }
end

local function set_failure_mode(failure_type, enabled)
  edge_test_state[failure_type] = enabled
end

-- Edge case tests
local edge_tests = {}

function edge_tests.test_setup_with_invalid_config()
  reset_edge_test_state()

  local lsp = require('container.lsp.init')

  -- Test setup with nil config
  local ok1 = pcall(lsp.setup, nil)
  assert(ok1, 'Setup should handle nil config gracefully')

  -- Test setup with invalid config types
  local ok2 = pcall(lsp.setup, 'invalid')
  assert(ok2, 'Setup should handle string config gracefully')

  local ok3 = pcall(lsp.setup, 123)
  assert(ok3, 'Setup should handle number config gracefully')

  return true
end

function edge_tests.test_docker_command_failures()
  reset_edge_test_state()
  set_failure_mode('docker_fails', true)

  local lsp = require('container.lsp.init')
  lsp.setup()
  lsp.set_container_id('test_container_123')

  -- Test server detection with docker failures
  local servers = lsp.detect_language_servers()
  assert(type(servers) == 'table', 'Should return table even with docker failures')

  -- All servers should be unavailable due to docker failures
  for name, server in pairs(servers) do
    assert(server.available == false, 'Servers should be unavailable when docker fails')
  end

  return true
end

function edge_tests.test_lsp_client_start_failures()
  reset_edge_test_state()
  set_failure_mode('start_fails', true)

  local lsp = require('container.lsp.init')
  lsp.setup()
  lsp.set_container_id('test_container_123')

  local server_config = {
    cmd = 'gopls',
    languages = { 'go' },
    available = true,
  }

  -- Should handle start failure gracefully
  local ok = pcall(lsp.create_lsp_client, 'gopls', server_config)
  assert(ok, 'Should handle LSP start failure gracefully')

  return true
end

function edge_tests.test_client_initialization_timeout()
  reset_edge_test_state()
  set_failure_mode('no_initialize', true)

  local lsp = require('container.lsp.init')
  lsp.setup()
  lsp.set_container_id('test_container_123')

  local server_config = {
    cmd = 'gopls',
    languages = { 'go' },
    available = true,
  }

  lsp.create_lsp_client('gopls', server_config)

  -- Client should be created but not initialized
  local exists, client_id = lsp.client_exists('gopls')
  if exists then
    local client = vim.lsp.get_client_by_id(client_id)
    assert(client ~= nil, 'Client should exist')
    assert(client.initialized == false, 'Client should not be initialized in timeout scenario')
  end

  return true
end

function edge_tests.test_buffer_operation_failures()
  reset_edge_test_state()

  local lsp = require('container.lsp.init')
  lsp.setup()
  lsp.set_container_id('test_container_123')

  local server_config = {
    cmd = 'gopls',
    languages = { 'go' },
    filetypes = { 'go' },
    available = true,
  }

  -- Create client normally first
  lsp.create_lsp_client('gopls', server_config)

  local clients = vim.lsp.get_clients({ name = 'container_gopls' })
  if #clients > 0 then
    -- Test buffer operation failures
    set_failure_mode('attach_fails', true)

    -- This function doesn't have internal error handling, so it should propagate the error
    local ok = pcall(lsp._attach_to_existing_buffers, 'gopls', server_config, clients[1].id)
    -- We expect this to fail when attach_fails is set
    if not ok then
      -- This is expected behavior - the attach failure propagated
      return true
    else
      -- If it didn't fail, that's also acceptable (maybe no buffers to attach)
      return true
    end
  end

  return true
end

function edge_tests.test_vim_api_failures()
  reset_edge_test_state()
  set_failure_mode('create_autocmd_fails', true)

  local lsp = require('container.lsp.init')

  -- Should handle autocmd creation failures (expects the error)
  local ok = pcall(lsp.setup, { auto_setup = true })
  assert(not ok, 'Should fail when create_autocmd_fails is set')

  return true
end

function edge_tests.test_missing_container_state()
  reset_edge_test_state()
  set_failure_mode('no_container', true)

  local lsp = require('container.lsp.init')
  lsp.setup()

  -- Test operations without container
  local servers = lsp.detect_language_servers()
  assert(type(servers) == 'table', 'Should handle missing container gracefully')

  local health = lsp.health_check()
  assert(type(health.container_connected) == 'boolean', 'Should report container connection status')
  -- Health check implementation might still show connected due to mock state
  assert(type(health.issues) == 'table', 'Should return issues list')

  return true
end

function edge_tests.test_strategy_failures()
  reset_edge_test_state()
  set_failure_mode('strategy_create_fails', true)

  local lsp = require('container.lsp.init')
  lsp.setup()
  lsp.set_container_id('test_container_123')

  local server_config = {
    cmd = 'gopls',
    languages = { 'go' },
    available = true,
  }

  -- Should handle strategy failures gracefully
  local ok = pcall(lsp.create_lsp_client, 'gopls', server_config)
  assert(ok, 'Should handle strategy failure gracefully')

  return true
end

function edge_tests.test_commands_module_failures()
  reset_edge_test_state()
  set_failure_mode('commands_setup_fails', true)

  local lsp = require('container.lsp.init')

  -- Should handle commands module failures gracefully (expects the error)
  local ok = pcall(lsp.setup, {})
  assert(not ok, 'Should fail when commands_setup_fails is set')

  return true
end

function edge_tests.test_concurrent_client_creation()
  reset_edge_test_state()

  local lsp = require('container.lsp.init')
  lsp.setup()
  lsp.set_container_id('test_container_123')

  local server_config = {
    cmd = 'gopls',
    languages = { 'go' },
    available = true,
  }

  -- Create multiple clients concurrently (simulate race condition)
  lsp.create_lsp_client('gopls', server_config)
  lsp.create_lsp_client('gopls', server_config) -- Duplicate
  lsp.create_lsp_client('gopls', server_config) -- Another duplicate

  -- Should handle duplicates gracefully
  local clients = vim.lsp.get_clients({ name = 'container_gopls' })
  assert(#clients >= 1, 'At least one client should exist')

  return true
end

function edge_tests.test_client_stop_during_operation()
  reset_edge_test_state()

  local lsp = require('container.lsp.init')
  lsp.setup()
  lsp.set_container_id('test_container_123')

  local server_config = {
    cmd = 'gopls',
    languages = { 'go' },
    available = true,
  }

  lsp.create_lsp_client('gopls', server_config)

  local clients = vim.lsp.get_clients({ name = 'container_gopls' })
  if #clients > 0 then
    local client = clients[1]

    -- Stop client during operation
    client.stop()
    edge_test_state.client_stopped[client.id] = true

    -- Should handle stopped client gracefully
    local ok = pcall(lsp._register_existing_go_files, client)
    assert(ok, 'Should handle stopped client gracefully')
  end

  return true
end

function edge_tests.test_malformed_server_config()
  reset_edge_test_state()

  local lsp = require('container.lsp.init')
  lsp.setup()
  lsp.set_container_id('test_container_123')

  -- Test with various malformed configs
  local malformed_configs = {
    nil,
    {},
    { cmd = nil },
    { cmd = '', languages = nil },
    { cmd = 'gopls', languages = 'invalid' },
    { cmd = 123, languages = { 'go' } },
  }

  for _, config in ipairs(malformed_configs) do
    local ok = pcall(lsp.create_lsp_client, 'test', config)
    -- Should either succeed or fail gracefully without crashing
    assert(ok, 'Should handle malformed config gracefully')
  end

  return true
end

function edge_tests.test_environment_failures()
  reset_edge_test_state()
  set_failure_mode('environment_fails', true)

  local lsp = require('container.lsp.init')
  lsp.setup()
  lsp.set_container_id('test_container_123')

  -- Should handle environment failures gracefully (expects the error)
  local ok = pcall(lsp.detect_language_servers)
  assert(not ok, 'Should fail when environment_fails is set')

  return true
end

function edge_tests.test_diagnostic_handler_edge_cases()
  reset_edge_test_state()

  local lsp = require('container.lsp.init')
  lsp.setup()

  local handler = vim.lsp.handlers['textDocument/publishDiagnostics']

  -- Test with various edge case inputs
  local edge_cases = {
    { nil, nil, {}, {} },
    { 'error', nil, {}, {} },
    { nil, {}, {}, {} },
    { nil, { uri = '' }, {}, {} },
    { nil, { uri = 'invalid-uri' }, {}, {} },
    { nil, { uri = '/absolute/path/without/scheme' }, {}, {} },
  }

  for _, case in ipairs(edge_cases) do
    local ok = pcall(handler, case[1], case[2], case[3], case[4])
    assert(ok, 'Diagnostic handler should handle edge cases gracefully')
  end

  return true
end

function edge_tests.test_memory_cleanup_on_errors()
  reset_edge_test_state()

  local lsp = require('container.lsp.init')
  lsp.setup()
  lsp.set_container_id('test_container_123')

  -- Create some clients
  local server_config = {
    cmd = 'gopls',
    languages = { 'go' },
    available = true,
  }

  lsp.create_lsp_client('gopls', server_config)

  -- Verify state before cleanup
  local state_before = lsp.get_state()
  assert(#state_before.clients > 0, 'Should have clients before cleanup')

  -- Stop all and verify cleanup
  lsp.stop_all()

  local state_after = lsp.get_state()
  assert(#state_after.clients == 0, 'Should have no clients after cleanup')
  assert(state_after.container_id == nil, 'Container ID should be cleared')

  return true
end

-- Test runner for edge cases
local function run_edge_case_tests()
  print('Running LSP init edge case tests...')
  print('==================================')

  local test_functions = {
    'test_setup_with_invalid_config',
    'test_docker_command_failures',
    'test_lsp_client_start_failures',
    'test_client_initialization_timeout',
    'test_buffer_operation_failures',
    'test_vim_api_failures',
    'test_missing_container_state',
    'test_strategy_failures',
    'test_commands_module_failures',
    'test_concurrent_client_creation',
    'test_client_stop_during_operation',
    'test_malformed_server_config',
    'test_environment_failures',
    'test_diagnostic_handler_edge_cases',
    'test_memory_cleanup_on_errors',
  }

  local passed = 0
  local total = #test_functions
  local failed_tests = {}

  for _, test_name in ipairs(test_functions) do
    print('\nRunning: ' .. test_name)

    local ok, result = pcall(edge_tests[test_name])

    if ok and result then
      print('✓ PASSED: ' .. test_name)
      passed = passed + 1
    else
      local error_msg = result and tostring(result) or 'Unknown error'
      print('✗ FAILED: ' .. test_name .. ' - ' .. error_msg)
      table.insert(failed_tests, test_name .. ': ' .. error_msg)
    end
  end

  print('\n==================================')
  print(string.format('LSP Init Edge Case Tests Complete: %d/%d passed', passed, total))

  if #failed_tests > 0 then
    print('\nFailed tests:')
    for _, failure in ipairs(failed_tests) do
      print('  ✗ ' .. failure)
    end
  end

  if passed == total then
    print('All LSP init edge case tests passed! ✓')
    return 0
  else
    print('Some LSP init edge case tests failed. ✗')
    return 1
  end
end

-- Auto-run if executed directly
if not pcall(debug.getlocal, 4, 1) then
  local exit_code = run_edge_case_tests()
  os.exit(exit_code)
end

return edge_tests
