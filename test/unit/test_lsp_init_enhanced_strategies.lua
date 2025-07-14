#!/usr/bin/env lua

-- Enhanced strategy and client lifecycle tests for container.lsp.init
-- Focuses on improving test coverage for strategy selection and client management

-- Add project lua directory to package path
package.path = './lua/?.lua;./lua/?/init.lua;../lua/?.lua;../lua/?/init.lua;' .. package.path

-- Test state for strategy testing
local strategy_test_state = {
  lsp_clients = {},
  strategies = {},
  clients_created = {},
  docker_commands = {},
  events = {},
  current_buf = 1,
  buffers = { 1, 2, 3 },
  strategy_calls = {},
  path_transformations = {},
  workspace_operations = {},
  client_id_counter = 0,
}

-- Mock vim with enhanced strategy support
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
    tempname = function()
      return '/tmp/test_' .. math.random(10000)
    end,
    shellescape = function(str)
      return "'" .. str .. "'"
    end,
    system = function(cmd)
      table.insert(strategy_test_state.docker_commands, cmd)
      if cmd:match('find.*%.go') then
        return '/test/workspace/main.go\n/test/workspace/utils.go\n'
      elseif cmd:match('docker.*version') then
        return 'Docker version 20.10.8'
      end
      return ''
    end,
    mkdir = function(path, flags)
      return true
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
          },
        }
      end,
    },
    get_clients = function(opts)
      opts = opts or {}
      local clients = {}
      for _, client in ipairs(strategy_test_state.lsp_clients) do
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
      strategy_test_state.client_id_counter = strategy_test_state.client_id_counter + 1
      local client_id = strategy_test_state.client_id_counter

      -- Record client creation details
      table.insert(strategy_test_state.clients_created, {
        id = client_id,
        name = config.name,
        config = config,
        strategy_info = config._strategy_info,
      })

      local client = {
        id = client_id,
        name = config.name or 'test_client',
        config = config,
        initialized = false,
        is_stopped = function()
          return strategy_test_state.client_stopped and strategy_test_state.client_stopped[client_id] or false
        end,
        stop = function()
          strategy_test_state.client_stopped = strategy_test_state.client_stopped or {}
          strategy_test_state.client_stopped[client_id] = true
        end,
        notify = function(method, params)
          table.insert(strategy_test_state.workspace_operations, {
            type = 'notify',
            method = method,
            params = params,
            client_id = client_id,
          })
        end,
        request = function(method, params, callback)
          table.insert(strategy_test_state.workspace_operations, {
            type = 'request',
            method = method,
            params = params,
            client_id = client_id,
          })
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

      strategy_test_state.lsp_clients[client_id] = client

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
      return strategy_test_state.lsp_clients[id]
    end,
    buf_attach_client = function(bufnr, client_id)
      local client = strategy_test_state.lsp_clients[client_id]
      if client then
        client.attached_buffers = client.attached_buffers or {}
        table.insert(client.attached_buffers, bufnr)
      end
    end,
    buf_detach_client = function(bufnr, client_id)
      local client = strategy_test_state.lsp_clients[client_id]
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
      table.insert(strategy_test_state.events, { events = events, opts = opts })
      return math.random(1000)
    end,
    nvim_get_current_buf = function()
      return strategy_test_state.current_buf
    end,
    nvim_list_bufs = function()
      return strategy_test_state.buffers
    end,
    nvim_buf_is_loaded = function(buf)
      return vim.tbl_contains(strategy_test_state.buffers, buf)
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

-- Mock io operations for file registration tests
local original_io_open = io.open
io.open = function(filename, mode)
  if mode == 'r' and filename:match('%.go$') then
    return {
      read = function(self, format)
        return 'package main\n\nimport "fmt"\n\nfunc main() {\n  fmt.Println("Hello, World!")\n}\n'
      end,
      close = function(self) end,
    }
  end
  return original_io_open and original_io_open(filename, mode) or nil
end

-- Mock modules with enhanced strategy support
local mock_log = {
  debug = function(...) end,
  info = function(...) end,
  warn = function(...) end,
  error = function(...) end,
}

local mock_docker = {
  run_docker_command = function(args)
    table.insert(strategy_test_state.docker_commands, table.concat(args, ' '))

    -- Mock successful which commands for known servers
    if vim.tbl_contains(args, 'which') then
      local cmd = args[#args]
      if vim.tbl_contains({ 'gopls', 'lua-language-server', 'pylsp', 'rust-analyzer' }, cmd) then
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
        features = { gopls = true },
        customizations = { vscode = { extensions = { 'golang.go' } } },
      },
    }
  end,
}

