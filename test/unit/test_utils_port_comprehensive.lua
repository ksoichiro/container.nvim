-- Comprehensive test suite for lua/container/utils/port.lua
-- Targeting 70%+ test coverage for port management utilities

package.path = './lua/?.lua;./lua/?/init.lua;' .. package.path

-- Initialize test counter
local test_count = 0
local passed_count = 0

local function test(name, func)
  test_count = test_count + 1
  print(string.format('Test %d: %s', test_count, name))

  local success, result = pcall(func)
  if success then
    passed_count = passed_count + 1
    print('✓ ' .. name .. ' passed')
  else
    print('✗ ' .. name .. ' failed: ' .. tostring(result))
  end
  print()
end

-- Mock vim functions for testing
_G.vim = {
  fn = {
    getcwd = function()
      return '/test/project'
    end,
    sha256 = function(str)
      local hash = 0
      for i = 1, #str do
        hash = hash + string.byte(str, i)
      end
      return string.format('%08x', hash % 0xFFFFFFFF)
    end,
    shellescape = function(str)
      return "'" .. str .. "'"
    end,
    system = function(cmd)
      return 'mocked system output'
    end,
  },
  v = { shell_error = 0 },
  api = {
    nvim_get_current_buf = function()
      return 1
    end,
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
    if type(obj) == 'table' then
      local items = {}
      for k, v in pairs(obj) do
        table.insert(items, string.format('%s=%s', tostring(k), tostring(v)))
      end
      return '{' .. table.concat(items, ', ') .. '}'
    end
    return tostring(obj)
  end,
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
          -- Mock port availability:
          -- Ports 10000-10010 are "available"
          -- Ports 20000-20005 are "available"
          -- Others are "unavailable"
          return (port >= 10000 and port <= 10010) or (port >= 20000 and port <= 20005)
        end,
        close = function() end,
      }
    end,
  },
}

-- Mock log module
local mock_log = {
  debug = function(...)
    -- Uncomment for debug output: print('[DEBUG]', ...)
  end,
  info = function(...)
    -- Uncomment for info output: print('[INFO]', ...)
  end,
  warn = function(...)
    print('[WARN]', ...)
  end,
  error = function(...)
    print('[ERROR]', ...)
  end,
}

package.loaded['container.utils.log'] = mock_log

print('=== Comprehensive Port Utility Tests ===')
print()

-- Load the port utility module
local port_utils = require('container.utils.port')

-- Test 1: Module loading and structure
test('Module loading and structure', function()
  assert(type(port_utils) == 'table', 'Module should be a table')

  -- Check that all expected functions exist
  local expected_functions = {
    'find_available_port',
    'allocate_port',
    'release_port',
    'release_project_ports',
    'get_allocated_ports',
    'get_project_ports',
    'is_port_allocated',
    'parse_port_spec',
    'resolve_dynamic_ports',
    'get_port_statistics',
    'validate_port_config',
  }

  for _, func_name in ipairs(expected_functions) do
    assert(type(port_utils[func_name]) == 'function', string.format('Function %s should exist', func_name))
  end
end)

-- Test 2: find_available_port basic functionality
test('find_available_port basic functionality', function()
  -- Test with default range
  local port = port_utils.find_available_port()
  assert(port ~= nil, 'Should find an available port in default range')
  assert(port >= 10000 and port <= 20000, 'Port should be in default range')

  -- Test with custom range
  local custom_port = port_utils.find_available_port(10000, 10005)
  assert(custom_port ~= nil, 'Should find port in custom range')
  assert(custom_port >= 10000 and custom_port <= 10005, 'Port should be in custom range')
end)

-- Test 3: find_available_port with excluded ports
test('find_available_port with excluded ports', function()
  -- First find an available port
  local first_port = port_utils.find_available_port(10000, 10010)
  assert(first_port ~= nil, 'Should find first port')

  -- Find another port excluding the first one
  local second_port = port_utils.find_available_port(10000, 10010, { first_port })
  assert(second_port ~= nil, 'Should find second port')
  assert(second_port ~= first_port, 'Second port should be different from first')
end)

