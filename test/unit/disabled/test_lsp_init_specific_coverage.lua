#!/usr/bin/env lua

-- Specific coverage tests for container.lsp.init module targeting uncovered lines
-- This test focuses on specific code paths that are not covered by existing tests

-- Add project lua directory to package path
package.path = './lua/?.lua;./lua/?/init.lua;../lua/?.lua;../lua/?/init.lua;' .. package.path

-- Minimal test state focused on specific coverage
local test_state = {
  lsp_clients = {},
  buffers = { 1, 2, 3 },
  events = {},
  container_init_status = {},
  path_mappings_initialized = false,
}

-- Minimal vim mock for specific tests
_G.vim = {
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
  trim = function(str)
    return str:match('^%s*(.-)%s*$')
  end,
  inspect = function(obj)
    return tostring(obj)
  end,

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
      if cmd:match('find.*%.go') then
        return '/test/workspace/main.go\n/test/workspace/utils.go\n'
      end
      return ''
    end,
    shellescape = function(str)
      return "'" .. str .. "'"
    end,
  },

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
        stop = function() end,
        notify = function(method, params) end,
        request = function(method, params, callback)
          if callback then
            callback(nil, {})
          end
        end,
        attached_buffers = {},
        workspace_folders = config.workspace_folders,
        server_capabilities = {
          workspace = { didChangeConfiguration = true },
        },
      }
      test_state.lsp_clients[client_id] = client
      vim.defer_fn(function()
        client.initialized = true
      end, 10)
      return client_id
    end,
    get_client_by_id = function(id)
      return test_state.lsp_clients[id]
    end,
    buf_attach_client = function(bufnr, client_id)
      local client = test_state.lsp_clients[client_id]
      if client then
        client.attached_buffers = client.attached_buffers or {}
        table.insert(client.attached_buffers, bufnr)
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

  api = {
    nvim_create_augroup = function(name, opts)
      return math.random(1000)
    end,
    nvim_create_autocmd = function(events, opts)
      table.insert(test_state.events, { events = events, opts = opts })
      return math.random(1000)
    end,
    nvim_get_current_buf = function()
      return 1
    end,
    nvim_list_bufs = function()
      return test_state.buffers
    end,
    nvim_buf_is_loaded = function(buf)
      return vim.tbl_contains(test_state.buffers, buf)
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

  bo = {},
  v = { shell_error = 0 },
  defer_fn = function(fn, delay)
    fn()
  end,
}

setmetatable(_G.vim.bo, {
  __index = function(t, bufnr)
    return { filetype = 'go' }
  end,
})

-- Mock modules
local mock_log = {
  debug = function(...) end,
  info = function(...) end,
  warn = function(...) end,
  error = function(...) end,
}

