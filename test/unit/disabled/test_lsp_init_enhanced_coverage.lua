#!/usr/bin/env lua

-- Enhanced unit tests for container.lsp.init module to achieve 70%+ coverage
-- This test focuses on uncovered code paths and advanced edge cases
-- Builds upon existing comprehensive and enhanced coverage tests

-- Add project lua directory to package path
package.path = './lua/?.lua;./lua/?/init.lua;../lua/?.lua;../lua/?/init.lua;' .. package.path

-- Test state for enhanced testing
local test_state = {
  lsp_clients = {},
  buffers = { 1, 2, 3 },
  current_buf = 1,
  docker_commands = {},
  events = {},
  use_old_api = false,
  commands_module_error = false,
  file_system_calls = {},
}

-- Mock vim global with enhanced LSP API testing
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
      return '/test/workspace/main.go\n/test/workspace/utils.go\n'
    end,
    shellescape = function(str)
      return "'" .. str .. "'"
    end,
  },

  -- Enhanced LSP mock with old/new API support
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
      if test_state.use_old_api then
        -- Return nil to force fallback to old API
        return nil
      end
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
      -- Old API fallback - return current clients directly
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
      if test_state.use_old_api then
        -- Return nil to force fallback to old API
        return nil
      end
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
    start_client = function(config)
      -- Old API fallback - implement directly
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

  -- API functions
  api = {
    nvim_create_augroup = function(name, opts)
      return math.random(1000)
    end,
    nvim_create_autocmd = function(events, opts)
      table.insert(test_state.events, { events = events, opts = opts })
      -- Test callback execution for coverage
      if opts.callback then
        local args = {
          buf = test_state.current_buf,
          data = { container_id = 'test_container_123' },
        }
        if events == 'User' then
          opts.callback(args)
        elseif vim.tbl_contains(events, 'BufEnter') or vim.tbl_contains(events, 'FileType') then
          opts.callback(args)
        elseif vim.tbl_contains(events, 'LspAttach') then
          args.data = { client_id = 1 }
          opts.callback(args)
        end
      end
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
      return '/test/workspace/main.go'
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
    -- Execute immediately for testing
    fn()
  end,
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

-- Mock commands module that can simulate failure
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
package.loaded['container.lsp.strategy'] = mock_strategy
package.loaded['lspconfig.util'] = mock_lspconfig_util

-- Helper functions
local function reset_test_state()
  test_state.lsp_clients = {}
  test_state.buffers = { 1, 2, 3 }
  test_state.current_buf = 1
  test_state.docker_commands = {}
  test_state.events = {}
  test_state.use_old_api = false
  test_state.commands_module_error = false
  test_state.file_system_calls = {}
end

-- Test suite focusing on uncovered paths
local tests = {}

function tests.test_old_api_fallback()
  reset_test_state()

  -- Setup vim APIs to simulate old API environment
  local old_get_clients = vim.lsp.get_clients
  local old_start = vim.lsp.start

  -- Remove new APIs to force fallback
  vim.lsp.get_clients = nil
  vim.lsp.start = nil

  local lsp = require('container.lsp.init')
  lsp.setup()
  lsp.set_container_id('test_container_123')

  -- Create a server config that would normally work
  local server_config = {
    cmd = 'gopls',
    languages = { 'go' },
    available = true,
    path = '/usr/local/bin/gopls',
  }

  -- This should trigger the old API paths in get_lsp_clients and start_lsp_client
  lsp.create_lsp_client('gopls', server_config)

  -- Restore APIs
  vim.lsp.get_clients = old_get_clients
  vim.lsp.start = old_start

  return true
end

function tests.test_commands_module_load_failure()
  reset_test_state()

  -- Make the commands module unavailable
  package.loaded['container.lsp.commands'] = nil
  package.preload['container.lsp.commands'] = function()
    error('Module not found')
  end

  local lsp = require('container.lsp.init')
  lsp.setup()

  -- This should trigger the commands module error path
  -- and execute the log.debug line that was uncovered

  -- Restore for other tests
  package.loaded['container.lsp.commands'] = mock_commands
  package.preload['container.lsp.commands'] = nil

  return true
end

function tests.test_auto_initialization_container_events()
  reset_test_state()

  -- Create some existing container_gopls clients to trigger cleanup
  test_state.lsp_clients[1] = {
    id = 1,
    name = 'container_gopls',
    is_stopped = function()
      return false
    end,
    initialized = true,
    stop = function() end,
    attached_buffers = { 1 },
  }

  local lsp = require('container.lsp.init')
  lsp.setup({ auto_setup = true })

  -- The autocmd callback should be executed automatically during setup
  -- This tests the check_go_buffers_and_setup function paths

  return true
end

function tests.test_container_status_management()
  reset_test_state()

  local lsp = require('container.lsp.init')
  lsp.setup()

  -- Test clearing container init status
  lsp.clear_container_init_status('test_container_123')

  return true
end

function tests.test_defensive_handler_edge_cases()
  reset_test_state()

  local lsp = require('container.lsp.init')
  lsp.setup()

  local handler = vim.lsp.handlers['textDocument/publishDiagnostics']

  -- Test error case
  handler('some error', nil, {}, {})

  -- Test nil result case
  handler(nil, nil, {}, {})

  -- Test empty URI case
  handler(nil, { uri = '', diagnostics = {} }, {}, {})

  -- Test URI without scheme case
  handler(nil, { uri = '/absolute/path', diagnostics = {} }, {}, {})

  -- Test URI without scheme that can't be fixed
  handler(nil, { uri = 'relative/path', diagnostics = {} }, {}, {})

  return true
end

function tests.test_register_existing_go_files_errors()
  reset_test_state()

  local lsp = require('container.lsp.init')
  lsp.setup()

  -- Create a stopped client to test error paths
  local stopped_client = {
    id = 1,
    is_stopped = function()
      return true
    end,
  }

  -- This should trigger the "client is stopped" warning
  lsp._register_existing_go_files(stopped_client)

  return true
end

function tests.test_file_operations_errors()
  reset_test_state()

  -- Mock io.open to simulate file read errors
  local original_io_open = io.open
  io.open = function(filename, mode)
    if mode == 'r' and filename:match('%.go$') then
      return nil -- Simulate file cannot be opened
    end
    return original_io_open(filename, mode)
  end

  local lsp = require('container.lsp.init')
  lsp.setup()

  -- Create a working client
  local client = {
    id = 1,
    is_stopped = function()
      return false
    end,
    notify = function(method, params) end,
    request = function(method, params, callback)
      if callback then
        callback(nil, {})
      end
    end,
  }

  -- This should trigger file read error paths
  lsp._register_existing_go_files(client)

  -- Restore io.open
  io.open = original_io_open

  return true
end

function tests.test_vim_system_error_handling()
  reset_test_state()

  -- Mock vim.v.shell_error to simulate command failures
  vim.v.shell_error = 1

  local lsp = require('container.lsp.init')
  lsp.setup()

  -- Create a working client
  local client = {
    id = 1,
    is_stopped = function()
      return false
    end,
    notify = function(method, params) end,
    request = function(method, params, callback)
      if callback then
        callback(nil, {})
      end
    end,
  }

  -- This should trigger the fallback to loaded buffers
  lsp._register_existing_go_files(client)

  -- Restore shell_error
  vim.v.shell_error = 0

  return true
end

function tests.test_lsp_client_notification_errors()
  reset_test_state()

  local lsp = require('container.lsp.init')
  lsp.setup()

  -- Create a client that throws errors on notify
  local error_client = {
    id = 1,
    is_stopped = function()
      return false
    end,
    notify = function(method, params)
      error('Notification failed')
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

  -- This should trigger the notification error handling
  lsp._register_existing_go_files(error_client)

  -- Restore io.open
  io.open = original_io_open

  return true
end

function tests.test_auto_setup_disabled()
  reset_test_state()

  local lsp = require('container.lsp.init')
  lsp.setup({ auto_setup = false })

  -- This should trigger the early return in setup_lsp_in_container
  lsp.setup_lsp_in_container()

  return true
end

function tests.test_gopls_commands_setup_paths()
  reset_test_state()

  -- Test when commands module is not available for gopls setup
  package.loaded['container.lsp.commands'] = nil
  package.preload['container.lsp.commands'] = function()
    error('Module not found')
  end

  local lsp = require('container.lsp.init')
  lsp.setup()

  -- This should trigger the commands_ok = false path
  lsp._setup_gopls_commands(1)

  -- Restore for other tests
  package.loaded['container.lsp.commands'] = mock_commands
  package.preload['container.lsp.commands'] = nil

  return true
end

function tests.test_setup_auto_attach_no_filetypes()
  reset_test_state()

  local lsp = require('container.lsp.init')
  lsp.setup()

  local server_config = {
    -- No filetypes or languages specified
  }

  -- This should trigger the early return for no filetypes
  lsp._setup_auto_attach('test_server', server_config, 1)

  return true
end

function tests.test_client_attachment_already_attached()
  reset_test_state()

  -- Create a client that's already attached to buffers
  test_state.lsp_clients[1] = {
    id = 1,
    name = 'test_client',
    is_stopped = function()
      return false
    end,
    attached_buffers = { 1 }, -- Already attached to buffer 1
  }

  local lsp = require('container.lsp.init')
  lsp.setup()

  local server_config = {
    filetypes = { 'go' },
    languages = { 'go' },
  }

  -- This should trigger the "already attached" code path
  lsp._attach_to_existing_buffers('test_server', server_config, 1)

  return true
end

function tests.test_strategy_initialization_errors()
  reset_test_state()

  -- Mock strategy module to test initialization failure
  local original_strategy = package.loaded['container.lsp.strategy']
  package.loaded['container.lsp.strategy'] = {
    setup = function()
      error('Strategy initialization failed')
    end,
    select_strategy = function()
      return 'test', {}
    end,
    create_client_with_strategy = function()
      return nil, 'Strategy creation failed'
    end,
    setup_path_transformation = function() end,
  }

  local lsp = require('container.lsp.init')
  lsp.setup()
  lsp.set_container_id('test_container_123')

  local server_config = {
    cmd = 'gopls',
    languages = { 'go' },
    available = true,
    path = '/usr/local/bin/gopls',
  }

  -- This should trigger strategy initialization error handling
  lsp.create_lsp_client('gopls', server_config)

  -- Restore original strategy
  package.loaded['container.lsp.strategy'] = original_strategy

  return true
end

function tests.test_lsp_client_immediate_failure()
  reset_test_state()

  -- Mock start_lsp_client to return nil (simulating immediate failure)
  local original_start = vim.lsp.start
  vim.lsp.start = function(config)
    return nil -- Simulate client start failure
  end

  local lsp = require('container.lsp.init')
  lsp.setup()
  lsp.set_container_id('test_container_123')

  local server_config = {
    cmd = 'gopls',
    languages = { 'go' },
    available = true,
    path = '/usr/local/bin/gopls',
  }

  -- This should trigger the client creation failure path
  lsp.create_lsp_client('gopls', server_config)

  -- Restore original function
  vim.lsp.start = original_start

  return true
end

function tests.test_language_server_detection_no_container()
  reset_test_state()

  local lsp = require('container.lsp.init')
  lsp.setup()
  -- Don't set container ID to test error path

  local servers = lsp.detect_language_servers()

  assert(type(servers) == 'table', 'Should return empty table when no container')
  assert(vim.tbl_count(servers) == 0, 'Should have no servers when no container ID')

  return true
end

function tests.test_setup_with_path_mappings_module()
  reset_test_state()

  -- Mock path utilities module
  local mock_path_utils = {
    get_local_workspace = function()
      return '/test/workspace'
    end,
    get_container_workspace = function()
      return '/workspace'
    end,
    setup = function(local_workspace, container_workspace)
      -- Mock setup
    end,
  }
  package.loaded['container.lsp.path'] = mock_path_utils

  local lsp = require('container.lsp.init')
  lsp.setup()
  lsp.set_container_id('test_container_123')

  local server_config = {
    cmd = 'gopls',
    languages = { 'go' },
    available = true,
    filetypes = { 'go' },
  }

  lsp.create_lsp_client('gopls', server_config)

  return true
end

function tests.test_existing_client_with_duplicates()
  reset_test_state()

  -- Create multiple existing clients with same name
  test_state.lsp_clients[1] = {
    id = 1,
    name = 'container_gopls',
    is_stopped = function()
      return false
    end,
    initialized = true,
    stop = function() end,
  }
  test_state.lsp_clients[2] = {
    id = 2,
    name = 'container_gopls',
    is_stopped = function()
      return false
    end,
    initialized = true,
    stop = function() end,
  }

  local lsp = require('container.lsp.init')
  lsp.setup()
  lsp.set_container_id('test_container_123')

  -- This should trigger the duplicate client cleanup path
  lsp.setup_lsp_in_container()

  return true
end

function tests.test_client_state_management_edge_cases()
  reset_test_state()

  local lsp = require('container.lsp.init')
  lsp.setup()

  -- Test client exists with stale state
  local stale_client_id = 999
  local server_config = { cmd = 'test' }

  -- Manually add stale state
  local state = lsp.get_state()
  -- Access internal state if possible (this tests cleanup logic)
  local exists, client_id = lsp.client_exists('nonexistent')
  assert(exists == false, 'Non-existent client should not exist')

  return true
end

function tests.test_auto_attach_client_stopped()
  reset_test_state()

  -- Create a stopped client to test auto-attach logic
  test_state.lsp_clients[1] = {
    id = 1,
    name = 'test_client',
    is_stopped = function()
      return true -- Client is stopped
    end,
    attached_buffers = {},
  }

  local lsp = require('container.lsp.init')
  lsp.setup()

  local server_config = {
    filetypes = { 'go' },
    languages = { 'go' },
  }

  -- Test auto-attach setup and execution
  lsp._setup_auto_attach('test_server', server_config, 1)

  return true
end

function tests.test_notify_module_errors()
  reset_test_state()

  -- Test path where notify module might not be available
  local original_notify = package.loaded['container.utils.notify']
  package.loaded['container.utils.notify'] = nil
  package.preload['container.utils.notify'] = function()
    error('Notify module not found')
  end

  local lsp = require('container.lsp.init')
  lsp.setup()
  lsp.set_container_id('test_container_123')

  -- Test retry setup which uses notify module
  lsp.retry_lsp_server_setup('nonexistent_server', 1)

  -- Restore
  package.loaded['container.utils.notify'] = original_notify
  package.preload['container.utils.notify'] = nil

  return true
end

function tests.test_workspace_diagnostic_request_error()
  reset_test_state()

  local lsp = require('container.lsp.init')
  lsp.setup()

  -- Create a client that fails on workspace diagnostic request
  local error_client = {
    id = 1,
    is_stopped = function()
      return false
    end,
    notify = function(method, params) end,
    request = function(method, params, callback)
      if method == 'workspace/diagnostic' and callback then
        callback('Workspace diagnostic error', nil)
      end
    end,
  }

  -- This should test the error handling in diagnostic request
  lsp._register_existing_go_files(error_client)

  return true
end

function tests.test_version_check_failure_in_diagnose()
  reset_test_state()

  -- Mock docker to fail version check
  local original_docker = package.loaded['container.docker.init']
  package.loaded['container.docker.init'] = {
    run_docker_command = function(args)
      if vim.tbl_contains(args, '--version') then
        return {
          success = false,
          stdout = '',
          stderr = 'Version check failed',
          code = 1,
        }
      end
      -- Normal which command
      return {
        success = true,
        stdout = '/usr/local/bin/gopls',
        stderr = '',
        code = 0,
      }
    end,
  }

  local lsp = require('container.lsp.init')
  lsp.setup()
  lsp.set_container_id('test_container_123')

  -- Detect servers first
  lsp.detect_language_servers()

  -- Test diagnose with version check failure
  local diagnosis = lsp.diagnose_lsp_server('gopls')
  assert(diagnosis.available == true, 'Server should be available')
  assert(diagnosis.working == false, 'Server should not be working due to version failure')

  -- Restore
  package.loaded['container.docker.init'] = original_docker

  return true
end

function tests.test_interceptor_metadata_checks()
  reset_test_state()

  local lsp = require('container.lsp.init')
  lsp.setup()

  -- Create a client with interceptor metadata to test on_init paths
  local client_with_metadata = {
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
    notify = function(method, params) end,
    request = function(method, params, callback)
      if callback then
        callback(nil, {})
      end
    end,
  }

  -- This should test the interceptor metadata check path
  lsp._register_existing_go_files(client_with_metadata)

  return true
end

-- Test runner
local function run_enhanced_coverage_tests()
  print('Running enhanced LSP init coverage tests...')
  print('===============================================')

  local test_functions = {
    'test_old_api_fallback',
    'test_commands_module_load_failure',
    'test_auto_initialization_container_events',
    'test_container_status_management',
    'test_defensive_handler_edge_cases',
    'test_register_existing_go_files_errors',
    'test_file_operations_errors',
    'test_vim_system_error_handling',
    'test_lsp_client_notification_errors',
    'test_auto_setup_disabled',
    'test_gopls_commands_setup_paths',
    'test_setup_auto_attach_no_filetypes',
    'test_client_attachment_already_attached',
    'test_strategy_initialization_errors',
    'test_lsp_client_immediate_failure',
    'test_language_server_detection_no_container',
    'test_setup_with_path_mappings_module',
    'test_existing_client_with_duplicates',
    'test_client_state_management_edge_cases',
    'test_auto_attach_client_stopped',
    'test_notify_module_errors',
    'test_workspace_diagnostic_request_error',
    'test_version_check_failure_in_diagnose',
    'test_interceptor_metadata_checks',
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

  print('\n===============================================')
  print(string.format('Enhanced Coverage Tests Complete: %d/%d passed', passed, total))

  if #failed_tests > 0 then
    print('\nFailed tests:')
    for _, failure in ipairs(failed_tests) do
      print('  ✗ ' .. failure)
    end
  end

  if passed == total then
    print('All enhanced coverage tests passed! ✓')
    return 0
  else
    print('Some enhanced coverage tests failed. ✗')
    return 1
  end
end

-- Auto-run if executed directly
if not pcall(debug.getlocal, 4, 1) then
  local exit_code = run_enhanced_coverage_tests()
  os.exit(exit_code)
end

return tests