-- Test 4: find_available_port failure case
test('find_available_port failure case', function()
  -- Try to find port in range with no available ports
  local port = port_utils.find_available_port(30000, 30005)
  assert(port == nil, 'Should return nil when no ports available')
end)

-- Test 5: allocate_port functionality
test('allocate_port functionality', function()
  local test_port = 10001
  local project_id = 'test-project-123'
  local purpose = 'web-server'

  -- Allocate a port
  local success = port_utils.allocate_port(test_port, project_id, purpose)
  assert(success == true, 'Port allocation should succeed')

  -- Try to allocate the same port again
  local duplicate = port_utils.allocate_port(test_port, 'other-project', 'other-purpose')
  assert(duplicate == false, 'Duplicate allocation should fail')
end)

-- Test 6: allocate_port with default parameters
test('allocate_port with default parameters', function()
  local test_port = 10002

  -- Allocate with minimal parameters
  local success = port_utils.allocate_port(test_port)
  assert(success == true, 'Port allocation with defaults should succeed')

  -- Verify allocation info
  local allocated_ports = port_utils.get_allocated_ports()
  assert(allocated_ports[test_port] ~= nil, 'Port should be allocated')
  assert(allocated_ports[test_port].project_id == 'unknown', 'Should use default project_id')
  assert(allocated_ports[test_port].purpose == 'generic', 'Should use default purpose')
end)

-- Test 7: release_port functionality
test('release_port functionality', function()
  local test_port = 10003

  -- Allocate then release a port
  port_utils.allocate_port(test_port, 'test-project', 'test-purpose')
  local released = port_utils.release_port(test_port)
  assert(released == true, 'Port release should succeed')

  -- Try to release the same port again
  local duplicate_release = port_utils.release_port(test_port)
  assert(duplicate_release == false, 'Duplicate release should return false')
end)

-- Test 8: release_project_ports functionality
test('release_project_ports functionality', function()
  local project_id = 'multi-port-project'

  -- Allocate multiple ports for the same project
  port_utils.allocate_port(10004, project_id, 'web')
  port_utils.allocate_port(10005, project_id, 'api')
  port_utils.allocate_port(10006, 'other-project', 'database')

  -- Release all ports for the project
  local released_count = port_utils.release_project_ports(project_id)
  assert(released_count == 2, 'Should release 2 ports for the project')

  -- Verify ports are released
  assert(not port_utils.is_port_allocated(10004), 'Port 10004 should be released')
  assert(not port_utils.is_port_allocated(10005), 'Port 10005 should be released')
  assert(port_utils.is_port_allocated(10006), 'Port 10006 should still be allocated')
end)

-- Test 9: get_allocated_ports functionality
test('get_allocated_ports functionality', function()
  -- Clear existing allocations first
  local all_ports = port_utils.get_allocated_ports()
  for port in pairs(all_ports) do
    port_utils.release_port(port)
  end

  -- Allocate some test ports
  port_utils.allocate_port(10007, 'project-a', 'web')
  port_utils.allocate_port(10008, 'project-b', 'api')

  local allocated = port_utils.get_allocated_ports()
  assert(type(allocated) == 'table', 'Should return a table')
  assert(allocated[10007] ~= nil, 'Port 10007 should be allocated')
  assert(allocated[10008] ~= nil, 'Port 10008 should be allocated')
  assert(allocated[10007].project_id == 'project-a', 'Should have correct project_id')
end)