local mock_commands = {
  setup = function(config) end,
  setup_commands = function() end,
  setup_keybindings = function(opts)
    table.insert(strategy_test_state.workspace_operations, {
      type = 'keybinding_setup',
      opts = opts,
    })
    return true
  end,
}

-- Enhanced mock strategy module
local mock_strategy = {
  setup = function()
    table.insert(strategy_test_state.strategy_calls, { action = 'setup' })
  end,
  select_strategy = function(name, container_id, server_config)
    local strategy_call = {
      action = 'select_strategy',
      name = name,
      container_id = container_id,
      server_config = server_config,
    }
    table.insert(strategy_test_state.strategy_calls, strategy_call)

    -- Return different strategies based on server
    if name == 'gopls' then
      return 'intercept', { port = 9090, transform_paths = true }
    elseif name == 'rust_analyzer' then
      return 'forward', { port = 9091 }
    else
      return 'direct', {}
    end
  end,
  create_client_with_strategy = function(strategy, name, container_id, server_config, strategy_config)
    local create_call = {
      action = 'create_client_with_strategy',
      strategy = strategy,
      name = name,
      container_id = container_id,
      server_config = server_config,
      strategy_config = strategy_config,
    }
    table.insert(strategy_test_state.strategy_calls, create_call)

    -- Simulate different strategy behaviors
    local config = {
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
      _strategy_info = {
        strategy = strategy,
        config = strategy_config,
      },
    }

    -- Add strategy-specific configurations
    if strategy == 'intercept' then
      config.before_init = function(params, config)
        table.insert(strategy_test_state.path_transformations, {
          action = 'before_init',
          strategy = 'intercept',
          params = params,
        })
      end
      config.on_init = function(client, result)
        table.insert(strategy_test_state.path_transformations, {
          action = 'on_init',
          strategy = 'intercept',
          client_id = client.id,
        })
      end
      config.on_attach = function(client, bufnr)
        table.insert(strategy_test_state.path_transformations, {
          action = 'on_attach',
          strategy = 'intercept',
          client_id = client.id,
          bufnr = bufnr,
        })
      end
    elseif strategy == 'forward' then
      config.cmd = { 'nc', 'localhost', strategy_config.port }
    end

    return config, nil
  end,
  setup_path_transformation = function(client, name, container_id)
    table.insert(strategy_test_state.strategy_calls, {
      action = 'setup_path_transformation',
      client_id = client.id,
      name = name,
      container_id = container_id,
    })

    -- Simulate path transformation setup
    table.insert(strategy_test_state.path_transformations, {
      action = 'setup_transformation',
      client_id = client.id,
      name = name,
      container_id = container_id,
    })
  end,
}

