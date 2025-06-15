#!/usr/bin/env lua

-- Test script for LspInfo integration
-- This script tests if our LSP clients show up in :LspInfo

package.path = './lua/?.lua;./lua/?/init.lua;' .. package.path

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

package.loaded['devcontainer.utils.log'] = mock_log

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

package.loaded['devcontainer.lsp.forwarding'] = mock_forwarding

print('Testing LspInfo integration...')
print()

-- Load and test the LSP module
local lsp_module = require('devcontainer.lsp.init')

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
