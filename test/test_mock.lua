#!/usr/bin/env lua

-- Mock vim globals for testing outside Neovim
_G.vim = {
  log = { levels = { DEBUG = 0, INFO = 1, WARN = 2, ERROR = 3 } },
  tbl_contains = function(t, value)
    for _, v in ipairs(t) do
      if v == value then return true end
    end
    return false
  end,
  tbl_deep_extend = function(behavior, ...)
    local result = {}
    local sources = {...}

    local function deep_extend(target, source)
      for k, v in pairs(source) do
        if type(v) == 'table' and type(target[k]) == 'table' then
          deep_extend(target[k], v)
        else
          target[k] = v
        end
      end
    end

    for _, source in ipairs(sources) do
      deep_extend(result, source)
    end
    return result
  end,
  split = function(str, sep)
    local result = {}
    local regex = ("([^%s]+)"):format(sep)
    for each in str:gmatch(regex) do
      table.insert(result, each)
    end
    return result
  end,
  inspect = function(obj)
    return tostring(obj)
  end,
  fn = {
    fnamemodify = function(path, modifier)
      if modifier == ':p' then
        return path:match('^/') and path or ('/' .. path)
      end
      return path
    end,
    getcwd = function()
      return '/test/workspace'
    end,
    expand = function(path)
      return path:gsub('%%:p', '/test/file.lua')
    end
  },
  startswith = function(str, prefix)
    return str:sub(1, #prefix) == prefix
  end,
  uri_to_fname = function(uri)
    return uri:gsub('^file://', '')
  end,
  uri_from_fname = function(fname)
    return 'file://' .. fname
  end,
  deepcopy = function(t)
    if type(t) ~= 'table' then return t end
    local copy = {}
    for k, v in pairs(t) do
      copy[k] = vim.deepcopy(v)
    end
    return copy
  end,
  loop = {
    new_pipe = function() return {} end,
    new_tcp = function() return {
      bind = function() return true end,
      close = function() end
    } end,
    spawn = function() return {}, 12345 end
  },
  lsp = {
    protocol = {
      make_client_capabilities = function()
        return {}
      end
    },
    handlers = {},
    rpc = {
      connect = function(host, port)
        return { host = host, port = port }
      end
    },
    get_active_clients = function()
      return {}
    end
  }
}

-- Add parent directory to package path
package.path = '../lua/?.lua;' .. package.path

-- Simple test for path conversion
local function test_path_conversion_simple()
  print("=== Simple Path Conversion Test ===")

  local path_module = require('devcontainer.lsp.path')

  -- Setup test paths
  path_module.setup('/test/workspace', '/workspace', {})

  -- Test basic conversion
  local local_path = '/test/workspace/main.py'
  local container_path = path_module.to_container_path(local_path)
  local back_to_local = path_module.to_local_path(container_path)

  print("Local path: " .. local_path)
  print("Container path: " .. (container_path or "nil"))
  print("Back to local: " .. (back_to_local or "nil"))

  if container_path == '/workspace/main.py' and back_to_local == local_path then
    print("✓ Path conversion working correctly")
    return true
  else
    print("✗ Path conversion failed")
    return false
  end
end

local function test_config_basic()
  print("\n=== Basic Configuration Test ===")

  local config = require('devcontainer.config')

  -- Test if we can access defaults
  if config.defaults and config.defaults.lsp then
    print("✓ Default configuration accessible")
    print("  LSP auto_setup: " .. tostring(config.defaults.lsp.auto_setup))
    print("  LSP timeout: " .. tostring(config.defaults.lsp.timeout))
    return true
  else
    print("✗ Default configuration not accessible")
    return false
  end
end

local function test_lsp_module_structure()
  print("\n=== LSP Module Structure Test ===")

  local lsp = require('devcontainer.lsp.init')
  local path = require('devcontainer.lsp.path')
  local forwarding = require('devcontainer.lsp.forwarding')

  -- Check if main functions exist
  local functions_to_check = {
    { lsp, 'setup' },
    { lsp, 'detect_language_servers' },
    { lsp, 'create_lsp_client' },
    { path, 'to_container_path' },
    { path, 'to_local_path' },
    { path, 'transform_uri' },
    { forwarding, 'setup_port_forwarding' },
    { forwarding, 'create_stdio_bridge' },
  }

  for _, check in ipairs(functions_to_check) do
    local module, func_name = check[1], check[2]
    if type(module[func_name]) == 'function' then
      print("✓ " .. func_name .. " function exists")
    else
      print("✗ " .. func_name .. " function missing")
      return false
    end
  end

  return true
end

-- Run tests
local function run_simple_tests()
  print("Running simplified devcontainer.nvim tests...\n")

  local tests = {
    test_config_basic,
    test_path_conversion_simple,
    test_lsp_module_structure,
  }

  local passed = 0
  local total = #tests

  for _, test in ipairs(tests) do
    local success = test()
    if success then
      passed = passed + 1
    end
  end

  print(string.format("\n=== Test Results ==="))
  print(string.format("Passed: %d/%d", passed, total))

  if passed == total then
    print("All tests passed! ✓")
    return 0
  else
    print("Some tests failed! ✗")
    return 1
  end
end

local exit_code = run_simple_tests()
os.exit(exit_code)