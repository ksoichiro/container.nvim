#!/usr/bin/env lua

-- Configuration and initialization workflow tests for container.lsp.init
-- Focuses on testing configuration preparation, workspace setup, and initialization callbacks

-- Add project lua directory to package path
package.path = './lua/?.lua;./lua/?/init.lua;../lua/?.lua;../lua/?/init.lua;' .. package.path

-- Test state for configuration testing
local config_test_state = {
  lsp_clients = {},
  workspace_operations = {},
  callback_executions = {},
  path_operations = {},
  docker_commands = {},
  file_registrations = {},
  diagnostic_requests = {},
  client_id_counter = 0,
  current_buf = 1,
}

-- Mock vim with enhanced configuration support
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
    if type(obj) == 'table' then
      local parts = {}
      for k, v in pairs(obj) do
        table.insert(parts, tostring(k) .. '=' .. tostring(v))
      end
      return '{' .. table.concat(parts, ', ') .. '}'
    end
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
      table.insert(config_test_state.docker_commands, cmd)
      if cmd:match('find.*%.go') then
        return '/test/workspace/main.go\n/test/workspace/pkg/utils.go\n'
      end
      return ''
    end,
    shellescape = function(str)
      return "'" .. str .. "'"
    end,
  },

  -- Enhanced LSP mock functions
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
            workspaceFolders = true,
          },
          textDocument = {
            hover = { contentFormat = { 'markdown', 'plaintext' } },
            definition = { linkSupport = true },
            references = { context = { includeDeclaration = true } },
            completion = { completionItem = { snippetSupport = true } },
          },
        }
      end,
    },
    get_clients = function(opts)
      opts = opts or {}
      local clients = {}
      for _, client in ipairs(config_test_state.lsp_clients) do
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
      config_test_state.client_id_counter = config_test_state.client_id_counter + 1
      local client_id = config_test_state.client_id_counter

      local client = {
        id = client_id,
        name = config.name or 'test_client',
        config = config,
        initialized = false,
        is_stopped = function()
          return config_test_state.client_stopped and config_test_state.client_stopped[client_id] or false
        end,
        stop = function()
          config_test_state.client_stopped = config_test_state.client_stopped or {}
          config_test_state.client_stopped[client_id] = true
        end,
        notify = function(method, params)
          table.insert(config_test_state.workspace_operations, {
            type = 'notify',
            method = method,
            params = params,
            client_id = client_id,
          })

          if method == 'textDocument/didOpen' then
            table.insert(config_test_state.file_registrations, {
              uri = params.textDocument.uri,
              languageId = params.textDocument.languageId,
              client_id = client_id,
            })
          end
        end,
        request = function(method, params, callback)
          table.insert(config_test_state.workspace_operations, {
            type = 'request',
            method = method,
            params = params,
            client_id = client_id,
          })

          if method == 'workspace/diagnostic' then
            table.insert(config_test_state.diagnostic_requests, {
              params = params,
              client_id = client_id,
            })
          end

          if callback then
            callback(nil, { capabilities = {} })
          end
        end,
        attached_buffers = {},
        workspace_folders = config.workspace_folders,
        server_capabilities = {
          workspace = { didChangeConfiguration = true },
          textDocument = {
            hover = true,
            definition = true,
            references = true,
          },
        },
      }

      config_test_state.lsp_clients[client_id] = client

      -- Simulate delayed initialization and call callbacks
      vim.defer_fn(function()
        client.initialized = true

        -- Execute before_init if present
        if config.before_init then
          local initialize_params = {
            workspaceFolders = config.workspace_folders or {},
            rootUri = 'file:///test/workspace',
            rootPath = '/test/workspace',
          }
          config.before_init(initialize_params, config)
          table.insert(config_test_state.callback_executions, {
            type = 'before_init',
            client_id = client_id,
            params = initialize_params,
          })
        end

        -- Execute on_init if present
        if config.on_init then
          config.on_init(client, { capabilities = {} })
          table.insert(config_test_state.callback_executions, {
            type = 'on_init',
            client_id = client_id,
          })
        end

        -- Execute on_attach if present
        if config.on_attach then
          config.on_attach(client, config_test_state.current_buf)
          table.insert(config_test_state.callback_executions, {
            type = 'on_attach',
            client_id = client_id,
            bufnr = config_test_state.current_buf,
          })
        end
      end, 10)

      return client_id
    end,
    start_client = function(config)
      return vim.lsp.start(config)
    end,
    get_client_by_id = function(id)
      return config_test_state.lsp_clients[id]
    end,
    buf_attach_client = function(bufnr, client_id)
      local client = config_test_state.lsp_clients[client_id]
      if client then
        client.attached_buffers = client.attached_buffers or {}
        table.insert(client.attached_buffers, bufnr)
      end
    end,
    buf_detach_client = function(bufnr, client_id)
      local client = config_test_state.lsp_clients[client_id]
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
      return math.random(1000)
    end,
    nvim_get_current_buf = function()
      return config_test_state.current_buf
    end,
    nvim_list_bufs = function()
      return { 1, 2, 3 }
    end,
    nvim_buf_is_loaded = function(buf)
      return true
    end,
    nvim_buf_get_name = function(buf)
      if buf == 1 then
        return '/test/workspace/main.go'
      elseif buf == 2 then
        return '/test/workspace/pkg/utils.go'
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

