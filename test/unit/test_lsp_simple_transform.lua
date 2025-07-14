#!/usr/bin/env lua

-- Comprehensive unit tests for container.lsp.simple_transform module
-- This test suite achieves high test coverage for the LSP path transformation module

-- Add project lua directory to package path
package.path = './lua/?.lua;./lua/?/init.lua;../lua/?.lua;../lua/?/init.lua;' .. package.path

-- Test state for mocking various vim components
local test_state = {
  current_buf = 1,
  buffers = {
    [0] = { name = '/test/workspace/main.go', valid = true, loaded = true },
    [1] = { name = '/test/workspace/main.go', valid = true, loaded = true },
    [2] = { name = '/test/workspace/src/module.go', valid = true, loaded = true },
    [3] = { name = '', valid = true, loaded = true }, -- Empty buffer name
    [4] = { name = 'relative/path.go', valid = true, loaded = true }, -- Relative path
  },
  cwd = '/test/workspace',
}

-- Mock vim global with comprehensive API
_G.vim = {
  -- String and table utilities
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
    local sources = { ... }
    for _, source in ipairs(sources) do
      if type(source) == 'table' then
        for k, v in pairs(source) do
          if type(v) == 'table' and type(result[k]) == 'table' and behavior == 'force' then
            result[k] = vim.tbl_deep_extend(behavior, result[k], v)
          else
            result[k] = v
          end
        end
      end
    end
    return result
  end,
  deepcopy = function(orig)
    if type(orig) ~= 'table' then
      return orig
    end
    local copy = {}
    for k, v in pairs(orig) do
      copy[k] = vim.deepcopy(v)
    end
    return copy
  end,
  -- Pattern escaping
  pesc = function(str)
    return str:gsub('[%(%)%.%%%+%-%*%?%[%]%^%$]', '%%%1')
  end,
  -- File system functions
  fn = {
    getcwd = function()
      return test_state.cwd
    end,
    fnamemodify = function(path, modifier)
      if modifier == ':p' then
        if vim.startswith(path, '/') then
          return path
        else
          return test_state.cwd .. '/' .. path
        end
      elseif modifier == ':h' then
        return path:match('(.*/)')
      elseif modifier == ':t' then
        return path:match('.*/(.*)') or path
      end
      return path
    end,
  },
  -- API functions
  api = {
    nvim_buf_get_name = function(bufnr)
      local buffer = test_state.buffers[bufnr]
      return buffer and buffer.name or ''
    end,
  },
  -- Logging (simplified for tests)
  notify = function(msg, level) end,
  log = { levels = { DEBUG = 1, INFO = 2, WARN = 3, ERROR = 4 } },
}

-- Test assertion helpers
local function assert_equals(actual, expected, message)
  if actual ~= expected then
    error(
      string.format(
        'Assertion failed: %s\nExpected: %s\nActual: %s',
        message or 'values should be equal',
        tostring(expected),
        tostring(actual)
      )
    )
  end
end

local function assert_nil(value, message)
  if value ~= nil then
    error(
      string.format('Assertion failed: %s\nExpected nil, got: %s', message or 'value should be nil', tostring(value))
    )
  end
end

local function assert_not_nil(value, message)
  if value == nil then
    error(string.format('Assertion failed: %s', message or 'value should not be nil'))
  end
end

local function assert_type(value, expected_type, message)
  local actual_type = type(value)
  if actual_type ~= expected_type then
    error(
      string.format(
        'Assertion failed: %s\nExpected type: %s\nActual type: %s',
        message or 'value should have correct type',
        expected_type,
        actual_type
      )
    )
  end
end

local function assert_table_contains(table, key, message)
  if table[key] == nil then
    error(
      string.format(
        'Assertion failed: %s\nTable does not contain key: %s',
        message or 'table should contain key',
        tostring(key)
      )
    )
  end
end

-- Load the module under test
local simple_transform = require('container.lsp.simple_transform')

print('Starting container.lsp.simple_transform tests...')

-- Test 1: Module Loading and Setup
print('\n=== Test 1: Module Loading and Setup ===')