local mock_lspconfig_util = {
  root_pattern = function(...)
    local patterns = { ... }
    return function(fname)
      for _, pattern in ipairs(patterns) do
        if pattern == 'go.mod' then
          return '/test/workspace'
        elseif pattern == 'Cargo.toml' then
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

local mock_path = {
  setup = function(host_workspace, container_workspace)
    table.insert(strategy_test_state.path_transformations, {
      action = 'path_setup',
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
local function reset_strategy_test_state()
  strategy_test_state = {
    lsp_clients = {},
    strategies = {},
    clients_created = {},
    docker_commands = {},
    events = {},
    current_buf = 1,
    buffers = { 1, 2, 3 },
    strategy_calls = {},
    path_transformations = {},
    workspace_operations = {},
    client_id_counter = 0,
    client_stopped = {},
  }
end

-- Strategy-focused tests
local strategy_tests = {}

function strategy_tests.test_strategy_selector_initialization()
  reset_strategy_test_state()

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

  -- Verify strategy module was called
  local setup_found = false
  local select_found = false
  local create_found = false

  for _, call in ipairs(strategy_test_state.strategy_calls) do
    if call.action == 'setup' then
      setup_found = true
    elseif call.action == 'select_strategy' then
      select_found = true
      assert(call.name == 'gopls', 'Strategy selection should be called for gopls')
      assert(call.container_id == 'test_container_123', 'Container ID should be passed')
    elseif call.action == 'create_client_with_strategy' then
      create_found = true
      assert(call.strategy == 'intercept', 'Should select intercept strategy for gopls')
    end
  end

  assert(setup_found, 'Strategy setup should be called')
  assert(select_found, 'Strategy selection should be called')
  assert(create_found, 'Client creation with strategy should be called')

  return true
end

function strategy_tests.test_different_strategy_types()
  reset_strategy_test_state()

  local lsp = require('container.lsp.init')
  lsp.setup()
  lsp.set_container_id('test_container_123')

  -- Test with different servers to get different strategies
  local server_configs = {
    gopls = {
      cmd = 'gopls',
      languages = { 'go' },
      available = true,
    },
    rust_analyzer = {
      cmd = 'rust-analyzer',
      languages = { 'rust' },
      available = true,
    },
    pylsp = {
      cmd = 'pylsp',
      languages = { 'python' },
      available = true,
    },
  }

  for name, config in pairs(server_configs) do
    lsp.create_lsp_client(name, config)
  end

  -- Verify different strategies were selected
  local strategies_used = {}
  for _, call in ipairs(strategy_test_state.strategy_calls) do
    if call.action == 'create_client_with_strategy' then
      strategies_used[call.name] = call.strategy
    end
  end

  assert(strategies_used.gopls == 'intercept', 'gopls should use intercept strategy')
  assert(strategies_used.rust_analyzer == 'forward', 'rust_analyzer should use forward strategy')
  assert(strategies_used.pylsp == 'direct', 'pylsp should use direct strategy')

  return true
end

function strategy_tests.test_path_transformation_integration()
  reset_strategy_test_state()

  local lsp = require('container.lsp.init')
  lsp.setup()
  lsp.set_container_id('test_container_123')

  local server_config = {
    cmd = 'gopls',
    languages = { 'go' },
    available = true,
  }

  lsp.create_lsp_client('gopls', server_config)

  -- Verify path transformation was set up
  local transformation_setup_found = false
  local path_setup_found = false

  for _, call in ipairs(strategy_test_state.strategy_calls) do
    if call.action == 'setup_path_transformation' then
      transformation_setup_found = true
      assert(call.name == 'gopls', 'Path transformation should be set up for gopls')
    end
  end

  for _, op in ipairs(strategy_test_state.path_transformations) do
    if op.action == 'path_setup' then
      path_setup_found = true
      assert(op.host_workspace == '/test/workspace', 'Host workspace should be set')
      assert(op.container_workspace == '/workspace', 'Container workspace should be set')
    end
  end

  assert(transformation_setup_found, 'Path transformation setup should be called')
  assert(path_setup_found, 'Path module setup should be called')

  return true
end

function strategy_tests.test_workspace_folder_initialization()
  reset_strategy_test_state()

  local lsp = require('container.lsp.init')
  lsp.setup()
  lsp.set_container_id('test_container_123')

  local server_config = {
    cmd = 'gopls',
    languages = { 'go' },
    available = true,
  }

  lsp.create_lsp_client('gopls', server_config)

  -- Verify client was created with proper workspace folders
  local client_found = false
  for _, client_info in ipairs(strategy_test_state.clients_created) do
    if client_info.name == 'container_gopls' then
      client_found = true
      assert(client_info.config.workspace_folders ~= nil, 'Client should have workspace folders')
      assert(type(client_info.config.workspace_folders) == 'table', 'Workspace folders should be a table')

      if #client_info.config.workspace_folders > 0 then
        local folder = client_info.config.workspace_folders[1]
        assert(folder.uri ~= nil, 'Workspace folder should have URI')
        assert(folder.name ~= nil, 'Workspace folder should have name')
      end
    end
  end

  assert(client_found, 'Container gopls client should be created')

  return true
end

function strategy_tests.test_client_lifecycle_callbacks()
  reset_strategy_test_state()

  local lsp = require('container.lsp.init')
  lsp.setup()
  lsp.set_container_id('test_container_123')

  local server_config = {
    cmd = 'gopls',
    languages = { 'go' },
    available = true,
  }

  lsp.create_lsp_client('gopls', server_config)

  -- Get the created client
  local clients = vim.lsp.get_clients({ name = 'container_gopls' })
  assert(#clients > 0, 'Client should be created')

  local client = clients[1]

  -- Simulate lifecycle callbacks
  if client.config.before_init then
    client.config.before_init({
      workspaceFolders = {
        { uri = 'file:///test/workspace', name = 'workspace' },
      },
      rootUri = 'file:///test/workspace',
    }, client.config)
  end

  if client.config.on_init then
    client.config.on_init(client, { capabilities = {} })
  end

  if client.config.on_attach then
    client.config.on_attach(client, 1)
  end

  -- Verify callbacks were executed
  local before_init_found = false
  local on_init_found = false
  local on_attach_found = false

  for _, op in ipairs(strategy_test_state.path_transformations) do
    if op.action == 'before_init' and op.strategy == 'intercept' then
      before_init_found = true
    elseif op.action == 'on_init' and op.strategy == 'intercept' then
      on_init_found = true
    elseif op.action == 'on_attach' and op.strategy == 'intercept' then
      on_attach_found = true
    end
  end

  assert(before_init_found, 'before_init callback should be executed')
  assert(on_init_found, 'on_init callback should be executed')
  assert(on_attach_found, 'on_attach callback should be executed')

  return true
end

function strategy_tests.test_file_registration_workflow()
  reset_strategy_test_state()

  local lsp = require('container.lsp.init')
  lsp.setup()
  lsp.set_container_id('test_container_123')

  -- Create a mock client for file registration
  local mock_client = {
    id = 1,
    is_stopped = function()
      return false
    end,
    initialized = true,
    notify = function(method, params)
      table.insert(strategy_test_state.workspace_operations, {
        type = 'notify',
        method = method,
        params = params,
        client_id = 1,
      })
    end,
    request = function(method, params, callback)
      table.insert(strategy_test_state.workspace_operations, {
        type = 'request',
        method = method,
        params = params,
        client_id = 1,
      })
      if callback then
        callback(nil, {})
      end
    end,
  }

  -- Test file registration
  lsp._register_existing_go_files(mock_client)

  -- Verify didOpen notifications were sent
  local didopen_found = false
  local workspace_diagnostic_found = false

  for _, op in ipairs(strategy_test_state.workspace_operations) do
    if op.type == 'notify' and op.method == 'textDocument/didOpen' then
      didopen_found = true
      assert(op.params.textDocument.languageId == 'go', 'Language ID should be go')
      assert(op.params.textDocument.uri ~= nil, 'URI should be provided')
    elseif op.type == 'request' and op.method == 'workspace/diagnostic' then
      workspace_diagnostic_found = true
    end
  end

  assert(didopen_found, 'didOpen notifications should be sent')
  assert(workspace_diagnostic_found, 'Workspace diagnostic request should be sent')

  return true
end

function strategy_tests.test_server_diagnosis_capabilities()
  reset_strategy_test_state()

  local lsp = require('container.lsp.init')
  lsp.setup()
  lsp.set_container_id('test_container_123')

  -- First detect servers
  local servers = lsp.detect_language_servers()

  -- Test diagnosis of available server
  local diagnosis = lsp.diagnose_lsp_server('gopls')
  assert(type(diagnosis) == 'table', 'Diagnosis should return table')
  assert(diagnosis.available == true, 'gopls should be available')
  assert(diagnosis.working == true, 'gopls should be working')
  assert(type(diagnosis.details) == 'table', 'Diagnosis should include details')

  -- Test diagnosis of non-existent server
  local bad_diagnosis = lsp.diagnose_lsp_server('nonexistent_server')
  assert(bad_diagnosis.available == false, 'Non-existent server should not be available')
  assert(type(bad_diagnosis.error) == 'string', 'Should provide error message')
  assert(type(bad_diagnosis.suggestions) == 'table', 'Should provide suggestions')

  return true
end

function strategy_tests.test_lsp_error_recovery()
  reset_strategy_test_state()

  local lsp = require('container.lsp.init')
  lsp.setup()
  lsp.set_container_id('test_container_123')

  -- Create some clients first
  lsp.detect_language_servers()
  lsp.setup_lsp_in_container()

  -- Test recovery process
  lsp.recover_all_lsp_servers()

  -- Verify recovery was initiated (the function should not crash)
  assert(true, 'Recovery process should complete without errors')

  return true
end

function strategy_tests.test_client_health_monitoring()
  reset_strategy_test_state()

  local lsp = require('container.lsp.init')
  lsp.setup()
  lsp.set_container_id('test_container_123')

  -- Create a client
  local server_config = {
    cmd = 'gopls',
    languages = { 'go' },
    available = true,
  }

  lsp.create_lsp_client('gopls', server_config)

  -- Check health
  local health = lsp.health_check()
  assert(type(health) == 'table', 'Health check should return table')
  assert(health.container_connected == true, 'Should report container connected')
  assert(health.servers_detected >= 0, 'Should report servers detected count')
  assert(health.clients_active >= 0, 'Should report clients active count')
  assert(type(health.issues) == 'table', 'Should return issues list')

  return true
end

function strategy_tests.test_client_analysis_detailed()
  reset_strategy_test_state()

  local lsp = require('container.lsp.init')
  lsp.setup()
  lsp.set_container_id('test_container_123')

  local server_config = {
    cmd = 'gopls',
    languages = { 'go' },
    available = true,
  }

  lsp.create_lsp_client('gopls', server_config)

  -- Get client and analyze it
  local clients = vim.lsp.get_clients({ name = 'container_gopls' })
  if #clients > 0 then
    local analysis = lsp.analyze_client('container_gopls')
    assert(type(analysis) == 'table', 'Analysis should return table')
    assert(analysis.basic_info ~= nil, 'Should include basic info')
    assert(analysis.config ~= nil, 'Should include config info')
    assert(analysis.server_info ~= nil, 'Should include server info')
    assert(analysis.buffer_attachment ~= nil, 'Should include buffer attachment info')
  end

  return true
end

function strategy_tests.test_container_init_status_management()
  reset_strategy_test_state()

  local lsp = require('container.lsp.init')
  lsp.setup({ auto_setup = true })

  -- Test clearing initialization status
  lsp.clear_container_init_status('test_container_123')

  -- The function should execute without errors
  assert(true, 'Clear container init status should complete')

  return true
end

function strategy_tests.test_debug_info_collection()
  reset_strategy_test_state()

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

  -- Collect debug info
  local debug_info = lsp.get_debug_info()
  assert(type(debug_info) == 'table', 'Debug info should return table')
  assert(debug_info.config ~= nil, 'Should include config')
  assert(debug_info.state ~= nil, 'Should include state')
  assert(debug_info.container_id == 'test_container_123', 'Should include correct container ID')
  assert(type(debug_info.active_clients) == 'table', 'Should include active clients')
  assert(type(debug_info.current_buffer_clients) == 'table', 'Should include buffer clients')

  -- Verify client info structure
  for _, client_info in ipairs(debug_info.active_clients) do
    assert(client_info.id ~= nil, 'Client info should include ID')
    assert(client_info.name ~= nil, 'Client info should include name')
    assert(type(client_info.is_stopped) == 'boolean', 'Client info should include stopped status')
    assert(type(client_info.initialized) == 'boolean', 'Client info should include initialized status')
  end

  return true
end

function strategy_tests.test_multiple_server_detection()
  reset_strategy_test_state()

  local lsp = require('container.lsp.init')
  lsp.setup()
  lsp.set_container_id('test_container_123')

  local servers = lsp.detect_language_servers()
  assert(type(servers) == 'table', 'Should return servers table')

  -- Verify multiple servers can be detected
  local expected_servers = { 'gopls', 'lua_ls', 'pylsp' }
  for _, server_name in ipairs(expected_servers) do
    if servers[server_name] then
      assert(servers[server_name].available == true, server_name .. ' should be available')
      assert(type(servers[server_name].languages) == 'table', server_name .. ' should have languages')
      assert(servers[server_name].cmd ~= nil, server_name .. ' should have command')
    end
  end

  return true
end

function strategy_tests.test_compatibility_helpers()
  reset_strategy_test_state()

  local lsp = require('container.lsp.init')
  lsp.setup()

  -- Test that LSP compatibility helpers are working
  -- These functions are called internally during client operations

  local clients = vim.lsp.get_clients()
  assert(type(clients) == 'table', 'get_clients should work')

  -- Test start functions (already tested indirectly through create_lsp_client)
  -- but verify they don't crash
  local test_config = {
    name = 'test_client',
    cmd = { 'echo', 'test' },
    filetypes = { 'test' },
  }

  local client_id = vim.lsp.start(test_config)
  assert(client_id ~= nil, 'LSP start should return client ID')

  return true
end

-- Test runner
local function run_strategy_tests()
  print('Running LSP init strategy and lifecycle tests...')
  print('================================================')

  local test_functions = {
    'test_strategy_selector_initialization',
    'test_different_strategy_types',
    'test_path_transformation_integration',
    'test_workspace_folder_initialization',
    'test_client_lifecycle_callbacks',
    'test_file_registration_workflow',
    'test_server_diagnosis_capabilities',
    'test_lsp_error_recovery',
    'test_client_health_monitoring',
    'test_client_analysis_detailed',
    'test_container_init_status_management',
    'test_debug_info_collection',
    'test_multiple_server_detection',
    'test_compatibility_helpers',
  }

  local passed = 0
  local total = #test_functions
  local failed_tests = {}

  for _, test_name in ipairs(test_functions) do
    print('\nRunning: ' .. test_name)

    local ok, result = pcall(strategy_tests[test_name])

    if ok and result then
      print('✓ PASSED: ' .. test_name)
      passed = passed + 1
    else
      local error_msg = result and tostring(result) or 'Unknown error'
      print('✗ FAILED: ' .. test_name .. ' - ' .. error_msg)
      table.insert(failed_tests, test_name .. ': ' .. error_msg)
    end
  end

  print('\n================================================')
  print(string.format('LSP Strategy Tests Complete: %d/%d passed', passed, total))

  if #failed_tests > 0 then
    print('\nFailed tests:')
    for _, failure in ipairs(failed_tests) do
      print('  ✗ ' .. failure)
    end
  end

  if passed == total then
    print('All LSP strategy tests passed! ✓')
    return 0
  else
    print('Some LSP strategy tests failed. ✗')
    return 1
  end
end

-- Auto-run if executed directly
if not pcall(debug.getlocal, 4, 1) then
  local exit_code = run_strategy_tests()
  os.exit(exit_code)
end

return strategy_tests