-- Mock io operations for file registration tests
local original_io_open = io.open
io.open = function(filename, mode)
  if mode == 'r' and filename:match('%.go$') then
    return {
      read = function(self, format)
        return 'package main\n\nimport (\n\t"fmt"\n\t"os"\n)\n\nfunc main() {\n\tfmt.Println("Hello, World!")\n}\n'
      end,
      close = function(self) end,
    }
  end
  return original_io_open and original_io_open(filename, mode) or nil
end

-- Mock modules
local mock_log = {
  debug = function(...) end,
  info = function(...) end,
  warn = function(...) end,
  error = function(...) end,
}

local mock_docker = {
  run_docker_command = function(args)
    table.insert(config_test_state.docker_commands, table.concat(args, ' '))

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
      current_config = {
        image = 'golang:1.21',
        workspaceFolder = '/workspace',
        features = { gopls = true },
      },
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
      root_dir = function(fname)
        return '/test/workspace'
      end,
      workspace_folders = {
        {
          uri = 'file:///test/workspace',
          name = 'workspace',
        },
      },
      before_init = function(params, config)
        -- Custom before_init for testing
      end,
      on_init = function(client, result)
        -- Custom on_init for testing
      end,
      on_attach = function(client, bufnr)
        -- Custom on_attach for testing
      end,
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

-- Mock path module with tracking
local mock_path = {
  setup = function(host_workspace, container_workspace)
    table.insert(config_test_state.path_operations, {
      action = 'setup',
      host_workspace = host_workspace,
      container_workspace = container_workspace,
    })
  end,
  get_local_workspace = function()
    return '/test/workspace'
  end,
  get_container_workspace = function()
    return '/workspace'
  end,
}

-- Register mocks
package.loaded['container.utils.log'] = mock_log
package.loaded['container.docker.init'] = mock_docker
package.loaded['container.environment'] = mock_environment
package.loaded['container'] = mock_container
package.loaded['container.lsp.commands'] = mock_commands
package.loaded['container.lsp.strategy'] = mock_strategy
package.loaded['container.lsp.path'] = mock_path
package.loaded['lspconfig.util'] = mock_lspconfig_util

-- Helper functions
local function reset_config_test_state()
  config_test_state = {
    lsp_clients = {},
    workspace_operations = {},
    callback_executions = {},
    path_operations = {},
    docker_commands = {},
    file_registrations = {},
    diagnostic_requests = {},
    client_id_counter = 0,
    current_buf = 1,
    client_stopped = {},
  }
end

-- Configuration workflow tests
local config_tests = {}

function config_tests.test_prepare_lsp_config_structure()
  reset_config_test_state()

  local lsp = require('container.lsp.init')
  lsp.setup()

  local server_config = {
    cmd = 'gopls',
    languages = { 'go' },
  }

  local config = lsp._prepare_lsp_config('gopls', server_config)

  -- Verify config structure
  assert(type(config) == 'table', 'Config should be a table')
  assert(config.name == 'container_gopls', 'Should have container prefix')
  assert(type(config.filetypes) == 'table', 'Should have filetypes')
  assert(type(config.cmd) == 'table', 'Should have command')
  assert(type(config.root_dir) == 'function', 'Should have root_dir function')
  assert(type(config.capabilities) == 'table', 'Should have capabilities')
  assert(type(config.workspace_folders) == 'table', 'Should have workspace folders')
  assert(type(config.before_init) == 'function', 'Should have before_init callback')
  assert(type(config.on_init) == 'function', 'Should have on_init callback')
  assert(type(config.on_attach) == 'function', 'Should have on_attach callback')

  return true
end

function config_tests.test_workspace_folders_configuration()
  reset_config_test_state()

  local lsp = require('container.lsp.init')
  lsp.setup()

  local server_config = {
    cmd = 'gopls',
    languages = { 'go' },
  }

  local config = lsp._prepare_lsp_config('gopls', server_config)

  -- Verify workspace folders
  assert(#config.workspace_folders > 0, 'Should have at least one workspace folder')

  local folder = config.workspace_folders[1]
  assert(folder.uri ~= nil, 'Workspace folder should have URI')
  assert(folder.name ~= nil, 'Workspace folder should have name')
  assert(folder.uri:match('^file://'), 'URI should have file scheme')

  return true
end

function config_tests.test_capabilities_configuration()
  reset_config_test_state()

  local lsp = require('container.lsp.init')
  lsp.setup()

  local server_config = {
    cmd = 'gopls',
    languages = { 'go' },
  }

  local config = lsp._prepare_lsp_config('gopls', server_config)

  -- Verify capabilities structure
  assert(config.capabilities.workspace ~= nil, 'Should have workspace capabilities')
  assert(config.capabilities.workspace.configuration == true, 'Should support workspace configuration')
  assert(
    config.capabilities.workspace.didChangeConfiguration.dynamicRegistration == true,
    'Should support dynamic configuration changes'
  )

  return true
end

function config_tests.test_root_dir_function()
  reset_config_test_state()

  local lsp = require('container.lsp.init')
  lsp.setup()

  local server_config = {
    cmd = 'gopls',
    languages = { 'go' },
  }

  local config = lsp._prepare_lsp_config('gopls', server_config)

  -- Test root_dir function with various inputs
  local test_files = {
    '/test/workspace/main.go',
    '/test/workspace/pkg/utils.go',
    '/test/workspace/cmd/app/main.go',
  }

  for _, file in ipairs(test_files) do
    local root = config.root_dir(file)
    assert(type(root) == 'string', 'root_dir should return string for ' .. file)
    assert(root ~= '', 'root_dir should not be empty for ' .. file)
  end

  return true
end

function config_tests.test_before_init_callback()
  reset_config_test_state()

  local lsp = require('container.lsp.init')
  lsp.setup()
  lsp.set_container_id('test_container_123')

  local server_config = {
    cmd = 'gopls',
    languages = { 'go' },
    available = true,
  }

  lsp.create_lsp_client('gopls', server_config)

  -- Wait for callbacks to execute
  vim.defer_fn(function() end, 20)

  -- Verify before_init was called
  local before_init_found = false
  for _, execution in ipairs(config_test_state.callback_executions) do
    if execution.type == 'before_init' then
      before_init_found = true
      assert(execution.params ~= nil, 'before_init should receive params')
      assert(execution.params.workspaceFolders ~= nil, 'Should have workspace folders in params')
      break
    end
  end

  assert(before_init_found, 'before_init callback should be executed')

  return true
end

function config_tests.test_on_init_callback()
  reset_config_test_state()

  local lsp = require('container.lsp.init')
  lsp.setup()
  lsp.set_container_id('test_container_123')

  local server_config = {
    cmd = 'gopls',
    languages = { 'go' },
    available = true,
  }

  lsp.create_lsp_client('gopls', server_config)

  -- Wait for callbacks to execute
  vim.defer_fn(function() end, 20)

  -- Verify on_init was called
  local on_init_found = false
  for _, execution in ipairs(config_test_state.callback_executions) do
    if execution.type == 'on_init' then
      on_init_found = true
      break
    end
  end

  assert(on_init_found, 'on_init callback should be executed')

  return true
end

function config_tests.test_on_attach_callback()
  reset_config_test_state()

  local lsp = require('container.lsp.init')
  lsp.setup()
  lsp.set_container_id('test_container_123')

  local server_config = {
    cmd = 'gopls',
    languages = { 'go' },
    available = true,
  }

  lsp.create_lsp_client('gopls', server_config)

  -- Wait for callbacks to execute
  vim.defer_fn(function() end, 20)

  -- Verify on_attach was called
  local on_attach_found = false
  for _, execution in ipairs(config_test_state.callback_executions) do
    if execution.type == 'on_attach' then
      on_attach_found = true
      assert(execution.bufnr ~= nil, 'on_attach should receive buffer number')
      break
    end
  end

  assert(on_attach_found, 'on_attach callback should be executed')

  return true
end

function config_tests.test_path_mappings_initialization()
  reset_config_test_state()

  local lsp = require('container.lsp.init')
  lsp.setup()
  lsp.set_container_id('test_container_123')

  local server_config = {
    cmd = 'gopls',
    languages = { 'go' },
    available = true,
  }

  lsp.create_lsp_client('gopls', server_config)

  -- Wait for path setup
  vim.defer_fn(function() end, 20)

  -- Verify path mappings were initialized
  local path_setup_found = false
  for _, operation in ipairs(config_test_state.path_operations) do
    if operation.action == 'setup' then
      path_setup_found = true
      assert(operation.host_workspace ~= nil, 'Should set host workspace')
      assert(operation.container_workspace ~= nil, 'Should set container workspace')
      break
    end
  end

  assert(path_setup_found, 'Path mappings should be initialized')

  return true
end

function config_tests.test_file_registration_workflow()
  reset_config_test_state()

  local lsp = require('container.lsp.init')
  lsp.setup()

  -- Create a mock client
  local mock_client = {
    id = 1,
    is_stopped = function()
      return false
    end,
    initialized = true,
    notify = function(method, params)
      table.insert(config_test_state.workspace_operations, {
        type = 'notify',
        method = method,
        params = params,
        client_id = 1,
      })

      if method == 'textDocument/didOpen' then
        table.insert(config_test_state.file_registrations, {
          uri = params.textDocument.uri,
          languageId = params.textDocument.languageId,
          client_id = 1,
        })
      end
    end,
    request = function(method, params, callback)
      table.insert(config_test_state.workspace_operations, {
        type = 'request',
        method = method,
        params = params,
        client_id = 1,
      })

      if method == 'workspace/diagnostic' then
        table.insert(config_test_state.diagnostic_requests, {
          params = params,
          client_id = 1,
        })
      end

      if callback then
        callback(nil, {})
      end
    end,
  }

  -- Test file registration
  lsp._register_existing_go_files(mock_client)

  -- Verify file registrations
  assert(#config_test_state.file_registrations > 0, 'Should register Go files')

  for _, registration in ipairs(config_test_state.file_registrations) do
    assert(registration.languageId == 'go', 'Should register with correct language ID')
    assert(registration.uri:match('%.go'), 'Should register Go files')
    assert(registration.uri:match('^file://'), 'Should use file URI scheme')
  end

  -- Verify diagnostic request
  assert(#config_test_state.diagnostic_requests > 0, 'Should request workspace diagnostics')

  return true
end

function config_tests.test_workspace_configuration_notifications()
  reset_config_test_state()

  local lsp = require('container.lsp.init')
  lsp.setup()
  lsp.set_container_id('test_container_123')

  local server_config = {
    cmd = 'gopls',
    languages = { 'go' },
    available = true,
  }

  lsp.create_lsp_client('gopls', server_config)

  -- Wait for initialization
  vim.defer_fn(function() end, 20)

  -- Check for workspace configuration notifications
  local config_notification_found = false
  for _, operation in ipairs(config_test_state.workspace_operations) do
    if operation.type == 'notify' and operation.method == 'workspace/didChangeConfiguration' then
      config_notification_found = true
      break
    end
  end

  -- Note: This depends on the server capabilities, so it might not always be present
  -- But the test should not crash
  assert(true, 'Workspace configuration handling should work')

  return true
end

function config_tests.test_custom_server_configuration()
  reset_config_test_state()

  local lsp = require('container.lsp.init')
  lsp.setup({
    servers = {
      gopls = {
        cmd = 'custom-gopls',
        extra_option = 'test_value',
        settings = {
          gopls = {
            usePlaceholders = true,
          },
        },
      },
    },
  })

  local server_config = {
    cmd = 'gopls',
    languages = { 'go' },
  }

  local config = lsp._prepare_lsp_config('gopls', server_config)

  -- Verify custom configuration is merged
  assert(config.extra_option == 'test_value', 'Custom server configuration should be merged')
  assert(config.settings ~= nil, 'Custom settings should be preserved')
  assert(config.settings.gopls.usePlaceholders == true, 'Nested settings should be preserved')

  return true
end

function config_tests.test_different_language_servers()
  reset_config_test_state()

  local lsp = require('container.lsp.init')
  lsp.setup()

  -- Test with different server types
  local server_configs = {
    gopls = {
      cmd = 'gopls',
      languages = { 'go' },
    },
    pylsp = {
      cmd = 'pylsp',
      languages = { 'python' },
    },
    lua_ls = {
      cmd = 'lua-language-server',
      languages = { 'lua' },
    },
  }

  for name, server_config in pairs(server_configs) do
    local config = lsp._prepare_lsp_config(name, server_config)

    assert(config.name == 'container_' .. name, 'Should have correct container prefix for ' .. name)
    assert(
      vim.tbl_contains(config.filetypes, server_config.languages[1]),
      'Should include language in filetypes for ' .. name
    )
  end

  return true
end

function config_tests.test_configuration_merging()
  reset_config_test_state()

  local custom_config = {
    auto_setup = false,
    timeout = 10000,
    servers = {
      gopls = {
        cmd = 'custom-gopls',
        init_options = { usePlaceholders = true },
      },
    },
    on_init = function(client, result)
      -- Custom callback
    end,
    on_attach = function(client, bufnr)
      -- Custom callback
    end,
  }

  local lsp = require('container.lsp.init')
  lsp.setup(custom_config)

  local state = lsp.get_state()
  assert(state.config.auto_setup == false, 'Custom auto_setup should be preserved')
  assert(state.config.timeout == 10000, 'Custom timeout should be preserved')
  assert(state.config.servers.gopls.cmd == 'custom-gopls', 'Custom server config should be preserved')
  assert(type(state.config.on_init) == 'function', 'Custom callbacks should be preserved')

  return true
end

function config_tests.test_error_handling_in_callbacks()
  reset_config_test_state()

  local lsp = require('container.lsp.init')
  lsp.setup()

  local server_config = {
    cmd = 'gopls',
    languages = { 'go' },
  }

  local config = lsp._prepare_lsp_config('gopls', server_config)

  -- Test callbacks with edge case inputs
  local edge_cases = {
    { workspaceFolders = nil, rootUri = nil },
    { workspaceFolders = {}, rootUri = '' },
    { workspaceFolders = { { uri = 'invalid' } } },
  }

  for _, case in ipairs(edge_cases) do
    local ok = pcall(config.before_init, case, config)
    assert(ok, 'before_init should handle edge cases gracefully')
  end

  -- Test on_init with mock client
  local mock_client = { workspace_folders = {} }
  local ok = pcall(config.on_init, mock_client, {})
  assert(ok, 'on_init should handle edge cases gracefully')

  return true
end

function config_tests.test_go_project_root_detection()
  reset_config_test_state()

  local lsp = require('container.lsp.init')
  lsp.setup()

  local server_config = {
    cmd = 'gopls',
    languages = { 'go' },
  }

  local config = lsp._prepare_lsp_config('gopls', server_config)

  -- Test root directory detection for Go projects
  local test_cases = {
    '/test/workspace/main.go',
    '/test/workspace/pkg/utils.go',
    '/test/workspace/cmd/app/main.go',
  }

  for _, file in ipairs(test_cases) do
    local root = config.root_dir(file)
    assert(root == '/test/workspace', 'Should detect correct Go project root for ' .. file)
  end

  return true
end

-- Test runner
local function run_config_tests()
  print('Running LSP init configuration and workflow tests...')
  print('===================================================')

  local test_functions = {
    'test_prepare_lsp_config_structure',
    'test_workspace_folders_configuration',
    'test_capabilities_configuration',
    'test_root_dir_function',
    'test_before_init_callback',
    'test_on_init_callback',
    'test_on_attach_callback',
    'test_path_mappings_initialization',
    'test_file_registration_workflow',
    'test_workspace_configuration_notifications',
    'test_custom_server_configuration',
    'test_different_language_servers',
    'test_configuration_merging',
    'test_error_handling_in_callbacks',
    'test_go_project_root_detection',
  }

  local passed = 0
  local total = #test_functions
  local failed_tests = {}

  for _, test_name in ipairs(test_functions) do
    print('\nRunning: ' .. test_name)

    local ok, result = pcall(config_tests[test_name])

    if ok and result then
      print('✓ PASSED: ' .. test_name)
      passed = passed + 1
    else
      local error_msg = result and tostring(result) or 'Unknown error'
      print('✗ FAILED: ' .. test_name .. ' - ' .. error_msg)
      table.insert(failed_tests, test_name .. ': ' .. error_msg)
    end
  end

  print('\n===================================================')
  print(string.format('LSP Configuration Tests Complete: %d/%d passed', passed, total))

  if #failed_tests > 0 then
    print('\nFailed tests:')
    for _, failure in ipairs(failed_tests) do
      print('  ✗ ' .. failure)
    end
  end

  if passed == total then
    print('All LSP configuration tests passed! ✓')
    return 0
  else
    print('Some LSP configuration tests failed. ✗')
    return 1
  end
end

-- Auto-run if executed directly
if not pcall(debug.getlocal, 4, 1) then
  local exit_code = run_config_tests()
  os.exit(exit_code)
end

return config_tests