-- Test module loads correctly
assert_type(simple_transform, 'table', 'Module should be a table')
assert_type(simple_transform.setup, 'function', 'setup should be a function')
assert_type(simple_transform.host_to_container, 'function', 'host_to_container should be a function')
assert_type(simple_transform.container_to_host, 'function', 'container_to_host should be a function')
print('✓ Module loads with expected functions')

-- Test setup with default values
simple_transform.setup()
local config = simple_transform.get_config()
assert_equals(config.container_workspace, '/workspace', 'Default container workspace should be /workspace')
assert_equals(config.host_workspace, '/test/workspace', 'Host workspace should be auto-detected')
assert_type(config.path_cache, 'table', 'Path cache should be initialized')
print('✓ Setup with defaults works correctly')

-- Test setup with custom values
simple_transform.setup({
  container_workspace = '/app',
  host_workspace = '/custom/host/path',
})
config = simple_transform.get_config()
assert_equals(config.container_workspace, '/app', 'Custom container workspace should be set')
assert_equals(config.host_workspace, '/custom/host/path', 'Custom host workspace should be set')
print('✓ Setup with custom values works correctly')

-- Test cache clearing on setup
simple_transform.setup()
config = simple_transform.get_config()
assert_type(config.path_cache, 'table', 'Cache should be cleared on setup')
print('✓ Cache clearing on setup works correctly')

-- Reset to default for remaining tests
simple_transform.setup({
  container_workspace = '/workspace',
  host_workspace = '/test/workspace',
})

-- Test 2: Basic Path Transformation
print('\n=== Test 2: Basic Path Transformation ===')

-- Test host to container path transformation
local host_path = '/test/workspace/src/main.go'
local container_path = simple_transform.host_to_container(host_path)
assert_equals(container_path, '/workspace/src/main.go', 'Host path should be transformed to container path')
print('✓ Basic host to container transformation works')

-- Test container to host path transformation
local converted_back = simple_transform.container_to_host(container_path)
assert_equals(converted_back, host_path, 'Container path should be transformed back to host path')
print('✓ Basic container to host transformation works')

-- Test with exact workspace match
local exact_workspace = '/test/workspace'
local exact_container = simple_transform.host_to_container(exact_workspace)
assert_equals(exact_container, '/workspace', 'Exact workspace path should be transformed correctly')
print('✓ Exact workspace path transformation works')

-- Test with paths outside workspace
local outside_path = '/different/path/file.go'
local outside_container = simple_transform.host_to_container(outside_path)
assert_equals(outside_container, outside_path, 'Paths outside workspace should remain unchanged')
print('✓ Paths outside workspace handled correctly')

-- Test 3: Edge Cases and Error Handling
print('\n=== Test 3: Edge Cases and Error Handling ===')

-- Test null/nil input handling
assert_nil(simple_transform.host_to_container(nil), 'nil host path should return nil')
assert_nil(simple_transform.container_to_host(nil), 'nil container path should return nil')
print('✓ nil input handling works correctly')

-- Test empty string handling
local empty_result = simple_transform.host_to_container('')
assert_equals(empty_result, '', 'Empty string should remain empty')
print('✓ Empty string handling works correctly')

-- Test paths with special characters
local special_path = '/test/workspace/path with spaces/file-name_test.go'
local special_container = simple_transform.host_to_container(special_path)
assert_equals(
  special_container,
  '/workspace/path with spaces/file-name_test.go',
  'Special characters should be handled'
)
print('✓ Special characters in paths handled correctly')

-- Test paths with regex special characters
local regex_path = '/test/workspace/path.with.dots/file[brackets].go'
local regex_container = simple_transform.host_to_container(regex_path)
assert_equals(regex_container, '/workspace/path.with.dots/file[brackets].go', 'Regex special chars should be escaped')
print('✓ Regex special characters handled correctly')

-- Test host workspace auto-detection when not configured
test_state.cwd = '/auto/detected/workspace'
simple_transform.setup({ container_workspace = '/app' })
local auto_path = '/auto/detected/workspace/file.go'
local auto_container = simple_transform.host_to_container(auto_path)
assert_equals(auto_container, '/app/file.go', 'Auto-detected workspace should work')
print('✓ Host workspace auto-detection works')

