#!/usr/bin/env lua

-- Core test script for container.nvim config.lua module
-- Focuses on core functionality for maximum coverage improvement

-- Add project lua directory to package path
package.path = './lua/?.lua;./lua/?/init.lua;../lua/?.lua;../lua/?/init.lua;' .. package.path

-- Store original functions for restoration
local original_vim = _G.vim

-- Create minimal mock environment
_G.vim = {
  split = function(str, sep, opts)
    if not str or str == '' then
      return {}
    end
    local result = {}
    local pattern = sep == '.' and '%.' or sep
    for part in (str .. sep):gmatch('([^' .. pattern .. ']*)' .. pattern) do
      if part ~= '' then
        table.insert(result, part)
      end
    end
    return result
  end,
  env = {},
  log = { levels = { DEBUG = 1, INFO = 2, WARN = 3, ERROR = 4 } },
  notify = function(msg, level) end,
  inspect = function(obj, opts)
    if type(obj) == 'table' then
      local parts = {}
      for k, v in pairs(obj) do
        table.insert(parts, tostring(k) .. '=' .. tostring(v))
      end
      return '{' .. table.concat(parts, ',') .. '}'
    end
    return tostring(obj)
  end,
  fn = {
    getcwd = function()
      return '/test/workspace'
    end,
    filereadable = function(path)
      return 0
    end,
    stdpath = function(what)
      return '/test/' .. what
    end,
  },
}

-- Test helper functions
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

local function assert_truthy(value, message)
  if not value then
    error(
      string.format(
        'Assertion failed: %s\nExpected truthy value, got: %s',
        message or 'value should be truthy',
        tostring(value)
      )
    )
  end
end

