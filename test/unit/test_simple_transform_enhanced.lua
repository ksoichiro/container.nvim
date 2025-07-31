#!/usr/bin/env lua

-- Enhanced test suite for simple_transform to improve coverage
-- Focuses on uncovered code paths and edge cases

package.path = './lua/?.lua;./lua/?/init.lua;../lua/?.lua;../lua/?/init.lua;' .. package.path

-- Mock vim environment
_G.vim = {
  fn = {
    getcwd = function()
      return '/test/default/workspace'
    end,
    fnamemodify = function(path, mod)
      if mod == ':p' then
        return path:match('^/') and path or '/test/default/workspace/' .. path
      end
      return path
    end,
    bufname = function(bufnr)
      local buffers = {
        [0] = '/test/workspace/current.go',
        [1] = '/test/workspace/file1.go',
        [2] = '', -- Empty buffer name
        [3] = 'relative.go', -- Relative path
      }
      return buffers[bufnr or 0] or ''
    end,
    bufnr = function()
      return 0
    end,
  },
  startswith = function(str, prefix)
    return str:sub(1, #prefix) == prefix
  end,
  split = function(str, sep)
    local result = {}
    for match in (str .. sep):gmatch('(.-)' .. sep) do
      table.insert(result, match)
    end
    return result
  end,
  uri_from_fname = function(fname)
    return 'file://' .. fname
  end,
  uri_to_fname = function(uri)
    return uri:gsub('^file://', '')
  end,
  deepcopy = function(t)
    if type(t) ~= 'table' then
      return t
    end
    local copy = {}
    for k, v in pairs(t) do
      copy[k] = vim.deepcopy(v)
    end
    return copy
  end,
  pesc = function(str)
    return str:gsub('[%(%)%.%+%-%*%?%[%]%^%$%%]', '%%%1')
  end,
  api = {
    nvim_buf_get_name = function(bufnr)
      local buffers = {
        [0] = '/test/workspace/current.go',
        [1] = '/test/workspace/file1.go',
        [2] = '', -- Empty buffer name
        [3] = 'relative.go', -- Relative path
      }
      return buffers[bufnr or 0] or ''
    end,
    nvim_get_current_buf = function()
      return 0
    end,
  },
}

print('=== Enhanced Simple Transform Coverage Tests ===')

-- Load the module
local transform = require('container.lsp.simple_transform')

local function assert_eq(actual, expected, message)
  if actual ~= expected then
    error(string.format('%s: expected %s, got %s', message or 'Assertion failed', tostring(expected), tostring(actual)))
  end
end

local function assert_not_nil(value, message)
  if value == nil then
    error(message or 'Value should not be nil')
  end
end

-- Test 1: Enhanced setup edge cases
print('\n--- Test 1: Enhanced Setup Edge Cases ---')

-- Setup without container_workspace option (should use default)
transform.setup({
  host_workspace = '/test/custom/host',
})

local config = transform.get_config()
assert_eq(config.container_workspace, '/workspace', 'Should use default container workspace')
assert_eq(config.host_workspace, '/test/custom/host', 'Should use provided host workspace')

-- Setup with container_workspace option
transform.setup({
  container_workspace = '/custom/container',
  host_workspace = '/custom/host',
})

config = transform.get_config()
assert_eq(config.container_workspace, '/custom/container', 'Should use custom container workspace')
assert_eq(config.host_workspace, '/custom/host', 'Should use custom host workspace')

print('✓ Enhanced setup edge cases passed')

-- Test 2: Path transformation edge cases
print('\n--- Test 2: Path Transformation Edge Cases ---')

transform.setup({
  host_workspace = '/test/workspace',
  container_workspace = '/workspace',
})

-- Test host_to_container with nil (should return nil)
local result = transform.host_to_container(nil)
assert_eq(result, nil, 'nil input should return nil')

-- Test host_to_container with cache hit (run twice)
local path1 = transform.host_to_container('/test/workspace/file.go')
local path2 = transform.host_to_container('/test/workspace/file.go')
assert_eq(path1, path2, 'Repeated calls should return same result')
assert_eq(path1, '/workspace/file.go', 'Path should be transformed correctly')

print('✓ Path transformation edge cases passed')

-- Test 3: Container to host edge cases
print('\n--- Test 3: Container to Host Edge Cases ---')

-- Test container_to_host with nil
result = transform.container_to_host(nil)
assert_eq(result, nil, 'nil input should return nil')

-- Test container_to_host with non-matching path
result = transform.container_to_host('/other/path/file.go')
assert_eq(result, '/other/path/file.go', 'Non-matching path should pass through')

print('✓ Container to host edge cases passed')

-- Test 4: URI transformation edge cases
print('\n--- Test 4: URI Transformation Edge Cases ---')

-- Test host_uri_to_container with nil
result = transform.host_uri_to_container(nil)
assert_eq(result, nil, 'nil URI should return nil')

-- Test container_uri_to_host with nil
result = transform.container_uri_to_host(nil)
assert_eq(result, nil, 'nil URI should return nil')

-- Test with non-file URI
result = transform.host_uri_to_container('http://example.com')
assert_eq(result, 'http://example.com', 'Non-file URI should pass through')

result = transform.container_uri_to_host('http://example.com')
assert_eq(result, 'http://example.com', 'Non-file URI should pass through')

print('✓ URI transformation edge cases passed')

-- Test 5: Buffer URI edge cases
print('\n--- Test 5: Buffer URI Edge Cases ---')

-- Test get_buffer_container_uri with empty buffer name
result = transform.get_buffer_container_uri(2) -- Empty buffer name
assert_eq(result, nil, 'Empty buffer name should return nil')

-- Test get_buffer_container_uri with relative path
result = transform.get_buffer_container_uri(3) -- Relative path
assert_not_nil(result, 'Relative path should be converted to absolute')

print('✓ Buffer URI edge cases passed')

-- Test 6: Location transformation edge cases
print('\n--- Test 6: Location Transformation Edge Cases ---')

-- Test transform_location with nil location
result = transform.transform_location(nil, 'host_to_container')
assert_eq(result, nil, 'nil location should return nil')

-- Test transform_location with location without URI
local location_no_uri = {
  range = {
    start = { line = 10, character = 5 },
    ['end'] = { line = 10, character = 15 },
  },
}
result = transform.transform_location(location_no_uri, 'host_to_container')
assert_eq(result.uri, nil, 'Location without URI should preserve structure')

print('✓ Location transformation edge cases passed')

-- Test 7: Locations array edge cases
print('\n--- Test 7: Locations Array Edge Cases ---')

-- Test transform_locations with nil
result = transform.transform_locations(nil, 'host_to_container')
assert_eq(result, nil, 'nil locations should return nil')

-- Test transform_locations with non-table input
result = transform.transform_locations('not a table', 'host_to_container')
assert_eq(result, 'not a table', 'Non-table input should return input as-is')

-- Test transform_locations with empty array
result = transform.transform_locations({}, 'host_to_container')
assert_eq(#result, 0, 'Empty array should return empty array')

print('✓ Locations array edge cases passed')

-- Test 8: Cache functionality
print('\n--- Test 8: Cache Functionality ---')

-- Clear cache and verify it's empty
transform.clear_cache()
config = transform.get_config()
local cache_count = 0
for _ in pairs(config.path_cache) do
  cache_count = cache_count + 1
end
assert_eq(cache_count, 0, 'Cache should be empty after clearing')

-- Add something to cache
transform.host_to_container('/test/workspace/cache_test.go')
config = transform.get_config()
cache_count = 0
for _ in pairs(config.path_cache) do
  cache_count = cache_count + 1
end
assert_eq(cache_count, 1, 'Cache should have one entry')

print('✓ Cache functionality passed')

-- Test 9: Configuration independence
print('\n--- Test 9: Configuration Independence ---')

local config1 = transform.get_config()
local config2 = transform.get_config()

-- Modify one config
config1.test_field = 'test_value'

-- Check other config is unaffected
assert_eq(config2.test_field, nil, 'Configurations should be independent')

print('✓ Configuration independence passed')

print('\n=== All Enhanced Coverage Tests Passed! ===')
print('Coverage improvements:')
print('  - Enhanced setup parameter handling')
print('  - Comprehensive nil input handling')
print('  - Cache functionality verification')
print('  - Edge cases for all transformation functions')
print('  - Configuration independence verification')
print('  - Buffer URI special cases')
print('  - Location transformation edge cases')

return true
