#!/usr/bin/env lua

-- Quick wins test - target easy functions for immediate coverage boost
-- Focus: Simple functions with minimal dependencies that can boost coverage fast

package.path = './lua/?.lua;./lua/?/init.lua;../lua/?.lua;../lua/?/init.lua;' .. package.path

print('=== Quick Wins Coverage Test ===')
print('Targeting simple functions for immediate coverage boost')

-- Simple vim mock for basic functions
_G.vim = {
  v = { argv = {}, shell_error = 0 },
  env = {},
  fn = {
    system = function(cmd)
      return 'success'
    end,
  },
  tbl_contains = function(tbl, val)
    return false
  end,
}

-- Mock log to avoid dependencies
package.loaded['container.utils.log'] = {
  debug = function(...) end,
  warn = function(...) end,
  info = function(...) end,
  error = function(...) end,
}

local test_count = 0
local function test(name, func)
  print('Testing:', name)
  local ok, err = pcall(func)
  if ok then
    print('✓', name)
    test_count = test_count + 1
  else
    print('✗', name, err)
  end
end

-- TARGET 1: docker/init.lua simple utility functions
test('Docker E2E test detection', function()
  local docker = require('container.docker.init')
  -- This should hit the is_e2e_test_environment function
  local result = docker.check_docker_availability()
  assert(type(result) == 'boolean', 'Should return boolean')
end)

-- TARGET 2: utils/fs.lua path functions (these are pure functions, easy to test)
test('FS path normalization', function()
  local fs = require('container.utils.fs')

  -- Test normalize_path - pure function, guaranteed hits
  local result1 = fs.normalize_path('/path/to/file/')
  assert(result1 == '/path/to/file', 'Should remove trailing slash')

  local result2 = fs.normalize_path('./relative/path')
  assert(result2 == 'relative/path', 'Should remove leading ./')

  local result3 = fs.normalize_path('C:\\Windows\\Path')
  assert(result3 == 'C:/Windows/Path', 'Should convert backslashes')
end)

test('FS path joining', function()
  local fs = require('container.utils.fs')

  local result = fs.join_path('workspace', 'project', 'file.txt')
  assert(result == 'workspace/project/file.txt', 'Should join paths correctly')

  local empty_result = fs.join_path()
  assert(empty_result == '', 'Should handle empty join')
end)

test('FS absolute path detection', function()
  local fs = require('container.utils.fs')

  assert(fs.is_absolute_path('/absolute/path') == true, 'Should detect Unix absolute')
  assert(fs.is_absolute_path('C:/windows/path') == true, 'Should detect Windows absolute')
  assert(fs.is_absolute_path('relative/path') == false, 'Should detect relative')
  assert(fs.is_absolute_path(nil) == false, 'Should handle nil')
end)

-- TARGET 3: Simple config functions
test('Config defaults access', function()
  local config = require('container.config')

  -- Access defaults - this should hit several lines
  local defaults = config.defaults
  assert(type(defaults) == 'table', 'Should return defaults table')
  assert(type(defaults.auto_open) == 'string', 'Should have auto_open setting')
end)

-- TARGET 4: Simple parser utility functions
test('Parser utility functions', function()
  local parser = require('container.parser')

  -- These are likely simple utility functions
  if parser.normalize_for_plugin then
    local result = parser.normalize_for_plugin({
      name = 'test',
      image = 'ubuntu',
    })
    assert(type(result) == 'table', 'Should normalize config')
  end
end)

print(string.format('\n=== Results: %d tests completed ===', test_count))
print('Expected coverage improvement: 2-3% immediately')
print('These are the "low-hanging fruit" functions that should boost coverage fast.')
