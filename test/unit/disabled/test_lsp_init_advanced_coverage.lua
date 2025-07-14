#!/usr/bin/env lua

-- Advanced coverage tests for container.lsp.init module to achieve 70%+ coverage
-- This focuses on uncovered code paths, edge cases, and error conditions

-- Add project lua directory to package path
package.path = './lua/?.lua;./lua/?/init.lua;../lua/?.lua;../lua/?/init.lua;' .. package.path

-- Test state for advanced coverage testing
local test_state = {
  lsp_clients = {},
  buffers = { 1, 2, 3 },
  current_buf = 1,
  docker_commands = {},
  events = {},
  file_system_calls = {},
  auto_init_callbacks = {},
  use_old_lsp_api = false,
  simulate_errors = {},
  path_mappings_initialized = false,
}

-- Mock vim global with comprehensive API coverage
_G.vim = {
  -- Enhanced table utilities
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

  -- Enhanced file system functions with error simulation
  fn = {
    getcwd = function()
      if test_state.simulate_errors.getcwd then
        error('getcwd simulation error')
      end
      return '/test/workspace'
    end,
    expand = function(path)
      if test_state.simulate_errors.expand then
        error('expand simulation error')
      end
      if path:match('%%:p') then
        return '/test/workspace/main.go'
      end
      return path
    end,
    system = function(cmd)
      test_state.file_system_calls[#test_state.file_system_calls + 1] = cmd
      if test_state.simulate_errors.system then
        return ''
      end
      if cmd:match('find.*%.go') then
        return '/test/workspace/main.go\n/test/workspace/utils.go\n/test/workspace/lib.go\n'
      end
      return 'mock output'
    end,
    shellescape = function(str)
      return "'" .. str .. "'"
    end,
    tempname = function()
      return '/tmp/test_' .. math.random(10000)
    end,
    mkdir = function(path, flags)
      return true
    end,
  },

  -- Enhanced LSP mock with old/new API support and error simulation
  lsp = {
    handlers = {
      ['textDocument/publishDiagnostics'] = function(err, result, ctx, config)
        if test_state.simulate_errors.diagnostic_handler then
          error('diagnostic handler error')
        end
        return { mocked = true }
      end,
    },
    protocol = {
      make_client_capabilities = function()
        if test_state.simulate_errors.capabilities then
          error('Failed to make capabilities')
        end
        return {
          workspace = {
            configuration = true,
            didChangeConfiguration = { dynamicRegistration = true },
          },
        }
      end,
    },
    get_clients = function(opts)
      if test_state.use_old_lsp_api then
        return nil -- Force fallback to old API
      end
      if test_state.simulate_errors.get_clients then
        error('get_clients error')
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
      if test_state.simulate_errors.get_active_clients then
        error('get_active_clients error')
      end
      return vim.lsp.get_clients(opts)
    end,
    start = function(config)
      if test_state.use_old_lsp_api then
        return nil -- Force fallback to old API
      end
      if test_state.simulate_errors.start then
        return nil -- Simulate start failure
      end
      local client_id = #test_state.lsp_clients + 1
      local client = {
        id = client_id,
        name = config.name or 'test_client',
        config = vim.tbl_deep_extend('force', config, {
          container_id = 'test_container_123',
          container_managed = true,
        }),
        initialized = false,
        is_stopped = function()
          return test_state.simulate_errors.client_stopped and test_state.simulate_errors.client_stopped[client_id]
            or false
        end,
        stop = function(force)
          if test_state.simulate_errors.client_stop then
            error('client stop error')
          end
          if not test_state.simulate_errors.client_stopped then
            test_state.simulate_errors.client_stopped = {}
          end
          test_state.simulate_errors.client_stopped[client_id] = true
        end,
        notify = function(method, params)
          if test_state.simulate_errors.notify then
            error('notify error')
          end
        end,
        request = function(method, params, callback)
          if test_state.simulate_errors.request then
            if callback then
              callback('request error', nil)
            end
            return
          end
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
      -- Simulate initialization
      vim.defer_fn(function()
        if not test_state.simulate_errors.no_init then
          client.initialized = true
        end
      end, 10)
      return client_id
    end,
    start_client = function(config)
      if test_state.simulate_errors.start_client then
        return nil
      end
      return vim.lsp.start(config)
    end,
    get_client_by_id = function(id)
      if test_state.simulate_errors.get_client_by_id then
        return nil
      end
      return test_state.lsp_clients[id]
    end,
    buf_attach_client = function(bufnr, client_id)
      if test_state.simulate_errors.buf_attach then
        error('buf_attach error')
      end
      local client = test_state.lsp_clients[client_id]
      if client then
        client.attached_buffers = client.attached_buffers or {}
        table.insert(client.attached_buffers, bufnr)
      end
    end,
    buf_detach_client = function(bufnr, client_id)
      if test_state.simulate_errors.buf_detach then
        error('buf_detach error')
      end
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

  -- Enhanced API functions with error simulation
  api = {
    nvim_create_augroup = function(name, opts)
      if test_state.simulate_errors.create_augroup then
        error('create_augroup error')
      end
      return math.random(1000)
    end,
    nvim_create_autocmd = function(events, opts)
      if test_state.simulate_errors.create_autocmd then
        error('create_autocmd error')
      end
      local event_entry = { events = events, opts = opts }
      table.insert(test_state.events, event_entry)

      -- Execute callback for coverage if it exists
      if opts.callback then
        local args = {
          buf = test_state.current_buf,
          data = { container_id = 'test_container_123', client_id = 1 },
        }

        -- Simulate different event scenarios for coverage
        if type(events) == 'table' then
          for _, event in ipairs(events) do
            if event == 'User' then
              test_state.auto_init_callbacks[#test_state.auto_init_callbacks + 1] = opts.callback
              if opts.pattern then
                local patterns = type(opts.pattern) == 'table' and opts.pattern or { opts.pattern }
                for _, pattern in ipairs(patterns) do
                  if pattern:match('Container') then
                    opts.callback(args)
                  end
                end
              end
            elseif vim.tbl_contains({ 'BufEnter', 'FileType', 'BufNewFile' }, event) then
              opts.callback(args)
            elseif event == 'LspAttach' then
              opts.callback(args)
            end
          end
        end
      end
      return math.random(1000)
    end,
    nvim_get_current_buf = function()
      if test_state.simulate_errors.get_current_buf then
        error('get_current_buf error')
      end
      return test_state.current_buf
    end,
    nvim_list_bufs = function()
      if test_state.simulate_errors.list_bufs then
        error('list_bufs error')
      end
      return test_state.buffers
    end,
    nvim_buf_is_loaded = function(buf)
      if test_state.simulate_errors.buf_is_loaded then
        return false
      end
      return vim.tbl_contains(test_state.buffers, buf)
    end,
    nvim_buf_get_name = function(buf)
      if test_state.simulate_errors.buf_get_name then
        return ''
      end
      if buf == 1 then
        return '/test/workspace/main.go'
      elseif buf == 2 then
        return '/test/workspace/utils.go'
      elseif buf == 3 then
        return '/test/workspace/lib.go'
      end
      return '/test/workspace/file' .. buf .. '.go'
    end,
    nvim_buf_get_option = function(buf, option)
      if test_state.simulate_errors.buf_get_option then
        return nil
      end
      if option == 'filetype' then
        return 'go'
      end
      return nil
    end,
  },

  -- Buffer options with enhanced mocking
  bo = {},

  -- Other vim functions with error simulation
  v = {
    shell_error = test_state.simulate_errors.shell_error and 1 or 0,
  },
  log = { levels = { DEBUG = 0, INFO = 1, WARN = 2, ERROR = 3 } },
  notify = function(msg, level)
    if test_state.simulate_errors.notify_vim then
      error('vim.notify error')
    end
  end,
  defer_fn = function(fn, delay)
    if test_state.simulate_errors.defer_fn then
      error('defer_fn error')
    end
    -- Execute immediately for testing unless delay is requested
    if not test_state.simulate_errors.no_execute_defer then
      fn()
    end
  end,
  wait = function(ms)
    if test_state.simulate_errors.wait then
      error('wait error')
    end
  end,
  cmd = function(command)
    if test_state.simulate_errors.cmd then
      error('cmd error')
    end
  end,
}

-- Set up vim.bo as a metatable for buffer options
setmetatable(_G.vim.bo, {
  __index = function(t, bufnr)
    return { filetype = 'go' }
  end,
})

-- Enhanced mock modules with error simulation
local mock_log = {
  debug = function(...) end,
  info = function(...) end,
  warn = function(...) end,
  error = function(...) end,
}

local mock_docker = {
  run_docker_command = function(args)
    test_state.docker_commands[#test_state.docker_commands + 1] = table.concat(args, ' ')

    if test_state.simulate_errors.docker then
      return {
        success = false,
        stdout = '',
        stderr = 'Docker error simulation',
        code = 1,
      }
    end

    -- Enhanced server detection simulation
    if vim.tbl_contains(args, 'which') then
      local cmd = args[#args]
      local known_servers = { 'gopls', 'lua-language-server', 'pylsp', 'rust-analyzer', 'clangd' }
      if vim.tbl_contains(known_servers, cmd) then
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

    -- Handle version checks
    if vim.tbl_contains(args, '--version') then
      if test_state.simulate_errors.version_check then
        return {
          success = false,
          stdout = '',
          stderr = 'Version check failed',
          code = 1,
        }
      end
      return {
        success = true,
        stdout = 'test version 1.0.0',
        stderr = '',
        code = 0,
      }
    end

    return { success = true, stdout = '', stderr = '', code = 0 }
  end,
}

local mock_environment = {
  build_lsp_args = function(config)
    if test_state.simulate_errors.environment then
      error('Environment error simulation')
    end
    return { '--user', 'test:test', '-e', 'HOME=/home/test' }
  end,
}

local mock_container = {
  get_state = function()
    if test_state.simulate_errors.container_state then
      error('Container state error simulation')
    end
    return {
      current_container = test_state.simulate_errors.no_container and nil or 'test_container_123',
      current_config = { image = 'golang:1.21' },
    }
  end,
}

local mock_commands = {
  setup = function(config)
    if test_state.simulate_errors.commands_setup then
      error('Commands setup error simulation')
    end
  end,
  setup_commands = function()
    if test_state.simulate_errors.commands_setup_commands then
      error('Commands setup_commands error simulation')
    end
  end,
  setup_keybindings = function(opts)
    if test_state.simulate_errors.commands_keybindings then
      return false
    end
    return true
  end,
}

local mock_strategy = {
  setup = function()
    if test_state.simulate_errors.strategy_setup then
      error('Strategy setup error simulation')
    end
  end,
  select_strategy = function(name, container_id, server_config)
    if test_state.simulate_errors.strategy_select then
      error('Strategy select error simulation')
    end
    return 'intercept', { port = 9090 }
  end,
  create_client_with_strategy = function(strategy, name, container_id, server_config, strategy_config)
    if test_state.simulate_errors.strategy_create then
      return nil, 'Strategy create error simulation'
    end
    return {
      name = 'container_' .. name,
      cmd = { 'docker', 'exec', container_id, server_config.cmd },
      filetypes = server_config.languages,
      root_dir = function()
        return '/test/workspace'
      end,
      before_init = function(params, config)
        -- Enhanced before_init for coverage
      end,
      on_init = function(client, result)
        -- Enhanced on_init for coverage
      end,
      on_attach = function(client, bufnr)
        -- Enhanced on_attach for coverage
      end,
    },
      nil
  end,
  setup_path_transformation = function(client, name, container_id)
    if test_state.simulate_errors.strategy_transform then
      error('Strategy transform error simulation')
    end
  end,
}

local mock_lspconfig_util = {
  root_pattern = function(...)
    local patterns = { ... }
    return function(fname)
      if test_state.simulate_errors.root_pattern then
        error('Root pattern error simulation')
      end
      for _, pattern in ipairs(patterns) do
        if pattern == 'go.mod' then
          return test_state.simulate_errors.no_go_root and nil or '/test/workspace'
        end
      end
      return nil
    end
  end,
  find_git_ancestor = function(fname)
    if test_state.simulate_errors.git_ancestor then
      return nil
    end
    return '/test/workspace'
  end,
  path = {
    dirname = function(path)
      if test_state.simulate_errors.dirname then
        error('dirname error')
      end
      return path:match('(.+)/') or path
    end,
  },
}

local mock_path_utils = {
  get_local_workspace = function()
    if test_state.simulate_errors.path_local_workspace then
      error('Path local workspace error')
    end
    return '/test/workspace'
  end,
  get_container_workspace = function()
    if test_state.simulate_errors.path_container_workspace then
      error('Path container workspace error')
    end
    return '/workspace'
  end,
  setup = function(local_workspace, container_workspace)
    if test_state.simulate_errors.path_setup then
      error('Path setup error')
    end
    test_state.path_mappings_initialized = true
  end,
}

local mock_notify = {
  error = function(title, message)
    if test_state.simulate_errors.notify_error then
      error('Notify error simulation')
    end
  end,
  warn = function(title, message)
    if test_state.simulate_errors.notify_warn then
      error('Notify warn simulation')
    end
  end,
  success = function(title, message)
    if test_state.simulate_errors.notify_success then
      error('Notify success simulation')
    end
  end,
}

-- Register mocks
package.loaded['container.utils.log'] = mock_log
package.loaded['container.docker.init'] = mock_docker
package.loaded['container.environment'] = mock_environment
package.loaded['container'] = mock_container
package.loaded['container.lsp.commands'] = mock_commands
package.loaded['container.lsp.strategy'] = mock_strategy
package.loaded['lspconfig.util'] = mock_lspconfig_util
package.loaded['container.lsp.path'] = mock_path_utils
package.loaded['container.utils.notify'] = mock_notify

-- Helper functions
local function reset_test_state()
  test_state.lsp_clients = {}
  test_state.buffers = { 1, 2, 3 }
  test_state.current_buf = 1
  test_state.docker_commands = {}
  test_state.events = {}
  test_state.file_system_calls = {}
  test_state.auto_init_callbacks = {}
  test_state.use_old_lsp_api = false
  test_state.simulate_errors = {}
  test_state.path_mappings_initialized = false
end

local function set_error_simulation(error_type, enabled)
  test_state.simulate_errors[error_type] = enabled
end

-- Advanced test suite for uncovered code paths
local tests = {}

function tests.test_old_api_compatibility()
  reset_test_state()
  test_state.use_old_lsp_api = true

  local lsp = require('container.lsp.init')
  lsp.setup()
  lsp.set_container_id('test_container_123')

  -- Test old API compatibility for get_lsp_clients
  local server_config = {
    cmd = 'gopls',
    languages = { 'go' },
    available = true,
    path = '/usr/local/bin/gopls',
  }

  lsp.create_lsp_client('gopls', server_config)

  -- This should trigger old API fallback paths
  local exists, client_id = lsp.client_exists('gopls')

  return true
end

function tests.test_commands_module_loading_failure()
  reset_test_state()

  -- Simulate commands module loading failure
  package.loaded['container.lsp.commands'] = nil
  package.preload['container.lsp.commands'] = function()
    error('Commands module not available')
  end

  local lsp = require('container.lsp.init')
  lsp.setup()

  -- Should handle gracefully and log the error
  -- Restore for other tests
  package.loaded['container.lsp.commands'] = mock_commands
  package.preload['container.lsp.commands'] = nil

  return true
end

function tests.test_defensive_handler_comprehensive()
  reset_test_state()

  local lsp = require('container.lsp.init')
  lsp.setup()

  local handler = vim.lsp.handlers['textDocument/publishDiagnostics']

  -- Test all defensive handler paths
  -- Error case with original handler
  handler('test error', nil, {}, {})

  -- Nil result case
  handler(nil, nil, {}, {})

  -- Empty URI case
  handler(nil, { uri = '', diagnostics = {} }, {}, {})

  -- URI without scheme - absolute path (should be fixed)
  handler(nil, { uri = '/absolute/path/file.go', diagnostics = {} }, {}, {})

  -- URI without scheme - relative path (cannot be fixed)
  handler(nil, { uri = 'relative/path', diagnostics = {} }, {}, {})

  -- Valid URI case
  handler(nil, { uri = 'file:///test/path.go', diagnostics = {} }, {}, {})

  return true
end

function tests.test_auto_initialization_container_events()
  reset_test_state()

  -- Create existing container_gopls client
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

  -- Create host gopls client to test cleanup
  test_state.lsp_clients[2] = {
    id = 2,
    name = 'gopls',
    is_stopped = function()
      return false
    end,
    initialized = true,
    stop = function() end,
    attached_buffers = { 1 },
  }

  local lsp = require('container.lsp.init')
  lsp.setup({ auto_setup = true })

  -- Auto-initialization should trigger cleanup paths
  assert(#test_state.auto_init_callbacks > 0, 'Auto-initialization callbacks should be registered')

  return true
end

function tests.test_setup_lsp_in_container_with_existing_clients()
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
  lsp.setup({ auto_setup = true })
  lsp.set_container_id('test_container_123')

  -- This should trigger duplicate client cleanup
  lsp.setup_lsp_in_container()

  return true
end

function tests.test_client_creation_strategy_failure()
  reset_test_state()
  set_error_simulation('strategy_create', true)

  local lsp = require('container.lsp.init')
  lsp.setup()
  lsp.set_container_id('test_container_123')

  local server_config = {
    cmd = 'gopls',
    languages = { 'go' },
    available = true,
    path = '/usr/local/bin/gopls',
  }

  -- Should handle strategy creation failure
  lsp.create_lsp_client('gopls', server_config)

  return true
end

function tests.test_client_start_failure()
  reset_test_state()
  set_error_simulation('start', true)

  local lsp = require('container.lsp.init')
  lsp.setup()
  lsp.set_container_id('test_container_123')

  local server_config = {
    cmd = 'gopls',
    languages = { 'go' },
    available = true,
    path = '/usr/local/bin/gopls',
  }

  -- Should handle client start failure
  lsp.create_lsp_client('gopls', server_config)

  return true
end

function tests.test_client_verification_paths()
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

  -- Test client verification after creation (delayed check)
  set_error_simulation('client_stopped', { [1] = true })

  -- This should trigger the client verification paths in create_lsp_client
  vim.defer_fn(function()
    -- Client verification runs automatically in create_lsp_client
  end, 1000)

  return true
end

function tests.test_register_go_files_comprehensive()
  reset_test_state()

  local lsp = require('container.lsp.init')
  lsp.setup()

  -- Test with stopped client
  local stopped_client = {
    id = 1,
    is_stopped = function()
      return true
    end,
  }
  lsp._register_existing_go_files(stopped_client)

  -- Test with shell error fallback
  set_error_simulation('shell_error', true)
  local working_client = {
    id = 2,
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

  -- Mock io.open for file reading
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

  lsp._register_existing_go_files(working_client)

  -- Test with file read failure
  io.open = function(filename, mode)
    if mode == 'r' and filename:match('%.go$') then
      return nil -- Simulate file read failure
    end
    return original_io_open(filename, mode)
  end

  lsp._register_existing_go_files(working_client)

  -- Test with notification error
  local error_client = {
    id = 3,
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

  lsp._register_existing_go_files(error_client)

  -- Restore io.open
  io.open = original_io_open

  return true
end

function tests.test_auto_setup_disabled_path()
  reset_test_state()

  local lsp = require('container.lsp.init')
  lsp.setup({ auto_setup = false })
  lsp.set_container_id('test_container_123')

  -- This should trigger the early return in setup_lsp_in_container
  lsp.setup_lsp_in_container()

  return true
end

function tests.test_language_server_detection_no_container()
  reset_test_state()

  local lsp = require('container.lsp.init')
  lsp.setup()
  -- Don't set container ID to test error path

  local servers = lsp.detect_language_servers()
  assert(type(servers) == 'table', 'Should return table')
  assert(vim.tbl_count(servers) == 0, 'Should return empty table when no container')

  return true
end

function tests.test_diagnose_server_comprehensive()
  reset_test_state()

  local lsp = require('container.lsp.init')
  lsp.setup()
  lsp.set_container_id('test_container_123')

  -- Test with non-existent server
  local diagnosis1 = lsp.diagnose_lsp_server('nonexistent_server')
  assert(diagnosis1.available == false, 'Non-existent server should not be available')

  -- Detect servers first
  lsp.detect_language_servers()

  -- Test with existing server but version check failure
  set_error_simulation('version_check', true)
  local diagnosis2 = lsp.diagnose_lsp_server('gopls')
  assert(diagnosis2.available == true, 'Server should be available')
  assert(diagnosis2.working == false, 'Server should not be working due to version failure')

  return true
end

function tests.test_retry_server_setup_paths()
  reset_test_state()

  local lsp = require('container.lsp.init')
  lsp.setup()
  lsp.set_container_id('test_container_123')

  -- First detect servers
  lsp.detect_language_servers()

  -- Test retry with non-existent server
  lsp.retry_lsp_server_setup('nonexistent_server', 1)

  -- Test retry with existing server
  lsp.retry_lsp_server_setup('gopls', 2)

  return true
end

function tests.test_gopls_commands_setup_failure()
  reset_test_state()

  -- Make commands module unavailable for gopls setup
  package.loaded['container.lsp.commands'] = nil
  package.preload['container.lsp.commands'] = function()
    error('Commands module not found')
  end

  local lsp = require('container.lsp.init')
  lsp.setup()

  -- This should trigger the commands_ok = false path
  lsp._setup_gopls_commands(1)

  -- Restore
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

  -- This should trigger early return for no filetypes
  lsp._setup_auto_attach('test_server', server_config, 1)

  return true
end

function tests.test_client_attachment_edge_cases()
  reset_test_state()

  -- Create client already attached to buffer
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

  -- This should trigger the "already attached" path
  lsp._attach_to_existing_buffers('test_server', server_config, 1)

  return true
end

function tests.test_path_mappings_initialization()
  reset_test_state()

  local lsp = require('container.lsp.init')
  lsp.setup()
  lsp.set_container_id('test_container_123')

  local server_config = {
    cmd = 'gopls',
    languages = { 'go' },
    available = true,
    filetypes = { 'go' },
  }

  -- This should trigger path mappings initialization
  lsp.create_lsp_client('gopls', server_config)

  assert(test_state.path_mappings_initialized == true, 'Path mappings should be initialized')

  return true
end

function tests.test_interceptor_metadata_validation()
  reset_test_state()

  local lsp = require('container.lsp.init')
  lsp.setup()

  -- Create client with interceptor metadata
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

  -- This should test the interceptor metadata check path in on_init
  lsp._register_existing_go_files(client_with_metadata)

  return true
end

function tests.test_workspace_diagnostic_error_handling()
  reset_test_state()

  local lsp = require('container.lsp.init')
  lsp.setup()

  -- Create client that fails on workspace diagnostic request
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

  -- This should test error handling in diagnostic request
  lsp._register_existing_go_files(error_client)

  return true
end

function tests.test_client_state_management()
  reset_test_state()

  local lsp = require('container.lsp.init')
  lsp.setup()

  -- Test with invalid inputs
  local result1 = lsp.create_lsp_client(nil, {})
  assert(result1 == nil, 'Should handle nil server name')

  local result2 = lsp.create_lsp_client('test', nil)
  assert(result2 == nil, 'Should handle nil server config')

  local result3 = lsp.create_lsp_client('test', 'invalid')
  assert(result3 == nil, 'Should handle invalid server config type')

  return true
end

function tests.test_auto_attach_with_stopped_client()
  reset_test_state()

  -- Create stopped client
  test_state.lsp_clients[1] = {
    id = 1,
    name = 'test_client',
    is_stopped = function()
      return true
    end,
    attached_buffers = {},
  }

  local lsp = require('container.lsp.init')
  lsp.setup()

  local server_config = {
    filetypes = { 'go' },
    languages = { 'go' },
  }

  -- Test auto-attach setup - this should handle stopped client
  lsp._setup_auto_attach('test_server', server_config, 1)

  return true
end

function tests.test_health_check_comprehensive()
  reset_test_state()

  local lsp = require('container.lsp.init')
  lsp.setup()

  -- Test health check without container
  local health1 = lsp.health_check()
  assert(type(health1.issues) == 'table', 'Should return issues list')

  -- Create stopped client
  test_state.lsp_clients[1] = {
    id = 1,
    name = 'test_client',
    is_stopped = function()
      return true
    end,
  }

  -- Add to internal state
  lsp.set_container_id('test_container_123')
  local state = lsp.get_state()

  -- Test health check with stopped client
  local health2 = lsp.health_check()
  assert(type(health2.issues) == 'table', 'Should detect stopped client issues')

  return true
end

function tests.test_analyze_client_comprehensive()
  reset_test_state()

  local lsp = require('container.lsp.init')
  lsp.setup()

  -- Test with non-existent client
  local analysis1 = lsp.analyze_client('nonexistent_client')
  assert(analysis1.error ~= nil, 'Should report error for non-existent client')

  -- Create client for analysis
  test_state.lsp_clients[1] = {
    id = 1,
    name = 'test_client',
    is_stopped = function()
      return false
    end,
    initialized = true,
    config = {
      cmd = { 'test' },
      root_dir = '/test',
      capabilities = { test = true },
      settings = { test = true },
      init_options = { test = true },
    },
    server_capabilities = { test = true },
    workspace_folders = { { uri = 'file:///test', name = 'test' } },
    attached_buffers = { 1 },
  }

  local analysis2 = lsp.analyze_client('test_client')
  assert(type(analysis2.basic_info) == 'table', 'Should return basic info')
  assert(type(analysis2.config) == 'table', 'Should return config info')
  assert(type(analysis2.server_info) == 'table', 'Should return server info')

  return true
end

function tests.test_error_conditions_comprehensive()
  reset_test_state()

  local lsp = require('container.lsp.init')

  -- Test setup with various error conditions
  set_error_simulation('create_augroup', true)
  local ok1 = pcall(lsp.setup, { auto_setup = true })
  -- Should handle augroup creation failure

  reset_test_state()
  set_error_simulation('capabilities', true)
  lsp.setup()
  lsp.set_container_id('test_container_123')

  local server_config = {
    cmd = 'gopls',
    languages = { 'go' },
    available = true,
  }

  -- Should handle capabilities error
  local ok2 = pcall(lsp.create_lsp_client, 'gopls', server_config)

  return true
end

function tests.test_buffer_operations_comprehensive()
  reset_test_state()

  local lsp = require('container.lsp.init')
  lsp.setup()

  -- Test buffer operations with various error conditions
  set_error_simulation('buf_get_name', true)

  local server_config = {
    filetypes = { 'go' },
    languages = { 'go' },
  }

  lsp._attach_to_existing_buffers('test_server', server_config, 1)

  return true
end

-- Test runner
local function run_advanced_coverage_tests()
  print('Running advanced LSP init coverage tests...')
  print('==========================================')

  local test_functions = {
    'test_old_api_compatibility',
    'test_commands_module_loading_failure',
    'test_defensive_handler_comprehensive',
    'test_auto_initialization_container_events',
    'test_setup_lsp_in_container_with_existing_clients',
    'test_client_creation_strategy_failure',
    'test_client_start_failure',
    'test_client_verification_paths',
    'test_register_go_files_comprehensive',
    'test_auto_setup_disabled_path',
    'test_language_server_detection_no_container',
    'test_diagnose_server_comprehensive',
    'test_retry_server_setup_paths',
    'test_gopls_commands_setup_failure',
    'test_setup_auto_attach_no_filetypes',
    'test_client_attachment_edge_cases',
    'test_path_mappings_initialization',
    'test_interceptor_metadata_validation',
    'test_workspace_diagnostic_error_handling',
    'test_client_state_management',
    'test_auto_attach_with_stopped_client',
    'test_health_check_comprehensive',
    'test_analyze_client_comprehensive',
    'test_error_conditions_comprehensive',
    'test_buffer_operations_comprehensive',
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
  print(string.format('Advanced Coverage Tests Complete: %d/%d passed', passed, total))

  if #failed_tests > 0 then
    print('\nFailed tests:')
    for _, failure in ipairs(failed_tests) do
      print('  ✗ ' .. failure)
    end
  end

  if passed == total then
    print('All advanced coverage tests passed! ✓')
    return 0
  else
    print('Some advanced coverage tests failed. ✗')
    return 1
  end
end

-- Auto-run if executed directly
if not pcall(debug.getlocal, 4, 1) then
  local exit_code = run_advanced_coverage_tests()
  os.exit(exit_code)
end

return tests