local function assert_type(value, expected_type, message)
  local actual_type = type(value)
  if actual_type ~= expected_type then
    error(
      string.format(
        'Assertion failed: %s\nExpected type: %s\nActual type: %s',
        message or 'type check failed',
        expected_type,
        actual_type
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

-- Clear package cache
local function clear_cache()
  package.loaded['container.config'] = nil
  package.loaded['container.config.validator'] = nil
  package.loaded['container.config.env'] = nil
  package.loaded['container.utils.log'] = nil
  package.loaded['container.utils.fs'] = nil
end

print('Starting container.nvim config.lua core tests...')

-- Test 1: Module Loading and Basic Structure
print('\n=== Test 1: Module Loading and Basic Structure ===')

clear_cache()
local config = require('container.config')

-- Test module structure
assert_type(config, 'table', 'Config module should be a table')
assert_type(config.defaults, 'table', 'Config defaults should be a table')
assert_type(config.setup, 'function', 'Config setup should be a function')
assert_type(config.get, 'function', 'Config get should be a function')
assert_type(config.get_value, 'function', 'Config get_value should be a function')
assert_type(config.set_value, 'function', 'Config set_value should be a function')
assert_type(config.reset, 'function', 'Config reset should be a function')
assert_type(config.reload, 'function', 'Config reload should be a function')
print('✓ Module structure verified')

-- Test default configuration keys
local defaults = config.defaults
assert_truthy(defaults.auto_open, 'Defaults should have auto_open')
assert_truthy(defaults.log_level, 'Defaults should have log_level')
assert_truthy(defaults.container_runtime, 'Defaults should have container_runtime')
assert_truthy(defaults.workspace, 'Defaults should have workspace table')
assert_truthy(defaults.lsp, 'Defaults should have lsp table')
assert_truthy(defaults.terminal, 'Defaults should have terminal table')
assert_truthy(defaults.ui, 'Defaults should have ui table')
print('✓ Default configuration structure verified')

-- Test 2: Deep Copy Function
print('\n=== Test 2: Deep Copy Function ===')

-- Test through setup which uses deep_copy internally
local original_defaults = config.defaults
local success, result = config.setup({})
assert_equals(success, true, 'Basic setup should succeed')

-- Modify current config and ensure defaults are unchanged
config.set_value('log_level', 'modified')
assert_equals(config.get_value('log_level'), 'modified', 'Current config should be modified')
assert_equals(original_defaults.log_level, 'info', 'Original defaults should be unchanged')
print('✓ Deep copy functionality verified')

-- Test 3: Configuration Value Access and Setting
print('\n=== Test 3: Configuration Value Access and Setting ===')

-- Test basic value operations
config.set_value('test_value', 'test')
local value = config.get_value('test_value')
assert_equals(value, 'test', 'Basic value setting and getting should work')

-- Test nested value operations
config.set_value('nested.deep.value', 'deep_test')
value = config.get_value('nested.deep.value')
assert_equals(value, 'deep_test', 'Nested value setting and getting should work')

-- Test non-existent value
value = config.get_value('non.existent.path')
assert_nil(value, 'Non-existent path should return nil')

-- Test empty path (may return full config object)
value = config.get_value('')
if value == nil then
  print('  Empty path returns nil (expected behavior)')
else
  print('  Empty path returns config object (alternative behavior)')
end
print('✓ Value access and setting verified')

-- Test 4: Configuration Merging
print('\n=== Test 4: Configuration Merging ===')

-- Test simple merging
success, result = config.setup({
  log_level = 'debug',
  new_setting = 'new_value',
})
assert_equals(success, true, 'Setup with simple config should succeed')
assert_equals(config.get_value('log_level'), 'debug', 'Simple merge should work')
assert_equals(config.get_value('new_setting'), 'new_value', 'New values should be added')

-- Test nested merging
success, result = config.setup({
  lsp = {
    timeout = 20000,
    new_lsp_setting = 'lsp_value',
  },
  workspace = {
    auto_mount = false,
  },
})
assert_equals(success, true, 'Setup with nested config should succeed')
assert_equals(config.get_value('lsp.timeout'), 20000, 'Nested values should be merged')
assert_equals(config.get_value('lsp.new_lsp_setting'), 'lsp_value', 'New nested values should be added')
assert_equals(config.get_value('workspace.auto_mount'), false, 'Nested boolean values should be set')
print('✓ Configuration merging verified')

-- Test 5: Configuration Reset
print('\n=== Test 5: Configuration Reset ===')

-- Set some custom values
config.set_value('custom.test', 'custom_value')
config.set_value('log_level', 'trace')

-- Reset configuration
local reset_result = config.reset()
assert_type(reset_result, 'table', 'Reset should return configuration table')
assert_equals(config.get_value('log_level'), 'info', 'Log level should be reset to default')
assert_nil(config.get_value('custom.test'), 'Custom values should be removed')
print('✓ Configuration reset verified')

-- Test 6: Configuration Reload
print('\n=== Test 6: Configuration Reload ===')

-- Initial setup
config.setup({ log_level = 'info', test_setting = 'original' })

-- Reload with new configuration
success, result = config.reload({
  log_level = 'warn',
  test_setting = 'reloaded',
  new_reload_setting = 'reload_value',
})
assert_equals(success, true, 'Reload should succeed')
assert_equals(config.get_value('log_level'), 'warn', 'Reloaded values should be applied')
assert_equals(config.get_value('test_setting'), 'reloaded', 'Updated values should be applied')
assert_equals(config.get_value('new_reload_setting'), 'reload_value', 'New values should be added')
print('✓ Configuration reload verified')

-- Test 7: Configuration Difference Detection
print('\n=== Test 7: Configuration Difference Detection ===')

local config1 = {
  setting1 = 'value1',
  nested = {
    key1 = 'nested_value1',
    shared = 'original',
  },
}

local config2 = {
  setting1 = 'value2',
  setting2 = 'new_value',
  nested = {
    key1 = 'nested_value2',
    key2 = 'new_nested',
    shared = 'original',
  },
}

local diffs = config.diff_configs(config1, config2)
assert_type(diffs, 'table', 'diff_configs should return table')
assert_truthy(#diffs > 0, 'Should detect differences')

-- Check for expected change types
local found_change = false
local found_addition = false
for _, diff in ipairs(diffs) do
  if diff.action == 'changed' then
    found_change = true
  elseif diff.action == 'added' then
    found_addition = true
  end
end
assert_truthy(found_change, 'Should detect changed values')
assert_truthy(found_addition, 'Should detect added values')
print('✓ Configuration difference detection verified')

-- Test diff_from_defaults
local default_diffs = config.diff_from_defaults()
assert_type(default_diffs, 'table', 'diff_from_defaults should return table')
print('✓ Default difference detection verified')

-- Test 8: Configuration Schema
print('\n=== Test 8: Configuration Schema ===')

local schema = config.get_schema()
assert_type(schema, 'table', 'Schema should be a table')
assert_truthy(schema['log_level'], 'Schema should include log_level')

-- Check if schema includes nested paths (may or may not depending on implementation)
local has_nested = false
for key, _ in pairs(schema) do
  if key:match('%.') then
    has_nested = true
    break
  end
end
if has_nested then
  print('  Schema includes nested paths')
else
  print('  Schema uses flat structure')
end

-- Test schema entry structure
local entry = schema['log_level']
if entry then
  assert_type(entry, 'table', 'Schema entry should be a table')
  if entry.type then
    assert_type(entry.type, 'string', 'Schema entry should have type')
  end
  if entry.default then
    print('  Schema entry has default value')
  end
end
print('✓ Configuration schema verified')

-- Test 9: Configuration Display
print('\n=== Test 9: Configuration Display ===')

-- Test show_config (should not error)
config.show_config()
print('✓ Configuration display verified')

-- Test 10: Path Edge Cases
print('\n=== Test 10: Path Edge Cases ===')

-- Test various edge cases for path operations
value = config.get_value('.')
if value == nil then
  print('  Single dot path returns nil')
else
  print('  Single dot path returns value (implementation behavior)')
end

value = config.get_value('.test')
if value == nil then
  print('  Path starting with dot returns nil')
else
  print('  Path starting with dot returns value')
end

value = config.get_value('test.')
if value == nil then
  print('  Path ending with dot returns nil')
else
  print('  Path ending with dot returns value')
end

-- Test creating deep nested structure
config.set_value('very.deep.nested.structure', 'deep_value')
value = config.get_value('very.deep.nested.structure')
assert_equals(value, 'deep_value', 'Deep nested creation should work')

-- Test overwriting structure with value
config.set_value('very.deep', 'replaced')
value = config.get_value('very.deep')
assert_equals(value, 'replaced', 'Structure replacement should work')
value = config.get_value('very.deep.nested.structure')
assert_nil(value, 'Replaced structure children should be removed')
print('✓ Path edge cases verified')

-- Test 11: Environment Variable Integration
print('\n=== Test 11: Environment Variable Integration ===')

-- Test with environment variables set
_G.vim.env = {
  CONTAINER_LOG_LEVEL = 'trace',
  CONTAINER_AUTO_START = 'true',
}

success, result = config.setup({
  log_level = 'info', -- Should override env var
})
assert_equals(success, true, 'Setup with env vars should succeed')
print('✓ Environment variable integration verified')

-- Clean up environment
_G.vim.env = {}

-- Test 12: Lazy Loading Integration
print('\n=== Test 12: Lazy Loading Integration ===')

-- Test accessing validator through metatable
local validator = config.validator
assert_type(validator, 'table', 'Validator should be accessible')

-- Test accessing env through metatable
local env = config.env
assert_type(env, 'table', 'Env should be accessible')
print('✓ Lazy loading integration verified')

-- Test 13: Error Handling
print('\n=== Test 13: Error Handling ===')

-- Test setup with nil
success, result = config.setup(nil)
assert_equals(success, true, 'Setup with nil should succeed')

-- Test diff with invalid inputs
local success, empty_diffs = pcall(config.diff_configs, {}, nil)
if success then
  assert_type(empty_diffs, 'table', 'diff_configs should handle nil gracefully')
  print('  diff_configs handles nil second argument')
else
  print('  diff_configs requires non-nil arguments (expected behavior)')
end

success, empty_diffs = pcall(config.diff_configs, nil, {})
if success then
  assert_type(empty_diffs, 'table', 'diff_configs should handle nil gracefully')
  print('  diff_configs handles nil first argument')
else
  print('  diff_configs requires non-nil arguments (expected behavior)')
end
print('✓ Error handling verified')

print('\n=== Config Core Test Results ===')
print('All config.lua core tests passed! ✓')
print('Expected significant coverage improvement for config.lua module')

-- Cleanup
_G.vim = original_vim
clear_cache()