-- Test 10: get_project_ports functionality
test('get_project_ports functionality', function()
  local project_id = 'specific-project'

  -- Allocate ports for different projects
  port_utils.allocate_port(10009, project_id, 'web')
  port_utils.allocate_port(10010, project_id, 'api')
  port_utils.allocate_port(20000, 'other-project', 'db')

  local project_ports = port_utils.get_project_ports(project_id)
  assert(type(project_ports) == 'table', 'Should return a table')

  local count = 0
  for port, info in pairs(project_ports) do
    count = count + 1
    assert(info.project_id == project_id, 'All ports should belong to the project')
  end
  assert(count == 2, 'Should have 2 ports for the project')
end)

-- Test 11: is_port_allocated functionality
test('is_port_allocated functionality', function()
  local test_port = 20001

  -- Check unallocated port
  assert(not port_utils.is_port_allocated(test_port), 'Port should not be allocated initially')

  -- Allocate and check
  port_utils.allocate_port(test_port, 'test-project', 'test')
  assert(port_utils.is_port_allocated(test_port), 'Port should be allocated')

  -- Release and check
  port_utils.release_port(test_port)
  assert(not port_utils.is_port_allocated(test_port), 'Port should not be allocated after release')
end)

-- Test 12: parse_port_spec with number input
test('parse_port_spec with number input', function()
  local spec, err = port_utils.parse_port_spec(3000)
  assert(spec ~= nil, 'Should parse number successfully')
  assert(err == nil, 'Should not have error')
  assert(spec.type == 'fixed', 'Should be fixed type')
  assert(spec.host_port == 3000, 'Host port should be 3000')
  assert(spec.container_port == 3000, 'Container port should be 3000')
end)

-- Test 13: parse_port_spec with auto format
test('parse_port_spec with auto format', function()
  local spec, err = port_utils.parse_port_spec('auto:8080')
  assert(spec ~= nil, 'Should parse auto format successfully')
  assert(err == nil, 'Should not have error')
  assert(spec.type == 'auto', 'Should be auto type')
  assert(spec.container_port == 8080, 'Container port should be 8080')
  assert(spec.host_port == nil, 'Host port should be nil for auto')
end)

-- Test 14: parse_port_spec with range format
test('parse_port_spec with range format', function()
  local spec, err = port_utils.parse_port_spec('range:9000-9100:3000')
  assert(spec ~= nil, 'Should parse range format successfully')
  assert(err == nil, 'Should not have error')
  assert(spec.type == 'range', 'Should be range type')
  assert(spec.range_start == 9000, 'Range start should be 9000')
  assert(spec.range_end == 9100, 'Range end should be 9100')
  assert(spec.container_port == 3000, 'Container port should be 3000')
end)

-- Test 15: parse_port_spec with host:container format
test('parse_port_spec with host:container format', function()
  local spec, err = port_utils.parse_port_spec('8080:3000')
  assert(spec ~= nil, 'Should parse host:container format successfully')
  assert(err == nil, 'Should not have error')
  assert(spec.type == 'fixed', 'Should be fixed type')
  assert(spec.host_port == 8080, 'Host port should be 8080')
  assert(spec.container_port == 3000, 'Container port should be 3000')
end)

-- Test 16: parse_port_spec with string number
test('parse_port_spec with string number', function()
  local spec, err = port_utils.parse_port_spec('5000')
  assert(spec ~= nil, 'Should parse string number successfully')
  assert(err == nil, 'Should not have error')
  assert(spec.type == 'fixed', 'Should be fixed type')
  assert(spec.host_port == 5000, 'Host port should be 5000')
  assert(spec.container_port == 5000, 'Container port should be 5000')
end)

-- Test 17: parse_port_spec with invalid input
test('parse_port_spec with invalid input', function()
  -- Test invalid type
  local spec, err = port_utils.parse_port_spec({})
  assert(spec == nil, 'Should return nil for invalid type')
  assert(err ~= nil, 'Should have error message')
  assert(err:find('Invalid port specification type'), 'Should have appropriate error message')

  -- Test invalid format
  local spec2, err2 = port_utils.parse_port_spec('invalid:format:test')
  assert(spec2 == nil, 'Should return nil for invalid format')
  assert(err2 ~= nil, 'Should have error message')
  assert(err2:find('Invalid port specification format'), 'Should have appropriate error message')
end)

