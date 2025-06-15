#!/usr/bin/env lua

-- Test script for auto port configuration bug
-- This tests the specific case: "forwardPorts": ["auto:8080", "auto:2345"]

package.path = './lua/?.lua;./lua/?/init.lua;' .. package.path

-- Mock vim functions for testing
_G.vim = {
  fn = {
    getcwd = function() return "/test/project" end,
    sha256 = function(str)
      local hash = 0
      for i = 1, #str do
        hash = hash + string.byte(str, i)
      end
      return string.format("%08x", hash % 0xFFFFFFFF)
    end,
    shellescape = function(str) return "'" .. str .. "'" end,
    system = function(cmd) return "mocked system output" end
  },
  v = { shell_error = 0 },
  api = {},
  lsp = {},
  cmd = function() end,
  defer_fn = function(fn, delay) fn() end,
  schedule = function(fn) fn() end,
  tbl_contains = function(tbl, value)
    for _, v in ipairs(tbl) do
      if v == value then return true end
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
  inspect = function(obj) return tostring(obj) end,
  deepcopy = function(orig)
    local copy
    if type(orig) == 'table' then
      copy = {}
      for orig_key, orig_value in pairs(orig) do
        copy[orig_key] = vim.deepcopy(orig_value)
      end
    else
      copy = orig
    end
    return copy
  end,
  loop = {
    new_tcp = function()
      return {
        bind = function(self, host, port)
          return port >= 10000 and port <= 10010
        end,
        close = function() end
      }
    end
  }
}

-- Mock log module
local mock_log = {
  debug = function(...) print("[DEBUG]", ...) end,
  info = function(...) print("[INFO]", ...) end,
  warn = function(...) print("[WARN]", ...) end,
  error = function(...) print("[ERROR]", ...) end
}

package.loaded['devcontainer.utils.log'] = mock_log

-- Mock fs module
local mock_fs = {
  basename = function(path)
    return path:match("([^/]+)$") or path
  end
}

package.loaded['devcontainer.utils.fs'] = mock_fs

print("=== Auto Port Configuration Bug Test ===")
print()

-- Test the problematic configuration
local test_config = {
  name = "Test Container",
  image = "node:18",
  forwardPorts = {"auto:8080", "auto:2345"}
}

print("Testing configuration:")
print(vim.inspect(test_config))
print()

-- Load the parser
local parser = require('devcontainer.parser')

-- Test 1: Port normalization
print("Test 1: Port Normalization")
local normalized_ports = parser.normalize_ports(test_config.forwardPorts)
print("Normalized ports:", vim.inspect(normalized_ports))

-- Check that auto ports don't have host_port initially
for i, port in ipairs(normalized_ports) do
  print(string.format("Port %d: type=%s, container_port=%s, host_port=%s",
    i, port.type, tostring(port.container_port), tostring(port.host_port)))

  if port.type == "auto" then
    if port.host_port ~= nil then
      error("Auto port should not have host_port before resolution")
    end
  end
end

print("✓ Port normalization test passed")
print()

-- Test 2: Validation before resolution
print("Test 2: Validation Before Resolution")

local config_with_normalized = vim.deepcopy(test_config)
config_with_normalized.normalized_ports = normalized_ports

local validation_errors = parser.validate(config_with_normalized)
print("Validation errors before resolution:", vim.inspect(validation_errors))

if #validation_errors > 0 then
  for _, err in ipairs(validation_errors) do
    if err:find("Invalid host port") then
      error("Validation should not fail for auto ports before resolution: " .. err)
    end
  end
end

print("✓ Validation before resolution test passed")
print()

-- Test 3: Port resolution
print("Test 3: Port Resolution")

-- Mock plugin config
local plugin_config = {
  port_forwarding = {
    enable_dynamic_ports = true,
    port_range_start = 10000,
    port_range_end = 10010
  }
}

-- Set up the full config for resolution
config_with_normalized.project_id = "test-project-12345678"

local resolved_config = parser.resolve_dynamic_ports(config_with_normalized, plugin_config)
print("Resolved config:", vim.inspect(resolved_config.normalized_ports))

-- Check that auto ports now have host_port
if resolved_config then
  for i, port in ipairs(resolved_config.normalized_ports) do
    print(string.format("Resolved Port %d: type=%s, container_port=%s, host_port=%s",
      i, port.type, tostring(port.container_port), tostring(port.host_port)))

    if not port.host_port then
      error(string.format("Port %d should have host_port after resolution", i))
    end
  end
else
  error("Port resolution failed")
end

print("✓ Port resolution test passed")
print()

-- Test 4: Validation after resolution
print("Test 4: Validation After Resolution")

local resolved_validation_errors = parser.validate_resolved_ports(resolved_config)
print("Validation errors after resolution:", vim.inspect(resolved_validation_errors))

if #resolved_validation_errors > 0 then
  for _, err in ipairs(resolved_validation_errors) do
    print("Validation error:", err)
  end
  error("Validation should pass after successful port resolution")
end

print("✓ Validation after resolution test passed")
print()

print("=== All Auto Port Configuration Tests Passed! ===")
print()
print("The bug has been fixed:")
print("  ✓ Auto ports don't cause validation errors before resolution")
print("  ✓ Port resolution correctly assigns host_port to auto ports")
print("  ✓ Validation after resolution ensures all ports are properly configured")
print("  ✓ Configuration 'forwardPorts': ['auto:8080', 'auto:2345'] now works correctly")
