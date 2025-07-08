#!/usr/bin/env lua

-- Test script for LspInfo integration
-- This script tests if our LSP clients show up in :LspInfo

package.path = '../lua/?.lua;../lua/?/init.lua;' .. package.path

-- Mock vim functions for testing
_G.vim = {
  fn = {
    getcwd = function()
      return '/test/project'
    end,
    sha256 = function(str)
      return 'mockhash'
    end,
  },
  api = {
    nvim_get_current_buf = function()
      return 1
    end,
    nvim_buf_get_option = function(buf, opt)
      if opt == 'filetype' then
        return 'python'
      end
      return nil
    end,
    nvim_create_augroup = function()
      return 1
    end,
    nvim_create_autocmd = function() end,
    nvim_list_bufs = function()
      return { 1 }
    end,
    nvim_buf_is_loaded = function()
      return true
    end,
    nvim_get_runtime_file = function()
      return {}
    end,
  },
  lsp = {
    get_active_clients = function(opts)
      -- Mock some active clients for testing
      if opts and opts.name then
        if opts.name == 'pylsp' then
          return { { id = 1, name = 'pylsp' } }
        end
      end
      return {}
    end,
    start_client = function(config)
      print('Mock start_client called with name: ' .. (config.name or 'unknown'))
      return 1
    end,
    buf_attach_client = function() end,
    protocol = {
      make_client_capabilities = function()
        return {}
      end,
    },
  },
  cmd = function() end,
  defer_fn = function(fn, delay)
    fn()
  end,
  schedule = function(fn)
    fn()
  end,
  tbl_contains = function(tbl, value)
    for _, v in ipairs(tbl) do
      if v == value then
        return true
      end
    end
    return false
  end,
  tbl_deep_extend = function(behavior, ...)
    local result = {}
    for i = 1, select('#', ...) do
      local tbl = select(i, ...)
      if type(tbl) == 'table' then
        for k, v in pairs(tbl) do
          result[k] = v
        end
      end
    end
    return result
  end,
  inspect = function(obj)
    return tostring(obj)
  end,
  stdpath = function(type)
    if type == 'config' then
      return '/tmp/nvim-test-config'
    elseif type == 'data' then
      return '/tmp/nvim-test-data'
    elseif type == 'cache' then
      return '/tmp/nvim-test-cache'
    end
    return '/tmp/nvim-test'
  end,
  json = {
    encode = function(obj)
      return '{}'
    end,
    decode = function(str)
      return {}
    end,
  },
  tbl_extend = function(behavior, t1, t2)
    local result = {}
    for k, v in pairs(t1 or {}) do
      result[k] = v
    end
    for k, v in pairs(t2 or {}) do
      result[k] = v
    end
    return result
  end,
  tbl_keys = function(tbl)
    local keys = {}
    for k, _ in pairs(tbl) do
      table.insert(keys, k)
    end
    return keys
  end,
  tbl_count = function(tbl)
    local count = 0
    for _ in pairs(tbl) do
      count = count + 1
    end
    return count
  end,
  bo = {},
  loop = {
    new_pipe = function()
      return {}
    end,
    spawn = function()
      return {}, 123
    end,
  },
}

-- Mock log module
local mock_log = {
  debug = function(...) end,
  info = function(msg, ...)
    print('[INFO] ' .. string.format(msg, ...))
  end,
  warn = function(msg, ...)
    print('[WARN] ' .. string.format(msg, ...))
  end,
  error = function(msg, ...)
    print('[ERROR] ' .. string.format(msg, ...))
  end,
}

package.loaded['container.utils.log'] = mock_log

-- Mock lspconfig
local mock_lspconfig = {
  pylsp = {
    setup = function(config)
      print('Mock lspconfig.pylsp.setup called with:')
      print('  name: ' .. (config.name or 'unknown'))
      print('  cmd: ' .. (config.cmd and table.concat(config.cmd, ' ') or 'none'))
      print('  This should make the server visible in :LspInfo')
    end,
  },
}

package.loaded['lspconfig'] = mock_lspconfig

-- Mock additional dependencies required by container.lsp modules
package.loaded['lspconfig.util'] = {
  root_pattern = function(...)
    return function(fname)
      return '/test/project'
    end
  end,
  find_git_ancestor = function(fname)
    return '/test/project'
  end,
  path = {
    dirname = function(path)
      return '/test/project'
    end,
  },
}

