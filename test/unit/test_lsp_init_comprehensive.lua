#!/usr/bin/env lua

-- Comprehensive LSP init module test for maximum coverage
-- Target: Achieve 70%+ coverage for lua/container/lsp/init.lua

package.path = './lua/?.lua;./lua/?/init.lua;../lua/?.lua;../lua/?/init.lua;' .. package.path

print('=== LSP Init Comprehensive Coverage Test ===')
print('Target: lsp/init.lua module coverage improvement from 9.04% to 70%+')

-- Mock system for comprehensive testing
local test_state = {
  containers = {},
  lsp_clients = {},
  docker_commands = {},
  events = {},
  buffers = {},
  current_buf = 1,
}

-- Mock vim global with comprehensive LSP support
_G.vim = {
  -- Basic table utilities
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
    tempname = function()
      return '/tmp/test_' .. math.random(10000)
    end,
    shellescape = function(str)
      return "'" .. str .. "'"
    end,
    system = function(cmd)
      test_state.docker_commands[#test_state.docker_commands + 1] = cmd
      if cmd:match('find.*%.go') then
        return '/test/workspace/main.go\n/test/workspace/utils.go\n'
      end
      return ''
    end,
    mkdir = function(path, flags)
      return true
    end,
  },

  -- LSP mock functions
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
      -- Simulate initialization after short delay
      vim.defer_fn(function()
        client.initialized = true
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

  -- API functions
  api = {
    nvim_create_augroup = function(name, opts)
      return math.random(1000)
    end,
    nvim_create_autocmd = function(events, opts)
      table.insert(test_state.events, { events = events, opts = opts })
      return math.random(1000)
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
  log = { levels = { DEBUG = 0, INFO = 1, WARN = 2, ERROR = 3 } },
  notify = function(msg, level) end,
  defer_fn = function(fn, delay)
    -- Execute immediately for testing
    fn()
  end,
  wait = function(ms) end,
  cmd = function(command) end,
}

-- Set up vim.bo as a metatable for buffer options
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
    test_state.docker_commands[#test_state.docker_commands + 1] = table.concat(args, ' ')

    -- Mock successful which commands for known servers
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
    local patterns = { ... }
    return function(fname)
      for _, pattern in ipairs(patterns) do
        if pattern == 'go.mod' then
          return '/test/workspace'
        end
      end
      return nil
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

-- Helper functions
local function reset_test_state()
  test_state.containers = {}
  test_state.lsp_clients = {}
  test_state.docker_commands = {}
  test_state.events = {}
  test_state.buffers = { 1, 2, 3 }
  test_state.current_buf = 1
end

local function add_test_buffer(filetype)
  filetype = filetype or 'go'
  local buf_id = #test_state.buffers + 1
  table.insert(test_state.buffers, buf_id)
  return buf_id
end

-- Test suite
local tests = {}

function tests.test_module_initialization()
  reset_test_state()

  local lsp = require('container.lsp.init')

  -- Test basic setup
  lsp.setup({
    auto_setup = true,
    timeout = 5000,
    servers = {
      gopls = { cmd = 'gopls' },
    },
  })

  local state = lsp.get_state()
  assert(state.config ~= nil, 'Config should be set after setup')
  assert(state.config.auto_setup == true, 'Auto setup should be enabled')
  assert(state.config.timeout == 5000, 'Timeout should be set correctly')

  return true
end

function tests.test_setup_with_custom_config()
  reset_test_state()

  local lsp = require('container.lsp.init')

  local custom_config = {
    auto_setup = false,
    timeout = 10000,
    servers = {
      gopls = { cmd = 'gopls', extra_option = true },
      pylsp = { cmd = 'pylsp' },
    },
    keybindings = {
      hover = 'K',
      definition = 'gd',
    },
  }

  lsp.setup(custom_config)

  local state = lsp.get_state()
  assert(state.config.auto_setup == false, 'Auto setup should be disabled')
  assert(state.config.timeout == 10000, 'Custom timeout should be set')
  assert(state.config.servers.gopls.extra_option == true, 'Custom server config should be preserved')
  assert(state.config.keybindings.hover == 'K', 'Custom keybindings should be set')

  return true
end

function tests.test_container_id_management()
  reset_test_state()

  local lsp = require('container.lsp.init')
  lsp.setup()

  -- Test setting container ID
  lsp.set_container_id('test_container_123')

  local state = lsp.get_state()
  assert(state.container_id == 'test_container_123', 'Container ID should be set correctly')

  return true
end

function tests.test_language_server_detection()
  reset_test_state()

  local lsp = require('container.lsp.init')
  lsp.setup()
  lsp.set_container_id('test_container_123')

  local servers = lsp.detect_language_servers()

  assert(type(servers) == 'table', 'Servers should be returned as table')
  assert(servers.gopls ~= nil, 'gopls should be detected')
  assert(servers.gopls.available == true, 'gopls should be available')
  assert(servers.gopls.cmd == 'gopls', 'gopls command should be correct')
  assert(type(servers.gopls.languages) == 'table', 'gopls should have languages list')

  -- Check that docker commands were executed
  local found_which_command = false
  for _, cmd in ipairs(test_state.docker_commands) do
    if cmd:match('which gopls') then
      found_which_command = true
      break
    end
  end
  assert(found_which_command, 'Docker which command should have been executed')

  return true
end

function tests.test_client_exists_check()
  reset_test_state()

  local lsp = require('container.lsp.init')
  lsp.setup()

  -- Test when client doesn't exist
  local exists, client_id = lsp.client_exists('gopls')
  assert(exists == false, 'Client should not exist initially')
  assert(client_id == nil, 'Client ID should be nil when not exists')

  -- Create a mock client
  local mock_client = {
    id = 1,
    name = 'container_gopls',
    is_stopped = function()
      return false
    end,
    config = {},
  }
  test_state.lsp_clients[1] = mock_client

  -- Test when client exists
  exists, client_id = lsp.client_exists('gopls')
  assert(exists == true, 'Client should exist after creation')
  assert(client_id == 1, 'Client ID should be returned correctly')

  return true
end

function tests.test_lsp_client_creation()
  reset_test_state()

  local lsp = require('container.lsp.init')
  lsp.setup()
  lsp.set_container_id('test_container_123')

  local server_config = {
    cmd = 'gopls',
    languages = { 'go' },
    available = true,
    path = '/usr/local/bin/gopls',
  }

  lsp.create_lsp_client('gopls', server_config)

  -- Check that client was created
  local state = lsp.get_state()
  assert(vim.tbl_contains(state.clients, 'gopls'), 'gopls client should be in state')

  -- Check that LSP client was actually started
  local clients = vim.lsp.get_clients({ name = 'container_gopls' })
  assert(#clients > 0, 'container_gopls client should be created')

  return true
end

function tests.test_lsp_setup_in_container()
  reset_test_state()

  local lsp = require('container.lsp.init')
  lsp.setup({ auto_setup = true })
  lsp.set_container_id('test_container_123')

  lsp.setup_lsp_in_container()

  -- Verify that servers were detected and clients created
  local state = lsp.get_state()
  assert(#state.clients > 0, 'At least one client should be created')

  return true
end

function tests.test_auto_initialization()
  reset_test_state()

  local lsp = require('container.lsp.init')
  lsp.setup({ auto_setup = true })

  -- Check that autocmds were created
  assert(#test_state.events > 0, 'Auto-initialization should create autocmds')

  -- Find User events (looking for ContainerDetected, ContainerStarted, ContainerOpened, or FileType events)
  local found_container_related_event = false
  for _, event in ipairs(test_state.events) do
    if type(event.events) == 'table' then
      -- Check for User events with container patterns
      if vim.tbl_contains(event.events, 'User') then
        if event.opts and event.opts.pattern then
          local patterns = type(event.opts.pattern) == 'table' and event.opts.pattern or { event.opts.pattern }
          for _, pattern in ipairs(patterns) do
            if pattern:match('Container') then
              found_container_related_event = true
              break
            end
          end
        end
      end
      -- Also check for FileType events (fallback mechanism)
      if vim.tbl_contains(event.events, 'FileType') or vim.tbl_contains(event.events, 'BufEnter') then
        found_container_related_event = true
      end
    end
    if found_container_related_event then
      break
    end
  end
  assert(found_container_related_event, 'Container-related events should be registered')

  return true
end

function tests.test_auto_attach_to_buffers()
  reset_test_state()

  local lsp = require('container.lsp.init')
  lsp.setup()
  lsp.set_container_id('test_container_123')

  -- Create test server config
  local server_config = {
    cmd = 'gopls',
    languages = { 'go' },
    filetypes = { 'go' },
    available = true,
  }

  -- Create client
  lsp.create_lsp_client('gopls', server_config)

  -- Get client ID
  local clients = vim.lsp.get_clients({ name = 'container_gopls' })
  assert(#clients > 0, 'Client should be created')

  local client = clients[1]

  -- Test auto-attach setup
  lsp._attach_to_existing_buffers('gopls', server_config, client.id)

  -- Check that Go buffers were attached
  assert(#client.attached_buffers > 0, 'Client should be attached to Go buffers')

  return true
end

function tests.test_global_defensive_handler()
  reset_test_state()

  local lsp = require('container.lsp.init')
  lsp.setup()

  -- Test that global defensive handler is installed
  local handler = vim.lsp.handlers['textDocument/publishDiagnostics']
  assert(type(handler) == 'function', 'Defensive handler should be installed')

  -- Test handler with valid result
  local valid_result = {
    uri = 'file:///test/path.go',
    diagnostics = {},
  }
  local response = handler(nil, valid_result, {}, {})
  assert(response ~= nil, 'Handler should process valid results')

  -- Test handler with invalid URI
  local invalid_result = {
    uri = '',
    diagnostics = {},
  }
  handler(nil, invalid_result, {}, {}) -- Should not crash

  return true
end

function tests.test_stop_all_clients()
  reset_test_state()

  local lsp = require('container.lsp.init')
  lsp.setup()
  lsp.set_container_id('test_container_123')

  -- Create multiple clients
  local server_configs = {
    gopls = { cmd = 'gopls', languages = { 'go' }, available = true },
    pylsp = { cmd = 'pylsp', languages = { 'python' }, available = true },
  }

  for name, config in pairs(server_configs) do
    lsp.create_lsp_client(name, config)
  end

  -- Verify clients exist
  local state = lsp.get_state()
  assert(#state.clients > 0, 'Clients should exist before stopping')

  -- Stop all clients
  lsp.stop_all()

  -- Verify clients are stopped
  state = lsp.get_state()
  assert(#state.clients == 0, 'All clients should be stopped')
  assert(state.container_id == nil, 'Container ID should be cleared')

  return true
end

function tests.test_stop_specific_client()
  reset_test_state()

  local lsp = require('container.lsp.init')
  lsp.setup()
  lsp.set_container_id('test_container_123')

  -- Create clients
  local server_config = {
    cmd = 'gopls',
    languages = { 'go' },
    available = true,
  }

  lsp.create_lsp_client('gopls', server_config)

  -- Verify client exists
  local state = lsp.get_state()
  assert(vim.tbl_contains(state.clients, 'gopls'), 'gopls client should exist')

  -- Stop specific client
  lsp.stop_client('gopls')

  -- Verify client is removed
  state = lsp.get_state()
  assert(not vim.tbl_contains(state.clients, 'gopls'), 'gopls client should be removed')

  return true
end

function tests.test_health_check()
  reset_test_state()

  local lsp = require('container.lsp.init')
  lsp.setup()

  -- Test health check without container
  local health = lsp.health_check()
  assert(type(health) == 'table', 'Health check should return table')
  -- The container_connected might be true due to mock container state
  assert(type(health.container_connected) == 'boolean', 'Should report container connection status')
  assert(type(health.servers_detected) == 'number', 'Should report servers detected count')
  assert(type(health.clients_active) == 'number', 'Should report clients active count')
  assert(type(health.issues) == 'table', 'Should return issues list')

  -- Set container and test again
  lsp.set_container_id('test_container_123')
  health = lsp.health_check()
  assert(health.container_connected == true, 'Should report container connected')

  return true
end

function tests.test_debug_info()
  reset_test_state()

  local lsp = require('container.lsp.init')
  lsp.setup()
  lsp.set_container_id('test_container_123')

  local debug_info = lsp.get_debug_info()
  assert(type(debug_info) == 'table', 'Debug info should return table')
  assert(debug_info.config ~= nil, 'Debug info should include config')
  assert(debug_info.state ~= nil, 'Debug info should include state')
  assert(debug_info.container_id ~= nil, 'Debug info should include container ID')
  assert(type(debug_info.active_clients) == 'table', 'Debug info should include active clients')
  assert(type(debug_info.current_buffer_clients) == 'table', 'Debug info should include buffer clients')

  return true
end

function tests.test_diagnose_lsp_server()
  reset_test_state()

  local lsp = require('container.lsp.init')
  lsp.setup()
  lsp.set_container_id('test_container_123')

  -- Test diagnosis of non-existent server
  local diagnosis = lsp.diagnose_lsp_server('nonexistent_server')
  assert(type(diagnosis) == 'table', 'Diagnosis should return table')
  assert(diagnosis.available == false, 'Non-existent server should not be available')
  assert(type(diagnosis.error) == 'string', 'Should provide error message')
  assert(type(diagnosis.suggestions) == 'table', 'Should provide suggestions')

  -- First detect servers to have some in state
  lsp.detect_language_servers()

  -- Test diagnosis of existing server
  diagnosis = lsp.diagnose_lsp_server('gopls')
  assert(type(diagnosis) == 'table', 'Diagnosis should return table')
  assert(diagnosis.available == true, 'gopls should be available')

  return true
end

function tests.test_retry_lsp_server_setup()
  reset_test_state()

  local lsp = require('container.lsp.init')
  lsp.setup()
  lsp.set_container_id('test_container_123')

  -- First detect servers
  lsp.detect_language_servers()

  -- Test retry setup
  lsp.retry_lsp_server_setup('gopls', 2)

  -- This test mainly verifies that the function doesn't crash
  -- The actual retry logic involves timers that are hard to test synchronously

  return true
end

function tests.test_recover_all_lsp_servers()
  reset_test_state()

  local lsp = require('container.lsp.init')
  lsp.setup()
  lsp.set_container_id('test_container_123')

  -- Create some clients first
  lsp.detect_language_servers()
  lsp.setup_lsp_in_container()

  -- Test recovery
  lsp.recover_all_lsp_servers()

  -- This test mainly verifies that the function doesn't crash
  -- The actual recovery logic involves async operations

  return true
end

function tests.test_analyze_client()
  reset_test_state()

  local lsp = require('container.lsp.init')
  lsp.setup()

  -- Test analysis of non-existent client
  local analysis = lsp.analyze_client('nonexistent_client')
  assert(type(analysis) == 'table', 'Analysis should return table')
  assert(analysis.error ~= nil, 'Should report error for non-existent client')

  return true
end

function tests.test_clear_container_init_status()
  reset_test_state()

  local lsp = require('container.lsp.init')
  lsp.setup()

  -- Test clearing initialization status
  lsp.clear_container_init_status('test_container_123')

  -- This function mainly cleans internal state, hard to test directly
  -- But it should not crash

  return true
end

function tests.test_setup_auto_attach()
  reset_test_state()

  local lsp = require('container.lsp.init')
  lsp.setup()

  local server_config = {
    filetypes = { 'go' },
    languages = { 'go' },
  }

  -- Test auto-attach setup
  lsp._setup_auto_attach('gopls', server_config, 1)

  -- Should create autocmds for file type events
  local found_filetype_event = false
  for _, event in ipairs(test_state.events) do
    if
      type(event.events) == 'table'
      and (vim.tbl_contains(event.events, 'BufEnter') or vim.tbl_contains(event.events, 'BufNewFile'))
    then
      found_filetype_event = true
      break
    end
  end
  assert(found_filetype_event, 'Auto-attach should create file type events')

  return true
end

function tests.test_setup_gopls_commands()
  reset_test_state()

  local lsp = require('container.lsp.init')
  lsp.setup()

  -- Test gopls commands setup
  lsp._setup_gopls_commands(1)

  -- Should create autocmds for gopls-specific commands
  local found_go_event = false
  for _, event in ipairs(test_state.events) do
    if event.opts and event.opts.pattern then
      local patterns = type(event.opts.pattern) == 'table' and event.opts.pattern or { event.opts.pattern }
      for _, pattern in ipairs(patterns) do
        if pattern:match('%.go') or pattern == 'go' then
          found_go_event = true
          break
        end
      end
    end
    if found_go_event then
      break
    end
  end
  assert(found_go_event, 'gopls commands setup should create Go-specific events')

  return true
end

function tests.test_register_existing_files()
  reset_test_state()

  local lsp = require('container.lsp.init')
  lsp.setup()

  -- Create a mock client
  local mock_client = {
    id = 1,
    is_stopped = function()
      return false
    end,
    notify = function(method, params)
      assert(method == 'textDocument/didOpen', 'Should call didOpen notification')
      assert(params.textDocument.languageId == 'go', 'Should set language ID to go')
    end,
    request = function(method, params, callback)
      if callback then
        callback(nil, {})
      end
    end,
  }

  -- Mock io.open to return test content
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

  -- Test file registration with language config
  local language_registry = require('container.lsp.language_registry')
  local go_config = language_registry.get_by_filetype('go')
  if go_config then
    lsp._register_existing_files(mock_client, go_config)
  end

  -- Restore io.open
  io.open = original_io_open

  return true
end

function tests.test_prepare_lsp_config()
  reset_test_state()

  local lsp = require('container.lsp.init')
  lsp.setup()

  local server_config = {
    cmd = 'gopls',
    languages = { 'go' },
  }

  local config = lsp._prepare_lsp_config('gopls', server_config)

  assert(type(config) == 'table', 'Should return config table')
  assert(config.name == 'container_gopls', 'Should have container prefix')
  assert(type(config.filetypes) == 'table', 'Should have filetypes')
  assert(type(config.before_init) == 'function', 'Should have before_init callback')
  assert(type(config.on_init) == 'function', 'Should have on_init callback')
  assert(type(config.on_attach) == 'function', 'Should have on_attach callback')
  assert(type(config.root_dir) == 'function', 'Should have root_dir function')

  return true
end

function tests.test_error_handling_invalid_inputs()
  reset_test_state()

  local lsp = require('container.lsp.init')
  lsp.setup()

  -- Test create_lsp_client with invalid inputs
  local result1 = lsp.create_lsp_client(nil, {})
  assert(result1 == nil, 'Should handle nil server name')

  local result2 = lsp.create_lsp_client('test', nil)
  assert(result2 == nil, 'Should handle nil server config')

  local result3 = lsp.create_lsp_client('test', 'invalid')
  assert(result3 == nil, 'Should handle invalid server config type')

  return true
end

-- Test runner
local function run_comprehensive_tests()
  print('Running comprehensive LSP init module tests...')
  print('==============================================')

  local test_functions = {
    'test_module_initialization',
    'test_setup_with_custom_config',
    'test_container_id_management',
    'test_language_server_detection',
    'test_client_exists_check',
    'test_lsp_client_creation',
    'test_lsp_setup_in_container',
    'test_auto_initialization',
    'test_auto_attach_to_buffers',
    'test_global_defensive_handler',
    'test_stop_all_clients',
    'test_stop_specific_client',
    'test_health_check',
    'test_debug_info',
    'test_diagnose_lsp_server',
    'test_retry_lsp_server_setup',
    'test_recover_all_lsp_servers',
    'test_analyze_client',
    'test_clear_container_init_status',
    'test_setup_auto_attach',
    'test_setup_gopls_commands',
    'test_register_existing_files',
    'test_prepare_lsp_config',
    'test_error_handling_invalid_inputs',
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

  print('\n==============================================')
  print(string.format('LSP Init Tests Complete: %d/%d passed', passed, total))

  if #failed_tests > 0 then
    print('\nFailed tests:')
    for _, failure in ipairs(failed_tests) do
      print('  ✗ ' .. failure)
    end
  end

  if passed == total then
    print('All LSP init tests passed! ✓')
    return 0
  else
    print('Some LSP init tests failed. ✗')
    return 1
  end
end

-- Auto-run if executed directly
if not pcall(debug.getlocal, 4, 1) then
  local exit_code = run_comprehensive_tests()
  os.exit(exit_code)
end

return tests