-- Reset for remaining tests
test_state.cwd = '/test/workspace'
simple_transform.setup({
  container_workspace = '/workspace',
  host_workspace = '/test/workspace',
})

-- Test 4: Path Caching
print('\n=== Test 4: Path Caching ===')

-- Clear cache first
simple_transform.clear_cache()

-- Test cache miss and hit
local cache_test_path = '/test/workspace/cached/file.go'
local first_result = simple_transform.host_to_container(cache_test_path)
local second_result = simple_transform.host_to_container(cache_test_path) -- Should hit cache
assert_equals(first_result, second_result, 'Cached result should match first result')
print('✓ Path caching works correctly')

-- Test cache contains the expected entry
config = simple_transform.get_config()
assert_table_contains(config.path_cache, cache_test_path, 'Cache should contain the test path')
print('✓ Cache stores entries correctly')

-- Test cache clearing
simple_transform.clear_cache()
config = simple_transform.get_config()
assert_equals(next(config.path_cache), nil, 'Cache should be empty after clearing')
print('✓ Cache clearing works correctly')

-- Test 5: URI Transformation
print('\n=== Test 5: URI Transformation ===')

-- Test host URI to container URI
local host_uri = 'file:///test/workspace/src/main.go'
local container_uri = simple_transform.host_uri_to_container(host_uri)
assert_equals(container_uri, 'file:///workspace/src/main.go', 'Host URI should be transformed to container URI')
print('✓ Host URI to container URI transformation works')

-- Test container URI to host URI
local converted_uri = simple_transform.container_uri_to_host(container_uri)
assert_equals(converted_uri, host_uri, 'Container URI should be transformed back to host URI')
print('✓ Container URI to host URI transformation works')

-- Test non-file URI handling
local http_uri = 'http://example.com/file'
local unchanged_uri = simple_transform.host_uri_to_container(http_uri)
assert_equals(unchanged_uri, http_uri, 'Non-file URIs should remain unchanged')
print('✓ Non-file URI handling works correctly')

-- Test nil URI handling
assert_nil(simple_transform.host_uri_to_container(nil), 'nil URI should return nil')
assert_nil(simple_transform.container_uri_to_host(nil), 'nil URI should return nil')
print('✓ nil URI handling works correctly')

-- Test malformed URI handling
local malformed_uri = 'not-a-uri'
local malformed_result = simple_transform.host_uri_to_container(malformed_uri)
assert_equals(malformed_result, malformed_uri, 'Malformed URIs should remain unchanged')
print('✓ Malformed URI handling works correctly')

-- Test 6: Buffer URI Functions
print('\n=== Test 6: Buffer URI Functions ===')

-- Test getting buffer container URI for current buffer
local buffer_uri = simple_transform.get_buffer_container_uri(0)
assert_equals(buffer_uri, 'file:///workspace/main.go', 'Current buffer URI should be transformed')
print('✓ Current buffer URI transformation works')

-- Test getting buffer container URI for specific buffer
local specific_buffer_uri = simple_transform.get_buffer_container_uri(2)
assert_equals(specific_buffer_uri, 'file:///workspace/src/module.go', 'Specific buffer URI should be transformed')
print('✓ Specific buffer URI transformation works')

-- Test buffer with empty name
local empty_buffer_uri = simple_transform.get_buffer_container_uri(3)
assert_nil(empty_buffer_uri, 'Buffer with empty name should return nil')
print('✓ Empty buffer name handling works')

-- Test buffer with relative path
local relative_buffer_uri = simple_transform.get_buffer_container_uri(4)
assert_equals(
  relative_buffer_uri,
  'file:///workspace/relative/path.go',
  'Relative path should be converted to absolute'
)
print('✓ Relative path conversion works')

-- Test default buffer (nil/0)
local default_buffer_uri = simple_transform.get_buffer_container_uri()
assert_equals(default_buffer_uri, 'file:///workspace/main.go', 'Default buffer should work')
print('✓ Default buffer parameter works')