local mock_docker = {
  run_docker_command = function(args)
    if vim.tbl_contains(args, 'which') then
      local cmd = args[#args]
      if vim.tbl_contains({ 'gopls', 'lua-language-server' }, cmd) then
        return {
          success = true,
          stdout = '/usr/local/bin/' .. cmd,
          stderr = '',
          code = 0,
        }
      end
    end
    return { success = false, stdout = '', stderr = 'not found', code = 1 }
  end,
}

local mock_environment = {
  build_lsp_args = function(config)
    return { '--user', 'test:test' }
  end,
}

local mock_container = {
  get_state = function()
    return {
      current_container = 'test_container_123',
      current_config = { image = 'golang:1.21' },
    }
  end,
}

local mock_commands = {
  setup = function(config) end,
  setup_commands = function() end,
  setup_keybindings = function(opts)
    return true
  end,
}

local mock_strategy = {
  setup = function() end,
  select_strategy = function(name, container_id, server_config)
    return 'intercept', { port = 9090 }
  end,
  create_client_with_strategy = function(strategy, name, container_id, server_config, strategy_config)
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
  setup_path_transformation = function(client, name, container_id) end,
}

local mock_lspconfig_util = {
  root_pattern = function(...)
    return function(fname)
      return '/test/workspace'
    end
  end,
  find_git_ancestor = function(fname)
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

-- Helper function
local function reset_test_state()
  test_state.lsp_clients = {}
  test_state.buffers = { 1, 2, 3 }
  test_state.events = {}
  test_state.container_init_status = {}
  test_state.path_mappings_initialized = false
end

-- Specific coverage tests
local tests = {}

function tests.test_setup_with_nil_config()
  reset_test_state()

  local lsp = require('container.lsp.init')

  -- Test setup with nil config - should use defaults
  lsp.setup(nil)

  local state = lsp.get_state()
  assert(state.config ~= nil, 'Config should be set with defaults')
  assert(state.config.auto_setup == true, 'Default auto_setup should be true')

  return true
end

function tests.test_language_server_detection_empty_container()
  reset_test_state()

  local lsp = require('container.lsp.init')
  lsp.setup()

  -- Test without setting container ID
  local servers = lsp.detect_language_servers()

  assert(type(servers) == 'table', 'Should return table')
  assert(vim.tbl_count(servers) == 0, 'Should return empty table when no container')

  return true
end

function tests.test_client_exists_with_stopped_client()
  reset_test_state()

  local lsp = require('container.lsp.init')
  lsp.setup()

  -- Create a stopped client directly in test state
  local stopped_client = {
    id = 1,
    name = 'container_gopls',
    is_stopped = function()
      return true
    end,
    config = {},
  }
  test_state.lsp_clients[1] = stopped_client

  -- This should trigger the cleanup path for stopped clients
  local exists, client_id = lsp.client_exists('gopls')
  assert(exists == false, 'Stopped client should not be considered as existing')

  return true
end

function tests.test_prepare_lsp_config_comprehensive()
  reset_test_state()

  local lsp = require('container.lsp.init')
  lsp.setup()

  local server_config = {
    cmd = 'gopls',
    languages = { 'go' },
  }

  -- Test _prepare_lsp_config function
  local config = lsp._prepare_lsp_config('gopls', server_config)

  assert(type(config) == 'table', 'Should return config table')
  assert(config.name == 'container_gopls', 'Should have container prefix')
  assert(type(config.before_init) == 'function', 'Should have before_init')
  assert(type(config.on_init) == 'function', 'Should have on_init')
  assert(type(config.on_attach) == 'function', 'Should have on_attach')

  -- Test before_init callback
  local init_params = {
    workspaceFolders = { { uri = 'file:///old', name = 'old' } },
  }
  config.before_init(init_params, config)
  assert(init_params.rootUri ~= nil, 'Should set rootUri')

  -- Test on_init callback with mock client
  local mock_client = {
    workspace_folders = nil,
    server_capabilities = { workspace = { didChangeConfiguration = true } },
    notify = function() end,
  }
  config.on_init(mock_client, {})

  return true
end

function tests.test_defensive_handler_specific_cases()
  reset_test_state()

  local lsp = require('container.lsp.init')
  lsp.setup()

  local handler = vim.lsp.handlers['textDocument/publishDiagnostics']

  -- Test with malformed URI that starts with slash
  local result_with_slash = {
    uri = '/absolute/path.go',
    diagnostics = {},
  }
  handler(nil, result_with_slash, {}, {})
  assert(result_with_slash.uri == 'file:///absolute/path.go', 'Should fix URI with file:// prefix')

  return true
end

function tests.test_register_go_files_with_workspace_diagnostic()
  reset_test_state()

  local lsp = require('container.lsp.init')
  lsp.setup()

  -- Create client with workspace diagnostic support
  local client = {
    id = 1,
    is_stopped = function()
      return false
    end,
    notify = function(method, params) end,
    request = function(method, params, callback)
      if method == 'workspace/diagnostic' then
        -- Simulate successful diagnostic request
        if callback then
          callback(nil, { items = {} })
        end
      end
    end,
  }

  -- Mock io.open for reading files
  local original_io_open = io.open
  io.open = function(filename, mode)
    if mode == 'r' and filename:match('%.go$') then
      return {
        read = function()
          return 'package main\n'
        end,
        close = function() end,
      }
    end
    return original_io_open(filename, mode)
  end

  lsp._register_existing_go_files(client)

  -- Restore
  io.open = original_io_open

  return true
end

function tests.test_setup_auto_attach_comprehensive()
  reset_test_state()

  local lsp = require('container.lsp.init')
  lsp.setup()

  local server_config = {
    filetypes = { 'go', 'javascript' },
    languages = { 'go', 'javascript' },
  }

  -- Test auto-attach setup with multiple filetypes
  lsp._setup_auto_attach('test_server', server_config, 1)

  -- Verify autocmds were created for both filetypes
  assert(#test_state.events > 0, 'Should create autocmds')

  return true
end

function tests.test_attach_to_existing_buffers_comprehensive()
  reset_test_state()

  -- Add more buffers with different filetypes
  test_state.buffers = { 1, 2, 3, 4, 5 }

  local lsp = require('container.lsp.init')
  lsp.setup()

  local server_config = {
    filetypes = { 'go' },
    languages = { 'go' },
  }

  -- Mock buffer checking to simulate unloaded buffers
  local original_buf_is_loaded = vim.api.nvim_buf_is_loaded
  vim.api.nvim_buf_is_loaded = function(buf)
    return buf <= 3 -- Only first 3 buffers are loaded
  end

  lsp._attach_to_existing_buffers('test_server', server_config, 1)

  -- Restore
  vim.api.nvim_buf_is_loaded = original_buf_is_loaded

  return true
end

function tests.test_stop_client_comprehensive()
  reset_test_state()

  local lsp = require('container.lsp.init')
  lsp.setup()

  -- Test stopping non-existent client
  lsp.stop_client('nonexistent')

  -- Create client and then stop it
  test_state.lsp_clients[1] = {
    id = 1,
    name = 'container_gopls',
    stop = function() end,
  }

  lsp.stop_client('gopls')

  return true
end

function tests.test_health_check_with_issues()
  reset_test_state()

  local lsp = require('container.lsp.init')
  lsp.setup()

  -- Create stopped client to trigger health issues
  test_state.lsp_clients[1] = {
    id = 1,
    name = 'test_client',
    is_stopped = function()
      return true
    end,
  }

  local health = lsp.health_check()

  assert(type(health) == 'table', 'Should return health table')
  assert(type(health.issues) == 'table', 'Should have issues array')

  return true
end

function tests.test_get_debug_info_comprehensive()
  reset_test_state()

  local lsp = require('container.lsp.init')
  lsp.setup()
  lsp.set_container_id('test_container_123')

  -- Create some clients for debug info
  test_state.lsp_clients[1] = {
    id = 1,
    name = 'test_client',
    config = { root_dir = '/test', cmd = { 'test' } },
    is_stopped = function()
      return false
    end,
    initialized = true,
    attached_buffers = { 1 },
    server_capabilities = { test = true },
  }

  local debug_info = lsp.get_debug_info()

  assert(type(debug_info) == 'table', 'Should return debug info')
  assert(debug_info.container_id ~= nil, 'Should include container ID')
  assert(type(debug_info.active_clients) == 'table', 'Should include active clients')

  return true
end

function tests.test_clear_container_init_status_specific()
  reset_test_state()

  local lsp = require('container.lsp.init')
  lsp.setup()

  -- Test clearing initialization status
  lsp.clear_container_init_status('test_container_123')

  -- This mainly tests the function doesn't crash
  return true
end

function tests.test_setup_gopls_commands_with_keybindings()
  reset_test_state()

  local lsp = require('container.lsp.init')
  lsp.setup({
    keybindings = {
      hover = 'K',
      definition = 'gd',
      references = 'gr',
    },
  })

  -- Test gopls commands setup
  lsp._setup_gopls_commands(1)

  assert(#test_state.events > 0, 'Should create autocmds for gopls commands')

  return true
end

function tests.test_recover_all_lsp_servers_comprehensive()
  reset_test_state()

  local lsp = require('container.lsp.init')
  lsp.setup()
  lsp.set_container_id('test_container_123')

  -- Add some existing clients
  test_state.lsp_clients[1] = {
    id = 1,
    name = 'container_gopls',
    stop = function() end,
  }

  -- Test recovery
  lsp.recover_all_lsp_servers()

  return true
end

function tests.test_retry_lsp_server_with_max_attempts()
  reset_test_state()

  local lsp = require('container.lsp.init')
  lsp.setup()
  lsp.set_container_id('test_container_123')

  -- Detect servers first
  lsp.detect_language_servers()

  -- Test retry with specific max attempts
  lsp.retry_lsp_server_setup('gopls', 3)

  return true
end

function tests.test_analyze_client_with_existing_client()
  reset_test_state()

  local lsp = require('container.lsp.init')
  lsp.setup()

  -- Create detailed client for analysis
  test_state.lsp_clients[1] = {
    id = 1,
    name = 'test_client',
    is_stopped = function()
      return false
    end,
    initialized = true,
    config = {
      cmd = { 'test', '--lsp' },
      root_dir = '/test/workspace',
      capabilities = { workspace = true },
      settings = { test = { enabled = true } },
      init_options = { test_mode = true },
    },
    server_capabilities = {
      textDocumentSync = true,
      completionProvider = true,
    },
    workspace_folders = {
      { uri = 'file:///test/workspace', name = 'workspace' },
    },
    attached_buffers = { 1, 2 },
  }

  local analysis = lsp.analyze_client('test_client')

  assert(type(analysis) == 'table', 'Should return analysis')
  assert(analysis.basic_info.id == 1, 'Should have correct client ID')
  assert(type(analysis.config) == 'table', 'Should have config info')
  assert(type(analysis.server_info) == 'table', 'Should have server info')
  assert(type(analysis.buffer_attachment) == 'table', 'Should have buffer attachment info')

  return true
end

function tests.test_diagnose_lsp_server_detailed()
  reset_test_state()

  local lsp = require('container.lsp.init')
  lsp.setup()
  lsp.set_container_id('test_container_123')

  -- First detect servers
  local servers = lsp.detect_language_servers()

  -- Test diagnosis of detected server
  local diagnosis = lsp.diagnose_lsp_server('gopls')

  assert(type(diagnosis) == 'table', 'Should return diagnosis')
  if diagnosis.available then
    assert(type(diagnosis.details) == 'table', 'Should have details when available')
  end

  return true
end

-- Test runner
local function run_specific_coverage_tests()
  print('Running specific LSP init coverage tests...')
  print('==========================================')

  local test_functions = {
    'test_setup_with_nil_config',
    'test_language_server_detection_empty_container',
    'test_client_exists_with_stopped_client',
    'test_prepare_lsp_config_comprehensive',
    'test_defensive_handler_specific_cases',
    'test_register_go_files_with_workspace_diagnostic',
    'test_setup_auto_attach_comprehensive',
    'test_attach_to_existing_buffers_comprehensive',
    'test_stop_client_comprehensive',
    'test_health_check_with_issues',
    'test_get_debug_info_comprehensive',
    'test_clear_container_init_status_specific',
    'test_setup_gopls_commands_with_keybindings',
    'test_recover_all_lsp_servers_comprehensive',
    'test_retry_lsp_server_with_max_attempts',
    'test_analyze_client_with_existing_client',
    'test_diagnose_lsp_server_detailed',
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

  print('\n==========================================')
  print(string.format('Specific Coverage Tests Complete: %d/%d passed', passed, total))

  if #failed_tests > 0 then
    print('\nFailed tests:')
    for _, failure in ipairs(failed_tests) do
      print('  ✗ ' .. failure)
    end
  end

  if passed == total then
    print('All specific coverage tests passed! ✓')
    return 0
  else
    print('Some specific coverage tests failed. ✗')
    return 1
  end
end

-- Auto-run if executed directly
if not pcall(debug.getlocal, 4, 1) then
  local exit_code = run_specific_coverage_tests()
  os.exit(exit_code)
end

return tests
