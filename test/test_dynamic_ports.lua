#!/usr/bin/env lua

-- Test script for dynamic port allocation functionality
-- This script tests the new dynamic port features

package.path = './lua/?.lua;./lua/?/init.lua;' .. package.path

-- Mock vim functions for testing
_G.vim = {
  fn = {
    getcwd = function() return "/test/project" end,
    sha256 = function(str)
      -- Simple hash function for testing
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
  api = {
    nvim_get_current_buf = function() return 1 end,
    nvim_buf_get_option = function(buf, opt)
      if opt == 'filetype' then return 'python' end
      return nil
    end,
    nvim_create_augroup = function() return 1 end,
    nvim_create_autocmd = function() end,
    nvim_list_bufs = function() return {1} end,
    nvim_buf_is_loaded = function() return true end
  },
  lsp = {
    get_active_clients = function() return {} end,
    start_client = function() return 1 end,
    buf_attach_client = function() end,
    protocol = {
      make_client_capabilities = function() return {} end
    }
  },
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
          -- Mock port availability check
          -- Ports 10000-10005 are "available", others are not
          return port >= 10000 and port <= 10005
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

print("=== Dynamic Port Allocation Tests ===")
print()

-- Test 1: Port Utility Module
print("Test 1: Port Utility Basic Functions")
local port_utils = require('devcontainer.utils.port')

-- Test find_available_port
local available_port = port_utils.find_available_port(10000, 10010)
print("Available port found:", available_port)
assert(available_port >= 10000 and available_port <= 10005, "Available port should be in mocked range")

-- Test port allocation
local project_id = "test-project-12345678"
local allocated = port_utils.allocate_port(available_port, project_id, "test-purpose")
print("Port allocation successful:", allocated)
assert(allocated == true, "Port allocation should succeed")

-- Test getting allocated ports
local allocated_ports = port_utils.get_project_ports(project_id)
print("Allocated ports for project:", vim.inspect(allocated_ports))
assert(next(allocated_ports) ~= nil, "Should have allocated ports")

print("✓ Port utility tests passed")
print()

-- Test 2: Port Specification Parsing
print("Test 2: Port Specification Parsing")

-- Test fixed port
local fixed_spec, err = port_utils.parse_port_spec(3000)
print("Fixed port spec:", vim.inspect(fixed_spec))
assert(fixed_spec.type == "fixed", "Should be fixed type")
assert(fixed_spec.host_port == 3000, "Host port should be 3000")

-- Test auto port
local auto_spec, err = port_utils.parse_port_spec("auto:3001")
print("Auto port spec:", vim.inspect(auto_spec))
assert(auto_spec.type == "auto", "Should be auto type")
assert(auto_spec.container_port == 3001, "Container port should be 3001")

-- Test range port
local range_spec, err = port_utils.parse_port_spec("range:8000-8010:3002")
print("Range port spec:", vim.inspect(range_spec))
assert(range_spec.type == "range", "Should be range type")
assert(range_spec.range_start == 8000, "Range start should be 8000")
assert(range_spec.range_end == 8010, "Range end should be 8010")
assert(range_spec.container_port == 3002, "Container port should be 3002")

print("✓ Port specification parsing tests passed")
print()

-- Test 3: Dynamic Port Resolution
print("Test 3: Dynamic Port Resolution")

local port_specs = {
  3000,              -- fixed
  "auto:3001",       -- auto allocation
  "range:10000-10010:3002", -- range allocation
  "8080:3003"        -- host:container mapping
}

local resolved_ports, errors = port_utils.resolve_dynamic_ports(port_specs, project_id, {
  port_range_start = 10000,
  port_range_end = 10010
})

print("Resolved ports:", vim.inspect(resolved_ports))
if errors then
  print("Resolution errors:", vim.inspect(errors))
end

assert(#resolved_ports >= 3, "Should resolve at least 3 ports")
print("✓ Dynamic port resolution tests passed")
print()

-- Test 4: Parser Integration
print("Test 4: Parser Integration")

-- Mock devcontainer.json content with dynamic ports
local mock_config = {
  name = "test-container",
  image = "ubuntu:latest",
  forwardPorts = {
    3000,
    "auto:3001",
    "range:10000-10005:3002"
  }
}

-- Test parser normalization
local parser = require('devcontainer.parser')
local normalized_ports = parser.normalize_ports(mock_config.forwardPorts)

print("Normalized ports:", vim.inspect(normalized_ports))
assert(#normalized_ports == 3, "Should normalize 3 ports")

-- Check that different types are recognized
local has_fixed = false
local has_auto = false
local has_range = false

for _, port in ipairs(normalized_ports) do
  if port.type == "fixed" then has_fixed = true end
  if port.type == "auto" then has_auto = true end
  if port.type == "range" then has_range = true end
end

assert(has_fixed, "Should have fixed port type")
assert(has_auto, "Should have auto port type")
assert(has_range, "Should have range port type")

print("✓ Parser integration tests passed")
print()

-- Test 5: Project ID Generation
print("Test 5: Project ID Generation")

local project_id_1 = parser.generate_project_id("/test/project1")
local project_id_2 = parser.generate_project_id("/test/project2")

print("Project ID 1:", project_id_1)
print("Project ID 2:", project_id_2)

assert(project_id_1 ~= project_id_2, "Different paths should generate different project IDs")
assert(project_id_1:find("project1"), "Project ID should contain directory name")

print("✓ Project ID generation tests passed")
print()

-- Test 6: Port Statistics
print("Test 6: Port Statistics")

local stats = port_utils.get_port_statistics()
print("Port statistics:", vim.inspect(stats))

assert(stats.total_allocated > 0, "Should have allocated ports")
assert(stats.by_project[project_id] ~= nil, "Should track by project")

print("✓ Port statistics tests passed")
print()

-- Cleanup
print("Test 7: Cleanup")
local released_count = port_utils.release_project_ports(project_id)
print("Released ports count:", released_count)
assert(released_count > 0, "Should release some ports")

local stats_after = port_utils.get_port_statistics()
print("Statistics after cleanup:", vim.inspect(stats_after))

print("✓ Cleanup tests passed")
print()

print("=== All Dynamic Port Tests Completed Successfully! ===")
print()
print("Features tested:")
print("  ✓ Port availability detection")
print("  ✓ Port allocation and tracking")
print("  ✓ Port specification parsing (fixed, auto, range)")
print("  ✓ Dynamic port resolution")
print("  ✓ Parser integration with new port formats")
print("  ✓ Project ID generation for isolation")
print("  ✓ Port statistics and monitoring")
print("  ✓ Cleanup and release functionality")
print()
print("The dynamic port allocation system is working correctly!")