-- Test 7: LSP Location Transformation
print('\n=== Test 7: LSP Location Transformation ===')

-- Test single location transformation to host
local container_location = {
  uri = 'file:///workspace/src/main.go',
  range = {
    start = { line = 10, character = 5 },
    ['end'] = { line = 10, character = 15 },
  },
}
local host_location = simple_transform.transform_location(container_location, 'to_host')
assert_equals(host_location.uri, 'file:///test/workspace/src/main.go', 'Location URI should be transformed to host')
assert_equals(host_location.range.start.line, 10, 'Range should be preserved')
print('✓ Single location transformation to host works')

-- Test single location transformation to container
local host_location2 = {
  uri = 'file:///test/workspace/lib/util.go',
  range = {
    start = { line = 5, character = 0 },
    ['end'] = { line = 5, character = 10 },
  },
}
local container_location2 = simple_transform.transform_location(host_location2, 'to_container')
assert_equals(
  container_location2.uri,
  'file:///workspace/lib/util.go',
  'Location URI should be transformed to container'
)
assert_equals(container_location2.range.start.line, 5, 'Range should be preserved')
print('✓ Single location transformation to container works')

-- Test location without URI
local location_no_uri = { range = { start = { line = 1, character = 1 } } }
local transformed_no_uri = simple_transform.transform_location(location_no_uri, 'to_host')
assert_equals(transformed_no_uri, location_no_uri, 'Location without URI should remain unchanged')
print('✓ Location without URI handling works')

-- Test nil location
local nil_location = simple_transform.transform_location(nil, 'to_host')
assert_nil(nil_location, 'nil location should return nil')
print('✓ nil location handling works')

-- Test 8: LSP Locations Array Transformation
print('\n=== Test 8: LSP Locations Array Transformation ===')