-- Test 18: resolve_dynamic_ports with fixed ports
test('resolve_dynamic_ports with fixed ports', function()
  local port_specs = { 3000, '8080:4000' }
  local project_id = 'fixed-test'

  local resolved, errors = port_utils.resolve_dynamic_ports(port_specs, project_id)
  assert(resolved ~= nil, 'Should resolve successfully')
  assert(errors == nil, 'Should not have errors')
  assert(#resolved == 2, 'Should resolve 2 ports')
  assert(resolved[1].host_port == 3000, 'First port should be 3000')
  assert(resolved[2].host_port == 8080, 'Second port should be 8080')
end)

-- Test 19: resolve_dynamic_ports with auto ports
test('resolve_dynamic_ports with auto ports', function()
  local port_specs = { 'auto:3000', 'auto:4000' }
  local project_id = 'auto-test'
  local config = {
    port_range_start = 10000,
    port_range_end = 10010,
  }

  local resolved, errors = port_utils.resolve_dynamic_ports(port_specs, project_id, config)
  assert(resolved ~= nil, 'Should resolve successfully')
  assert(errors == nil, 'Should not have errors')
  assert(#resolved == 2, 'Should resolve 2 ports')
  assert(resolved[1].type == 'dynamic', 'First port should be dynamic')
  assert(resolved[2].type == 'dynamic', 'Second port should be dynamic')
  assert(resolved[1].host_port ~= nil, 'First port should have host_port')
  assert(resolved[2].host_port ~= nil, 'Second port should have host_port')
end)

-- Test 20: resolve_dynamic_ports with range ports
test('resolve_dynamic_ports with range ports', function()
  local port_specs = { 'range:20000-20005:3000' }
  local project_id = 'range-test'

  local resolved, errors = port_utils.resolve_dynamic_ports(port_specs, project_id)
  assert(resolved ~= nil, 'Should resolve successfully')
  assert(errors == nil, 'Should not have errors')
  assert(#resolved == 1, 'Should resolve 1 port')
  assert(resolved[1].type == 'dynamic', 'Port should be dynamic')
  assert(resolved[1].host_port >= 20000 and resolved[1].host_port <= 20005, 'Host port should be in range')
end)

-- Test 21: resolve_dynamic_ports with errors
test('resolve_dynamic_ports with errors', function()
  local port_specs = { 'invalid:format', 'auto:3000' }
  local project_id = 'error-test'

  local resolved, errors = port_utils.resolve_dynamic_ports(port_specs, project_id)
  assert(resolved ~= nil, 'Should return resolved table even with errors')
  assert(errors ~= nil, 'Should have errors')
  assert(#errors > 0, 'Should have at least one error')
  assert(#resolved == 1, 'Should resolve valid ports despite errors')
end)

-- Test 22: resolve_dynamic_ports with no available ports
test('resolve_dynamic_ports with no available ports', function()
  local port_specs = { 'auto:3000' }
  local project_id = 'no-ports-test'
  local config = {
    port_range_start = 30000,
    port_range_end = 30005,
  }

  local resolved, errors = port_utils.resolve_dynamic_ports(port_specs, project_id, config)
  assert(resolved ~= nil, 'Should return resolved table')
  assert(errors ~= nil, 'Should have errors for unavailable ports')
  assert(#errors > 0, 'Should have at least one error')
  assert(#resolved == 0, 'Should not resolve any ports')
end)

-- Test 23: get_port_statistics functionality
test('get_port_statistics functionality', function()
  -- Clear existing allocations first
  local all_ports = port_utils.get_allocated_ports()
  for port in pairs(all_ports) do
    port_utils.release_port(port)
  end

  -- Allocate some test ports
  port_utils.allocate_port(10000, 'project-stats-1', 'web')
  port_utils.allocate_port(10001, 'project-stats-1', 'api')
  port_utils.allocate_port(15000, 'project-stats-2', 'database')
  port_utils.allocate_port(30000, 'project-stats-3', 'cache') -- Outside default range

  local stats = port_utils.get_port_statistics()
  assert(type(stats) == 'table', 'Should return a table')
  assert(stats.total_allocated == 4, 'Should have 4 total allocated ports')
  assert(stats.by_project['project-stats-1'] == 2, 'Project 1 should have 2 ports')
  assert(stats.by_project['project-stats-2'] == 1, 'Project 2 should have 1 port')
  assert(stats.by_purpose['web'] == 1, 'Should have 1 web port')
  assert(stats.by_purpose['api'] == 1, 'Should have 1 api port')
  assert(stats.port_range_usage.allocated_in_range == 3, 'Should have 3 ports in default range')
end)

-- Test 24: validate_port_config functionality
test('validate_port_config functionality', function()
  -- Test valid configuration
  local valid_config = {
    port_range_start = 10000,
    port_range_end = 20000,
  }
  local errors = port_utils.validate_port_config(valid_config)
  assert(#errors == 0, 'Valid config should have no errors')

  -- Test invalid range order
  local invalid_order = {
    port_range_start = 20000,
    port_range_end = 10000,
  }
  local errors2 = port_utils.validate_port_config(invalid_order)
  assert(#errors2 > 0, 'Invalid range order should have errors')

  -- Test system port warning
  local system_ports = {
    port_range_start = 80,
    port_range_end = 1000,
  }
  local errors3 = port_utils.validate_port_config(system_ports)
  assert(#errors3 > 0, 'System port range should have errors')

  -- Test port too high
  local high_ports = {
    port_range_start = 60000,
    port_range_end = 70000,
  }
  local errors4 = port_utils.validate_port_config(high_ports)
  assert(#errors4 > 0, 'Port range too high should have errors')
end)

-- Test 25: validate_port_config edge cases
test('validate_port_config edge cases', function()
  -- Test empty config
  local empty_config = {}
  local errors = port_utils.validate_port_config(empty_config)
  assert(#errors == 0, 'Empty config should be valid')

  -- Test partial config (only start)
  local partial_config = {
    port_range_start = 10000,
  }
  local errors2 = port_utils.validate_port_config(partial_config)
  assert(#errors2 == 0, 'Partial config should be valid')

  -- Test boundary values
  local boundary_config = {
    port_range_start = 1024,
    port_range_end = 65535,
  }
  local errors3 = port_utils.validate_port_config(boundary_config)
  assert(#errors3 == 0, 'Boundary values should be valid')
end)

-- Test 26: Stress test with many allocations
test('Stress test with many allocations', function()
  local project_id = 'stress-test'
  local allocated_ports = {}

  -- Allocate many ports
  for i = 1, 5 do
    local port = port_utils.find_available_port(10000, 10010)
    if port then
      port_utils.allocate_port(port, project_id, 'stress-' .. i)
      table.insert(allocated_ports, port)
    end
  end

  assert(#allocated_ports > 0, 'Should allocate at least some ports')

  -- Verify all are allocated
  for _, port in ipairs(allocated_ports) do
    assert(port_utils.is_port_allocated(port), 'Port should be allocated')
  end

  -- Clean up
  local released = port_utils.release_project_ports(project_id)
  assert(released == #allocated_ports, 'Should release all allocated ports')
end)

-- Test 27: Complex workflow test
test('Complex workflow test', function()
  local project_id = 'workflow-test'

  -- 1. Parse various port specifications
  local port_specs = {
    3000,
    'auto:4000',
    'range:20000-20005:5000',
    '8080:6000',
  }

  -- 2. Resolve all dynamic ports
  local resolved, errors = port_utils.resolve_dynamic_ports(port_specs, project_id, {
    port_range_start = 10000,
    port_range_end = 10010,
  })

  assert(resolved ~= nil, 'Should resolve ports')
  assert(#resolved >= 3, 'Should resolve most ports')

  -- 3. Check allocation status
  local project_ports = port_utils.get_project_ports(project_id)
  assert(next(project_ports) ~= nil, 'Project should have allocated ports')

  -- 4. Get statistics
  local stats = port_utils.get_port_statistics()
  assert(stats.by_project[project_id] ~= nil, 'Stats should include project')

  -- 5. Clean up
  local released = port_utils.release_project_ports(project_id)
  assert(released > 0, 'Should release ports')

  -- 6. Verify cleanup
  local final_project_ports = port_utils.get_project_ports(project_id)
  assert(next(final_project_ports) == nil, 'Project should have no ports after cleanup')
end)

-- Test 28: Test edge cases with port allocation
test('Edge cases with port allocation', function()
  -- Test allocation with invalid port numbers
  local success = port_utils.allocate_port(-1, 'test', 'test')
  assert(success == true, 'Should still allocate invalid port numbers')

  -- Test allocation with very high port
  local success2 = port_utils.allocate_port(99999, 'test', 'test')
  assert(success2 == true, 'Should allocate high port numbers')

  -- Test allocation with nil project_id and purpose
  local success3 = port_utils.allocate_port(50000, nil, nil)
  assert(success3 == true, 'Should handle nil parameters')

  -- Clean up
  port_utils.release_port(-1)
  port_utils.release_port(99999)
  port_utils.release_port(50000)
end)

-- Test 29: Test find_available_port with edge cases
test('find_available_port edge cases', function()
  -- Test with inverted range
  local port = port_utils.find_available_port(10010, 10000)
  assert(port == nil, 'Should return nil for inverted range')

  -- Test with same start and end
  local port2 = port_utils.find_available_port(10000, 10000)
  assert(port2 == 10000 or port2 == nil, 'Should handle single port range')

  -- Test with exclude list containing all possible ports
  local all_ports = {}
  for i = 10000, 10010 do
    table.insert(all_ports, i)
  end
  local port3 = port_utils.find_available_port(10000, 10010, all_ports)
  assert(port3 == nil, 'Should return nil when all ports excluded')
end)

-- Test 30: Test allocation timestamp and info
test('Allocation timestamp and info', function()
  local test_port = 20002
  local project_id = 'timestamp-test'
  local purpose = 'testing'

  local before_time = os.time()
  local success = port_utils.allocate_port(test_port, project_id, purpose)
  local after_time = os.time()

  assert(success == true, 'Port allocation should succeed')

  local allocated = port_utils.get_allocated_ports()
  local port_info = allocated[test_port]

  assert(port_info ~= nil, 'Port info should exist')
  assert(port_info.project_id == project_id, 'Project ID should match')
  assert(port_info.purpose == purpose, 'Purpose should match')
  assert(port_info.allocated_at >= before_time, 'Timestamp should be after start')
  assert(port_info.allocated_at <= after_time, 'Timestamp should be before end')

  -- Clean up
  port_utils.release_port(test_port)
end)

-- Final cleanup and summary
print('=== Test Summary ===')
print(string.format('Total tests: %d', test_count))
print(string.format('Passed: %d', passed_count))
print(string.format('Failed: %d', test_count - passed_count))

if passed_count == test_count then
  print('🎉 All port utility tests passed!')
  print()
  print('Coverage areas tested:')
  print('  ✓ Port availability detection')
  print('  ✓ Port allocation and release')
  print('  ✓ Project-based port management')
  print('  ✓ Port specification parsing (all formats)')
  print('  ✓ Dynamic port resolution')
  print('  ✓ Port statistics and monitoring')
  print('  ✓ Configuration validation')
  print('  ✓ Error handling and edge cases')
  print('  ✓ Complex workflows and stress testing')
  print('  ✓ Timestamp and metadata tracking')
else
  print('❌ Some tests failed')
  os.exit(1)
end