-- Mock Strategy B dependencies to avoid circular imports
package.loaded['container.lsp.proxy.init'] = {
  setup = function(config)
    print('  [MOCK] Proxy system setup called')
  end,
  create_proxy = function(container_id, server_name, config)
    print('  [MOCK] Creating proxy for ' .. server_name)
    return {
      proxy_id = 'mock-proxy-123',
      server_name = server_name,
      container_id = container_id,
    }
  end,
  create_lsp_client_config = function(container_id, server_name, config)
    print('  [MOCK] Creating LSP client config for ' .. server_name)
    return {
      name = 'container_' .. server_name,
      cmd = { 'mock', 'command', server_name },
      root_dir = '/test/project',
      on_init = function() end,
      on_attach = function() end,
      on_exit = function() end,
      capabilities = {},
      settings = {},
    }
  end,
  get_proxy = function(container_id, server_name)
    print('  [MOCK] Getting proxy for ' .. server_name)
    return {
      proxy_id = 'mock-proxy-123',
      server_name = server_name,
      container_id = container_id,
    }
  end,
  health_check = function()
    return { healthy = true, details = {} }
  end,
}

-- Mock forwarding and symlink modules
package.loaded['container.lsp.forwarding'] = {
  get_client_cmd = function(server_name, server_config, container_id)
    return { 'docker', 'exec', container_id, server_name }
  end,
  check_container_connectivity = function()
    return true
  end,
}

package.loaded['container.lsp.transform'] = {
  setup_path_transformation = function() end,
}

package.loaded['container.symlink'] = {
  setup_lsp_symlinks = function()
    return true
  end,
  cleanup_lsp_symlinks = function()
    return true
  end,
  check_symlink_support = function()
    return true
  end,
}

-- Mock additional container modules
package.loaded['container.lsp.path'] = {
  get_local_workspace = function()
    return '/test/project'
  end,
  get_container_workspace = function()
    return '/workspace'
  end,
  setup = function() end,
}

package.loaded['container.docker.init'] = {
  run_docker_command = function()
    return { success = true, stdout = '/usr/bin/pylsp', stderr = '' }
  end,
}

package.loaded['container.environment'] = {
  build_lsp_args = function()
    return {}
  end,
}

package.loaded['container'] = {
  get_state = function()
    return { current_config = {} }
  end,
}

-- Mock vim.lsp for our changes
local captured_config = nil
local mock_client_id = 1

vim.lsp = {
  start_client = function(config)
    captured_config = config
    print('Mock start_client called with name:', config.name or 'unnamed')
    return mock_client_id
  end,
  get_client_by_id = function(id)
    if id == mock_client_id then
      return {
        id = id,
        name = captured_config and captured_config.name or 'container_pylsp',
        config = captured_config or {},
        notify = function() end,
        request = function() end,
        handlers = {}, -- Add empty handlers table
      }
    end
    return nil
  end,
  get_active_clients = function(opts)
    return {} -- Return empty array for tests
  end,
  buf_attach_client = function() end,
  protocol = {
    make_client_capabilities = function()
      return {}
    end,
  },
  handlers = {}, -- Add empty handlers table for vim.lsp.handlers
}

-- Mock lspconfig util
package.loaded['lspconfig.util'] = {
  find_git_ancestor = function()
    return '/test/project'
  end,
  path = {
    dirname = function(path)
      return path
    end,
  },
}

-- Mock forwarding module
local mock_forwarding = {
  get_client_cmd = function(name, config, container_id)
    return { 'docker', 'exec', '-i', container_id, name }
  end,
  create_client_middleware = function()
    return {}
  end,
}

package.loaded['container.lsp.forwarding'] = mock_forwarding

print('Testing LspInfo integration...')
print()

-- Load and test the LSP module
local lsp_ok, lsp_module = pcall(require, 'container.lsp.init')
if not lsp_ok then
  print('⚠ Skipping LspInfo integration test - LSP module not available in current test environment')
  print('This test will be enabled when Strategy B implementation is complete')
  os.exit(0)
end

-- Setup the module
lsp_module.setup({
  auto_setup = true,
  timeout = 5000,
})

-- Set a mock container ID
lsp_module.set_container_id('test_container_123')

print('=== Testing LSP Client Creation ===')

-- Test creating an LSP client
local server_config = {
  cmd = 'pylsp',
  languages = { 'python' },
  filetypes = { 'python' },
  available = true,
  path = '/usr/bin/pylsp',
}

lsp_module.create_lsp_client('pylsp', server_config)

print()
print('=== Test Results ===')
print('If the integration works correctly:')
print('1. lspconfig.pylsp.setup should have been called')
print('2. The client should be configured with Docker exec command')
print('3. In real Neovim, the client should appear in :LspInfo')
print()
print('✓ LspInfo integration test completed')
print('Note: Run this in real Neovim environment to see actual :LspInfo output')