-- Test array of locations
local locations_array = {
  {
    uri = 'file:///workspace/file1.go',
    range = { start = { line = 1, character = 1 }, ['end'] = { line = 1, character = 5 } },
  },
  {
    uri = 'file:///workspace/file2.go',
    range = { start = { line = 2, character = 2 }, ['end'] = { line = 2, character = 8 } },
  },
}
local transformed_array = simple_transform.transform_locations(locations_array, 'to_host')
assert_type(transformed_array, 'table', 'Transformed array should be a table')
assert_equals(#transformed_array, 2, 'Array should have same length')
assert_equals(transformed_array[1].uri, 'file:///test/workspace/file1.go', 'First location should be transformed')
assert_equals(transformed_array[2].uri, 'file:///test/workspace/file2.go', 'Second location should be transformed')
print('✓ Array of locations transformation works')

-- Test single location passed as array-like (has uri field)
local single_as_array = simple_transform.transform_locations(container_location, 'to_host')
assert_equals(single_as_array.uri, 'file:///test/workspace/src/main.go', 'Single location should be transformed')
print('✓ Single location in array format works')

-- Test empty array
local empty_array = {}
local transformed_empty = simple_transform.transform_locations(empty_array, 'to_host')
assert_equals(transformed_empty, empty_array, 'Empty array should remain unchanged')
print('✓ Empty array handling works')

-- Test nil locations
local nil_locations = simple_transform.transform_locations(nil, 'to_host')
assert_nil(nil_locations, 'nil locations should return nil')
print('✓ nil locations handling works')

-- Test non-table input
local non_table = 'not a table'
local transformed_non_table = simple_transform.transform_locations(non_table, 'to_host')
assert_equals(transformed_non_table, non_table, 'Non-table input should remain unchanged')
print('✓ Non-table input handling works')

-- Test 9: Configuration Management
print('\n=== Test 9: Configuration Management ===')

-- Test getting configuration returns a copy
local config1 = simple_transform.get_config()
local config2 = simple_transform.get_config()
assert_not_nil(config1, 'Config should not be nil')
assert_not_nil(config2, 'Config should not be nil')
-- Modify one config
config1.test_field = 'test_value'
assert_nil(config2.test_field, 'Modifying one config copy should not affect another')
print('✓ Configuration returns independent copies')

-- Test configuration fields
assert_type(config2.container_workspace, 'string', 'Container workspace should be string')
assert_type(config2.host_workspace, 'string', 'Host workspace should be string')
assert_type(config2.path_cache, 'table', 'Path cache should be table')
print('✓ Configuration has expected fields')

-- Test 10: Integration Scenarios
print('\n=== Test 10: Integration Scenarios ===')

-- Test end-to-end LSP workflow simulation
local lsp_response = {
  {
    uri = 'file:///workspace/main.go',
    range = { start = { line = 10, character = 5 }, ['end'] = { line = 10, character = 15 } },
  },
  {
    uri = 'file:///workspace/utils.go',
    range = { start = { line = 20, character = 8 }, ['end'] = { line = 20, character = 18 } },
  },
}

-- Transform container response to host
local host_response = simple_transform.transform_locations(lsp_response, 'to_host')
assert_equals(host_response[1].uri, 'file:///test/workspace/main.go', 'First file should be transformed')
assert_equals(host_response[2].uri, 'file:///test/workspace/utils.go', 'Second file should be transformed')
print('✓ End-to-end LSP response transformation works')

-- Test round-trip transformation consistency
local original_uri = 'file:///test/workspace/example.go'
local to_container_uri = simple_transform.host_uri_to_container(original_uri)
local back_to_host_uri = simple_transform.container_uri_to_host(to_container_uri)
assert_equals(back_to_host_uri, original_uri, 'Round-trip transformation should be consistent')
print('✓ Round-trip transformation consistency verified')

-- Test path transformation with different workspace configurations
simple_transform.setup({
  container_workspace = '/custom/workspace',
  host_workspace = '/custom/host',
})
local custom_host_path = '/custom/host/src/file.go'
local custom_container_path = simple_transform.host_to_container(custom_host_path)
assert_equals(custom_container_path, '/custom/workspace/src/file.go', 'Custom workspace configuration should work')
print('✓ Custom workspace configuration works')

-- Test 11: Performance and Edge Cases
print('\n=== Test 11: Performance and Edge Cases ===')

-- Test very long paths
local long_path = '/custom/host' .. string.rep('/very/long/path/component', 10) .. '/file.go'
local long_result = simple_transform.host_to_container(long_path)
assert_not_nil(long_result, 'Long paths should be handled')
print('✓ Long path handling works')

-- Test paths with Unicode characters
local unicode_path = '/custom/host/文件/ファイル/αρχείο.go'
local unicode_result = simple_transform.host_to_container(unicode_path)
assert_equals(
  unicode_result,
  '/custom/workspace/文件/ファイル/αρχείο.go',
  'Unicode paths should be handled'
)
print('✓ Unicode path handling works')

-- Test multiple consecutive path separators
local multi_sep_path = '/custom//host///file.go'
local multi_sep_result = simple_transform.host_to_container(multi_sep_path)
assert_not_nil(multi_sep_result, 'Multiple separators should be handled')
print('✓ Multiple path separators handled')

-- Test case sensitivity
local case_path1 = '/custom/host/File.go'
local case_path2 = '/custom/host/file.go'
local case_result1 = simple_transform.host_to_container(case_path1)
local case_result2 = simple_transform.host_to_container(case_path2)
assert_equals(case_result1, '/custom/workspace/File.go', 'Case should be preserved')
assert_equals(case_result2, '/custom/workspace/file.go', 'Case should be preserved')
print('✓ Case sensitivity preserved')

print('\n=== Test Results ===')
print('All simple_transform tests passed! ✓')
print('Coverage includes:')
print('  - Module loading and setup')
print('  - Basic path transformations')
print('  - Edge cases and error handling')
print('  - Path caching functionality')
print('  - URI transformations')
print('  - Buffer URI operations')
print('  - LSP location transformations')
print('  - LSP locations array handling')
print('  - Configuration management')
print('  - Integration scenarios')
print('  - Performance and edge cases')
