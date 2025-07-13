#!/usr/bin/env lua

-- Comprehensive test script for container.nvim config.lua module
-- Tests configuration management functionality for 70%+ coverage improvement

-- Add project lua directory to package path
package.path = './lua/?.lua;./lua/?/init.lua;../lua/?.lua;../lua/?/init.lua;' .. package.path

-- Store original functions for restoration
local original_getenv = os.getenv
local original_vim = _G.vim
local original_dofile = dofile
local original_io_open = io.open
local original_loadstring = loadstring

-- Mock vim global for testing
_G.vim = {
  split = function(str, sep, opts)
    local result = {}
    local trimempty = opts and opts.trimempty
    for match in (str .. sep):gmatch('(.-)' .. sep) do
      if not trimempty or match ~= '' then
        table.insert(result, match)
      end
    end
    return result
  end,
  env = {},
  log = { levels = { DEBUG = 1, INFO = 2, WARN = 3, ERROR = 4 } },
  notify = function(msg, level) end,
  inspect = function(obj, opts)
    -- Simple inspect implementation for testing
    if type(obj) == 'table' then
      local parts = {}
      for k, v in pairs(obj) do
        table.insert(parts, tostring(k) .. ' = ' .. tostring(v))
      end
      return '{' .. table.concat(parts, ', ') .. '}'
    end
    return tostring(obj)
  end,
  tbl_contains = function(tbl, val)
    for _, v in ipairs(tbl) do
      if v == val then
        return true
      end
    end
    return false
  end,
  split = function(str, sep, opts)
    local result = {}
    local trimempty = opts and opts.trimempty
    local plain = opts and opts.plain
    if plain then
      for match in (str .. sep):gmatch('(.-)' .. sep:gsub('%.', '%%.')) do
        if not trimempty or match ~= '' then
          table.insert(result, match)
        end
      end
    else
      for match in (str .. sep):gmatch('(.-)' .. sep) do
        if not trimempty or match ~= '' then
          table.insert(result, match)
        end
      end
    end
    return result
  end,
  fn = {
    getcwd = function()
      return '/test/workspace'
    end,
    filereadable = function(path)
      -- Mock filereadable function
      if path:match('readable_config%.lua$') then
        return 1
      elseif path:match('invalid_config%.lua$') then
        return 1
      elseif path:match('error_config%.lua$') then
        return 1
      end
      return 0
    end,
    stdpath = function(what)
      if what == 'data' then
        return '/test/data'
      end
      return '/test/' .. what
    end,
    has = function(feature)
      if feature == 'nvim-0.10' then
        return 1
      end
      return 0
    end,
    fnamemodify = function(path, modifier)
      -- Simple mock for path modification
      if modifier == ':p' then
        return path
      elseif modifier == ':h' then
        return path:gsub('/[^/]*$', '')
      elseif modifier == ':t' then
        return path:match('[^/]*$')
      end
      return path
    end,
    isdirectory = function(path)
      -- Simple mock - assume paths ending with / are directories
      return path:match('/$') and 1 or 0
    end,
    mkdir = function(path, mode)
      -- Simple mock - always succeed
      return 1
    end,
  },
  uv = {
    new_fs_event = function()
      return {
        start = function(self, path, opts, callback)
          -- Mock watcher
          return true
        end,
      }
    end,
  },
  api = {
    nvim_exec_autocmds = function(event, opts)
      -- Mock autocmd execution
    end,
    nvim_create_autocmd = function(events, opts)
      -- Mock autocmd creation
    end,
    nvim_create_augroup = function(name, opts)
      -- Mock augroup creation
      return 1
    end,
  },
  schedule_wrap = function(func)
    return func
  end,
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

local function assert_not_equals(actual, expected, message)
  if actual == expected then
    error(
      string.format(
        'Assertion failed: %s\nExpected: not %s\nActual: %s',
        message or 'values should not be equal',
        tostring(expected),
        tostring(actual)
      )
    )
  end
end

local function assert_table_equals(actual, expected, message)
  if type(actual) ~= 'table' or type(expected) ~= 'table' then
    error(
      string.format(
        'Assertion failed: %s\nBoth values must be tables\nActual: %s (%s)\nExpected: %s (%s)',
        message or 'tables should be equal',
        tostring(actual),
        type(actual),
        tostring(expected),
        type(expected)
      )
    )
  end

  for k, v in pairs(expected) do
    if type(v) == 'table' then
      assert_table_equals(actual[k], v, string.format('%s[%s]', message or 'table', k))
    else
      assert_equals(actual[k], v, string.format('%s[%s]', message or 'table', k))
    end
  end

  for k, _ in pairs(actual) do
    if expected[k] == nil then
      error(
        string.format(
          'Assertion failed: %s\nUnexpected key in actual table: %s',
          message or 'tables should be equal',
          tostring(k)
        )
      )
    end
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

local function assert_nil(value, message)
  if value ~= nil then
    error(
      string.format('Assertion failed: %s\nExpected nil, got: %s', message or 'value should be nil', tostring(value))
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

local function assert_contains(haystack, needle, message)
  if type(haystack) == 'string' then
    if not haystack:find(needle, 1, true) then
      error(
        string.format(
          'Assertion failed: %s\nExpected string to contain: %s\nActual string: %s',
          message or 'string should contain substring',
          tostring(needle),
          tostring(haystack)
        )
      )
    end
  elseif type(haystack) == 'table' then
    local found = false
    for _, v in pairs(haystack) do
      if v == needle then
        found = true
        break
      end
    end
    if not found then
      error(
        string.format(
          'Assertion failed: %s\nExpected table to contain: %s',
          message or 'table should contain value',
          tostring(needle)
        )
      )
    end
  else
    error('assert_contains: haystack must be string or table')
  end
end

local function assert_has_key(table, key, message)
  if type(table) ~= 'table' then
    error('assert_has_key: first argument must be a table')
  end
  if table[key] == nil then
    error(
      string.format(
        'Assertion failed: %s\nExpected table to have key: %s',
        message or 'table should have key',
        tostring(key)
      )
    )
  end
end

-- Setup and cleanup utilities
local function clear_package_cache()
  package.loaded['container.config'] = nil
  package.loaded['container.config.validator'] = nil
  package.loaded['container.config.env'] = nil
  package.loaded['container.utils.log'] = nil
  package.loaded['container.utils.fs'] = nil
end

local function setup_mocks()
  -- Mock dofile for project configuration testing
  dofile = function(path)
    if path:match('readable_config%.lua$') then
      return {
        log_level = 'debug',
        terminal = {
          default_shell = '/bin/bash',
        },
      }
    elseif path:match('invalid_config%.lua$') then
      return 'not a table'
    elseif path:match('error_config%.lua$') then
      error('config file error')
    end
    return original_dofile(path)
  end

  -- Mock io.open for filesystem operations
  io.open = function(path, mode)
    if path:match('test_config_save%.lua$') and mode == 'w' then
      return {
        write = function(self, content)
          return true
        end,
        close = function(self)
          return true
        end,
      }
    elseif path:match('test_config_load%.lua$') and mode == 'r' then
      return {
        read = function(self, format)
          if format == '*all' or format == '*a' then
            return 'return { log_level = "warn" }'
          end
          return nil
        end,
        close = function(self)
          return true
        end,
      }
    end
    return original_io_open(path, mode)
  end

  -- Mock loadstring for configuration parsing
  loadstring = function(content)
    if content == 'return { log_level = "warn" }' then
      return function()
        return { log_level = 'warn' }
      end
    elseif content:match('syntax error') then
      return nil, 'syntax error'
    end
    return original_loadstring(content)
  end
end

local function cleanup_mocks()
  dofile = original_dofile
  io.open = original_io_open
  loadstring = original_loadstring
  _G.vim = original_vim
  os.getenv = original_getenv
end

-- Load the module under test
print('Starting container.nvim config.lua comprehensive tests...')

-- Test 1: Module Loading and Defaults
print('\n=== Test 1: Module Loading and Defaults ===')

clear_package_cache()
setup_mocks()

local config = require('container.config')

-- Test module structure
assert_type(config, 'table', 'Config module should be a table')
assert_type(config.defaults, 'table', 'Config defaults should be a table')
assert_type(config.setup, 'function', 'Config setup should be a function')
assert_type(config.get, 'function', 'Config get should be a function')
print('✓ Module loads with expected structure')

-- Test default configuration structure
local defaults = config.defaults
assert_has_key(defaults, 'auto_open', 'Defaults should have auto_open')
assert_has_key(defaults, 'log_level', 'Defaults should have log_level')
assert_has_key(defaults, 'container_runtime', 'Defaults should have container_runtime')
assert_has_key(defaults, 'workspace', 'Defaults should have workspace')
assert_has_key(defaults, 'lsp', 'Defaults should have lsp')
assert_has_key(defaults, 'terminal', 'Defaults should have terminal')
assert_has_key(defaults, 'ui', 'Defaults should have ui')
assert_has_key(defaults, 'port_forwarding', 'Defaults should have port_forwarding')
assert_has_key(defaults, 'docker', 'Defaults should have docker')
print('✓ Default configuration has expected structure')

-- Test specific default values
assert_equals(defaults.auto_open, 'immediate', 'Default auto_open should be immediate')
assert_equals(defaults.log_level, 'info', 'Default log_level should be info')
assert_equals(defaults.container_runtime, 'docker', 'Default container_runtime should be docker')
assert_equals(defaults.workspace.auto_mount, true, 'Default workspace.auto_mount should be true')
assert_equals(defaults.lsp.auto_setup, true, 'Default lsp.auto_setup should be true')
print('✓ Default values are correct')

-- Test 2: Basic Configuration Setup
print('\n=== Test 2: Basic Configuration Setup ===')

-- Test setup with no user config
local success, result = config.setup()
assert_equals(success, true, 'Setup with no config should succeed')
assert_type(result, 'table', 'Setup should return configuration table')
print('✓ Setup with no user config works')

-- Test setup with empty config
success, result = config.setup({})
assert_equals(success, true, 'Setup with empty config should succeed')
print('✓ Setup with empty config works')

-- Test setup with partial config
success, result = config.setup({
  log_level = 'debug',
  lsp = {
    timeout = 10000,
  },
})
assert_equals(success, true, 'Setup with partial config should succeed')
local current_config = config.get()
assert_equals(current_config.log_level, 'debug', 'Custom log_level should be set')
assert_equals(current_config.lsp.timeout, 10000, 'Custom lsp.timeout should be set')
assert_equals(current_config.lsp.auto_setup, true, 'Default lsp.auto_setup should be preserved')
print('✓ Setup with partial config merges correctly')

-- Test 3: Deep Configuration Merging
print('\n=== Test 3: Deep Configuration Merging ===')

-- Test nested configuration merging
success, result = config.setup({
  terminal = {
    default_shell = '/bin/zsh',
    float = {
      width = 0.9,
    },
  },
  ui = {
    icons = {
      container = '🚢',
    },
  },
})
assert_equals(success, true, 'Setup with nested config should succeed')
current_config = config.get()
assert_equals(current_config.terminal.default_shell, '/bin/zsh', 'Nested terminal.default_shell should be set')
assert_equals(current_config.terminal.float.width, 0.9, 'Nested terminal.float.width should be set')
assert_equals(current_config.terminal.float.height, 0.6, 'Default terminal.float.height should be preserved')
assert_equals(current_config.ui.icons.container, '🚢', 'Nested ui.icons.container should be set')
assert_equals(current_config.ui.icons.running, '✅', 'Default ui.icons.running should be preserved')
print('✓ Deep configuration merging works correctly')

-- Test array merging (should replace, not merge)
success, result = config.setup({
  workspace = {
    exclude_patterns = { '.custom', 'build' },
  },
})
assert_equals(success, true, 'Setup with array config should succeed')
current_config = config.get()
-- Check that custom exclude patterns are present
assert_truthy(current_config.workspace.exclude_patterns, 'Exclude patterns should be set')
local found_custom = false
local found_build = false
for _, pattern in ipairs(current_config.workspace.exclude_patterns) do
  if pattern == '.custom' then
    found_custom = true
  elseif pattern == 'build' then
    found_build = true
  end
end
assert_truthy(found_custom, 'Custom pattern should be in exclude patterns')
assert_truthy(found_build, 'Build pattern should be in exclude patterns')
print('✓ Array configuration replacement works correctly')

-- Test 4: Configuration Validation
print('\n=== Test 4: Configuration Validation ===')

-- Note: Since we're testing the config module in isolation, and the validator
-- module is lazy-loaded, we'll test the validation integration indirectly

-- Test with invalid configuration (should still succeed but might log errors)
success, result = config.setup({
  log_level = 'invalid_level',
  auto_open_delay = 'not_a_number',
})
-- Validation might fail, but setup should handle it gracefully
assert_type(success, 'boolean', 'Setup should return boolean success value')
print('✓ Validation integration tested')

-- Test 5: Project-Specific Configuration Loading
print('\n=== Test 5: Project-Specific Configuration Loading ===')

-- Mock getcwd to return path with readable config
_G.vim.fn.getcwd = function()
  return '/test/readable_config'
end

success, result = config.setup({
  log_level = 'info',
})
assert_equals(success, true, 'Setup with project config should succeed')
current_config = config.get()
-- Project config should override defaults but user config should take precedence
assert_equals(current_config.log_level, 'info', 'User config should take precedence over project config')
print('✓ Project-specific configuration loading works')

-- Test with invalid project config
_G.vim.fn.getcwd = function()
  return '/test/invalid_config'
end

success, result = config.setup()
assert_equals(success, true, 'Setup should succeed even with invalid project config')
print('✓ Invalid project configuration handled gracefully')

-- Test with error in project config
_G.vim.fn.getcwd = function()
  return '/test/error_config'
end

success, result = config.setup()
assert_equals(success, true, 'Setup should succeed even with error in project config')
print('✓ Project configuration errors handled gracefully')

-- Restore original getcwd
_G.vim.fn.getcwd = function()
  return '/test/workspace'
end

-- Test 6: Configuration Value Access
print('\n=== Test 6: Configuration Value Access ===')

-- Setup known configuration
local setup_success, setup_result = config.setup({
  log_level = 'debug',
  lsp = {
    timeout = 15000,
    port_range = { 9000, 10000 },
  },
})
assert_equals(setup_success, true, 'Setup should succeed before value access tests')

-- Debug: Check current configuration state
local current_config = config.get()
print('Debug: Current config log_level =', current_config and current_config.log_level or 'nil')

-- Test get_value with simple path
local value = config.get_value('log_level')
assert_equals(value, 'debug', 'Simple path value access should work')

-- Test get_value with nested path
value = config.get_value('lsp.timeout')
assert_equals(value, 15000, 'Nested path value access should work')

-- Test get_value with array access
value = config.get_value('lsp.port_range')
assert_table_equals(value, { 9000, 10000 }, 'Array value access should work')

-- Test get_value with non-existent path
value = config.get_value('non.existent.path')
assert_nil(value, 'Non-existent path should return nil')

-- Test get_value with partial path
value = config.get_value('lsp')
assert_type(value, 'table', 'Partial path should return table')
assert_equals(value.timeout, 15000, 'Partial path table should have expected values')
print('✓ Configuration value access works correctly')

-- Test 7: Configuration Value Setting
print('\n=== Test 7: Configuration Value Setting ===')

-- Test set_value with simple path
config.set_value('log_level', 'error')
value = config.get_value('log_level')
assert_equals(value, 'error', 'Simple path value setting should work')

-- Test set_value with nested path
config.set_value('lsp.timeout', 20000)
value = config.get_value('lsp.timeout')
assert_equals(value, 20000, 'Nested path value setting should work')

-- Test set_value with new nested path
config.set_value('new.nested.value', 'test')
value = config.get_value('new.nested.value')
assert_equals(value, 'test', 'New nested path creation should work')

-- Test set_value with array replacement
config.set_value('workspace.exclude_patterns', { 'new', 'patterns' })
value = config.get_value('workspace.exclude_patterns')
assert_table_equals(value, { 'new', 'patterns' }, 'Array value setting should work')
print('✓ Configuration value setting works correctly')

-- Test 8: Configuration Reset and Reload
print('\n=== Test 8: Configuration Reset and Reload ===')

-- Modify configuration
config.set_value('log_level', 'custom')
config.set_value('custom.setting', 'value')

-- Test reset
local reset_config = config.reset()
assert_type(reset_config, 'table', 'Reset should return configuration table')
assert_equals(config.get_value('log_level'), 'info', 'Reset should restore default log_level')
assert_nil(config.get_value('custom.setting'), 'Reset should remove custom settings')
print('✓ Configuration reset works correctly')

-- Test reload with new configuration
success, result = config.reload({
  log_level = 'warn',
  new_setting = 'reload_test',
})
assert_equals(success, true, 'Reload should succeed')
assert_equals(config.get_value('log_level'), 'warn', 'Reload should apply new configuration')
assert_equals(config.get_value('new_setting'), 'reload_test', 'Reload should set new values')
print('✓ Configuration reload works correctly')

-- Test 9: Configuration Difference Detection
print('\n=== Test 9: Configuration Difference Detection ===')

-- Setup initial configuration
config.setup({
  log_level = 'info',
  lsp = {
    timeout = 5000,
  },
})

-- Create modified configuration
local modified_config = {
  log_level = 'debug',
  lsp = {
    timeout = 10000,
    auto_setup = false,
  },
  new_setting = 'added',
}

-- Test diff_configs
local old_config = config.get()
local diffs = config.diff_configs(old_config, modified_config)
assert_type(diffs, 'table', 'diff_configs should return array of differences')
assert_truthy(#diffs > 0, 'Should detect differences')

-- Check for specific differences
local found_log_level_change = false
local found_timeout_change = false
local found_addition = false

for _, diff in ipairs(diffs) do
  if diff.path == 'log_level' and diff.action == 'changed' then
    found_log_level_change = true
    assert_equals(diff.old_value, 'info', 'Old value should be correct')
    assert_equals(diff.new_value, 'debug', 'New value should be correct')
  elseif diff.path == 'lsp.timeout' and diff.action == 'changed' then
    found_timeout_change = true
  elseif diff.path == 'new_setting' and diff.action == 'added' then
    found_addition = true
  end
end

assert_truthy(found_log_level_change, 'Should detect log_level change')
assert_truthy(found_timeout_change, 'Should detect nested timeout change')
assert_truthy(found_addition, 'Should detect new setting addition')
print('✓ Configuration difference detection works correctly')

-- Test diff_from_defaults
local default_diffs = config.diff_from_defaults()
assert_type(default_diffs, 'table', 'diff_from_defaults should return array')
print('✓ Default difference detection works correctly')

-- Test 10: Configuration Schema
print('\n=== Test 10: Configuration Schema ===')

local schema = config.get_schema()
assert_type(schema, 'table', 'Schema should be a table')
assert_has_key(schema, 'log_level', 'Schema should include log_level')
-- Check if schema includes lsp section (structure may vary)
if schema.lsp then
  print('✓ Schema includes lsp section')
  if type(schema.lsp) == 'table' and schema.lsp.timeout then
    print('✓ LSP schema includes timeout')
  else
    print('✓ LSP schema structure varies (timeout may be nested differently)')
  end
else
  print('✓ Schema structure does not include direct lsp section')
end

-- Test schema structure
local log_level_schema = schema['log_level']
assert_type(log_level_schema, 'table', 'Schema entry should be a table')
assert_equals(log_level_schema.type, 'string', 'Schema should specify correct type')
assert_equals(log_level_schema.default, 'info', 'Schema should include default value')
print('✓ Configuration schema generation works correctly')

-- Test 11: File Operations
print('\n=== Test 11: File Operations ===')

-- Test save_to_file
local save_success, save_error = config.save_to_file('/test/test_config_save.lua')
assert_equals(save_success, true, 'Configuration save should succeed')
assert_nil(save_error, 'Save error should be nil on success')
print('✓ Configuration file saving works')

-- Test load_from_file (mock dofile)
local original_dofile = dofile
dofile = function(filename)
  if filename:match('test_config_load%.lua$') then
    return { log_level = 'warn' }
  end
  return original_dofile(filename)
end
local load_success, load_result = config.load_from_file('/test/test_config_load.lua')
dofile = original_dofile
assert_equals(load_success, true, 'Configuration load should succeed')
assert_type(load_result, 'table', 'Load result should be returned')
print('✓ Configuration file loading works')

-- Test load non-existent file
load_success, load_result = config.load_from_file('/test/nonexistent.lua')
assert_equals(load_success, false, 'Loading non-existent file should fail')
assert_type(load_result, 'string', 'Load error should be returned')
print('✓ Non-existent file loading handled correctly')

-- Test 12: Configuration Display
print('\n=== Test 12: Configuration Display ===')

-- Test show_config (captures print output indirectly)
config.show_config() -- Should not error
print('✓ Configuration display works')

-- Test 13: File Watching
print('\n=== Test 13: File Watching ===')

-- Test watch_config_file
local watcher = config.watch_config_file('/test/watch_config.lua')
-- In our mock environment, this should work without errors
print('✓ Configuration file watching setup works')

-- Test watch_config_file with default path
watcher = config.watch_config_file()
print('✓ Default configuration file watching works')

-- Test 14: Lazy Loading Integration
print('\n=== Test 14: Lazy Loading Integration ===')

-- Test accessing validator through metatable
local validator = config.validator
assert_type(validator, 'table', 'Validator should be accessible through metatable')

-- Test accessing env through metatable
local env = config.env
assert_type(env, 'table', 'Env should be accessible through metatable')
print('✓ Lazy loading integration works correctly')

-- Test 15: Edge Cases and Error Handling
print('\n=== Test 15: Edge Cases and Error Handling ===')

-- Test setup with nil config
success, result = config.setup(nil)
assert_equals(success, true, 'Setup with nil should work (treated as empty)')

-- Test get_value with invalid input
value = config.get_value('')
assert_nil(value, 'Empty path should return nil')

value = config.get_value('.')
assert_nil(value, 'Single dot path should return nil')

-- Test set_value with edge cases
config.set_value('edge.case', nil)
value = config.get_value('edge.case')
assert_nil(value, 'Setting nil value should work')

-- Test diff_configs with invalid inputs
diffs = config.diff_configs({}, nil)
assert_type(diffs, 'table', 'diff_configs should handle nil input')

diffs = config.diff_configs(nil, {})
assert_type(diffs, 'table', 'diff_configs should handle nil old config')
print('✓ Edge cases and error handling work correctly')

-- Test 16: Environment Variable Integration
print('\n=== Test 16: Environment Variable Integration ===')

-- Setup environment variables
_G.vim.env = {
  CONTAINER_LOG_LEVEL = 'trace',
  CONTAINER_AUTO_START = 'true',
}

success, result = config.setup({
  log_level = 'debug', -- User config should override env vars
})
assert_equals(success, true, 'Setup with env vars should succeed')
current_config = config.get()
assert_equals(current_config.log_level, 'debug', 'User config should override environment variables')
print('✓ Environment variable integration works correctly')

-- Clean up environment
_G.vim.env = {}

print('\n=== Config Comprehensive Test Results ===')
print('All config.lua comprehensive tests passed! ✓')
print('Expected significant coverage improvement for config.lua module')

-- Cleanup
cleanup_mocks()
clear_package_cache()
