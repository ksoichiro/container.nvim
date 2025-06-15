#!/usr/bin/env lua

-- Basic test script for devcontainer.nvim
-- This tests core functionality without requiring a full Neovim session

-- Mock vim global for testing
_G.vim = {
  tbl_contains = function(t, value)
    for _, v in ipairs(t) do
      if v == value then return true end
    end
    return false
  end,
  split = function(str, sep)
    local result = {}
    for match in (str .. sep):gmatch("(.-)" .. sep) do
      table.insert(result, match)
    end
    return result
  end,
  startswith = function(str, prefix)
    return str:sub(1, #prefix) == prefix
  end,
  tbl_deep_extend = function(behavior, ...)
    local result = {}
    local sources = {...}
    for _, source in ipairs(sources) do
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
    for k, _ in pairs(t) do
      table.insert(keys, k)
    end
    return keys
  end,
  fn = {
    getcwd = function() return "/test/workspace" end,
    shellescape = function(str) return "'" .. str .. "'" end,
    system = function(cmd) return "" end,
    sha256 = function(str) return "abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234" end,
    fnamemodify = function(path, mod)
      if mod == ':p' then return path end
      if mod == ':h' then return vim.split(path, '/')[1] or path end
      return path
    end
  },
  v = { shell_error = 0 },
  loop = {
    new_tcp = function()
      return {
        bind = function(self, addr, port) return true end,
        close = function(self) end
      }
    end
  },
  notify = function(msg, level) print("[NOTIFY]", msg) end,
  log = { levels = { INFO = 1, ERROR = 2 } }
}

local function test_module_loading()
  print("=== Module Loading Test ===")

  -- Test if modules can be loaded
  local modules = {
    'devcontainer.config',
    'devcontainer.parser',
    'devcontainer.utils.log',
    'devcontainer.utils.fs',
    'devcontainer.lsp.init',
    'devcontainer.lsp.path',
    'devcontainer.lsp.forwarding',
  }

  for _, module_name in ipairs(modules) do
    local success, module = pcall(require, module_name)
    if success then
      print("✓ " .. module_name .. " loaded successfully")
    else
      print("✗ " .. module_name .. " failed to load: " .. module)
      return false
    end
  end

  return true
end

local function test_path_conversion()
  print("\n=== Path Conversion Test ===")

  local path_module = require('devcontainer.lsp.path')

  -- Setup test paths
  path_module.setup('/test/workspace', '/workspace', {})

  -- Test local to container conversion
  local test_cases = {
    ['/test/workspace/main.py'] = '/workspace/main.py',
    ['/test/workspace/src/utils.py'] = '/workspace/src/utils.py',
    ['/other/file.py'] = '/other/file.py', -- Outside workspace
  }

  for local_path, expected_container in pairs(test_cases) do
    local container_path = path_module.to_container_path(local_path)
    if container_path == expected_container then
      print("✓ " .. local_path .. " -> " .. container_path)
    else
      print("✗ " .. local_path .. " -> " .. (container_path or "nil") .. " (expected: " .. expected_container .. ")")
      return false
    end
  end

  -- Test container to local conversion
  for expected_local, container_path in pairs(test_cases) do
    if container_path:match('^/workspace') then
      local local_path = path_module.to_local_path(container_path)
      if local_path == expected_local then
        print("✓ " .. container_path .. " -> " .. local_path)
      else
        print("✗ " .. container_path .. " -> " .. (local_path or "nil") .. " (expected: " .. expected_local .. ")")
        return false
      end
    end
  end

  return true
end

local function test_config_loading()
  print("\n=== Configuration Test ===")

  local config = require('devcontainer.config')

  -- Test default configuration
  local success, result = config.setup()
  if not success then
    print("✗ Failed to load default configuration")
    return false
  end

  print("✓ Default configuration loaded")

  -- Test custom configuration
  local custom_config = {
    log_level = 'debug',
    lsp = {
      auto_setup = false,
      timeout = 10000,
    }
  }

  success, result = config.setup(custom_config)
  if not success then
    print("✗ Failed to load custom configuration")
    return false
  end

  print("✓ Custom configuration loaded")

  -- Verify configuration values
  local current_config = config.get()
  if current_config.log_level == 'debug' and current_config.lsp.timeout == 10000 then
    print("✓ Configuration values correctly set")
  else
    print("✗ Configuration values not set correctly")
    return false
  end

  return true
end

local function test_server_detection()
  print("\n=== Server Detection Test ===")

  local lsp = require('devcontainer.lsp.init')

  -- Setup with test config
  lsp.setup({
    auto_setup = false,
    servers = {
      lua_ls = { cmd = 'lua-language-server' },
      pylsp = { cmd = 'pylsp' },
    }
  })

  -- Test server detection logic (without actual container)
  print("✓ LSP module initialized")

  -- Test get_state
  local state = lsp.get_state()
  if state and state.config then
    print("✓ LSP state accessible")
  else
    print("✗ LSP state not accessible")
    return false
  end

  return true
end

-- Main test runner
local function run_tests()
  print("Starting devcontainer.nvim basic tests...\n")

  local tests = {
    test_module_loading,
    test_config_loading,
    test_path_conversion,
    test_server_detection,
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

-- Add parent directory to package path
package.path = './lua/?.lua;' .. package.path

-- Run tests
local exit_code = run_tests()
os.exit(exit_code)
