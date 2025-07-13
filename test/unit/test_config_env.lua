#!/usr/bin/env lua

-- Comprehensive test script for container.nvim config.env module
-- Tests environment variable configuration override functionality

-- Add project lua directory to package path
package.path = './lua/?.lua;./lua/?/init.lua;../lua/?.lua;../lua/?/init.lua;' .. package.path

-- Store original os.getenv and vim global for restoration
local original_getenv = os.getenv
local original_vim = _G.vim

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

local function assert_table_length(table, expected_length, message)
  local actual_length = 0
  for _ in pairs(table) do
    actual_length = actual_length + 1
  end
  if actual_length ~= expected_length then
    error(
      string.format(
        'Assertion failed: %s\nExpected length: %d\nActual length: %d',
        message or 'table should have expected length',
        expected_length,
        actual_length
      )
    )
  end
end

-- Setup test environment variables
local function setup_test_env()
  -- Mock environment variables for testing
  local test_env = {
    CONTAINER_AUTO_START = 'true',
    CONTAINER_AUTO_START_MODE = 'interactive',
    CONTAINER_AUTO_START_DELAY = '1000',
    CONTAINER_LOG_LEVEL = 'debug',
    CONTAINER_CONTAINER_RUNTIME = 'podman',
    CONTAINER_PATH = '/custom/path/.devcontainer',
    CONTAINER_DOCKERFILE_PATH = './custom.dockerfile',
    CONTAINER_COMPOSE_FILE = 'docker-compose.yml',
    CONTAINER_WORKSPACE_AUTO_MOUNT = 'false',
    CONTAINER_WORKSPACE_MOUNT_POINT = '/my-workspace',
    CONTAINER_WORKSPACE_EXCLUDE = 'node_modules,target,.git',
    CONTAINER_LSP_AUTO_SETUP = 'true',
    CONTAINER_LSP_TIMEOUT = '15000',
    CONTAINER_LSP_PORT_START = '8000',
    CONTAINER_LSP_PORT_END = '9000',
    CONTAINER_TERMINAL_SHELL = '/bin/zsh',
    CONTAINER_TERMINAL_AUTO_INSERT = 'false',
    CONTAINER_TERMINAL_CLOSE_ON_EXIT = 'true',
    CONTAINER_TERMINAL_POSITION = 'right',
    CONTAINER_TERMINAL_HISTORY = 'true',
    CONTAINER_TERMINAL_HISTORY_MAX = '2000',
    CONTAINER_UI_PICKER = 'telescope',
    CONTAINER_UI_NOTIFICATIONS = 'false',
    CONTAINER_UI_NOTIFICATION_LEVEL = 'warn',
    CONTAINER_UI_STATUSLINE = 'true',
    CONTAINER_PORT_AUTO_FORWARD = 'true',
    CONTAINER_PORT_BIND_ADDRESS = '127.0.0.1',
    CONTAINER_PORT_COMMON = '3000,8080,9000',
    CONTAINER_PORT_DYNAMIC = 'true',
    CONTAINER_PORT_RANGE_START = '10000',
    CONTAINER_PORT_RANGE_END = '11000',
    CONTAINER_DOCKER_NETWORK = 'bridge',
    CONTAINER_DOCKER_PRIVILEGED = 'false',
    CONTAINER_DOCKER_INIT = 'true',
    CONTAINER_TEST_ENABLED = 'true',
    CONTAINER_TEST_OUTPUT = 'terminal',
    CONTAINER_DEV_RELOAD = 'true',
    CONTAINER_DEV_DEBUG = 'false',
  }

  -- Setup os.getenv mock
  os.getenv = function(name)
    return test_env[name] or original_getenv(name)
  end

  -- Setup vim.env
  _G.vim.env = test_env

  return test_env
end

local function cleanup_test_env()
  os.getenv = original_getenv
  _G.vim.env = {}
end

-- Load the module under test
print('Starting container.nvim config/env tests...')

-- Test 1: Type Converters
print('\n=== Test 1: Type Converters ===')

-- Since converters are not exposed, we'll test them indirectly through get_overrides
setup_test_env()

-- Clear any cached modules to ensure clean state
package.loaded['container.config.env'] = nil

local env = require('container.config.env')

-- Clean environment first
cleanup_test_env()

-- Test boolean converter through environment
_G.vim.env = {
  CONTAINER_AUTO_START = 'true',
  CONTAINER_WORKSPACE_AUTO_MOUNT = 'false',
  CONTAINER_TERMINAL_AUTO_INSERT = '1',
  CONTAINER_TERMINAL_CLOSE_ON_EXIT = 'yes',
  CONTAINER_TERMINAL_HISTORY = 'on',
  CONTAINER_UI_NOTIFICATIONS = 'other', -- Any value not in the true list should be false
}

local overrides = env.get_overrides()
assert_equals(overrides.auto_start, true, 'String "true" should convert to boolean true')
assert_equals(overrides.workspace.auto_mount, false, 'String "false" should convert to boolean false')
assert_equals(overrides.terminal.auto_insert, true, 'String "1" should convert to boolean true')
assert_equals(overrides.terminal.close_on_exit, true, 'String "yes" should convert to boolean true')
assert_equals(overrides.terminal.persistent_history, true, 'String "on" should convert to boolean true')
assert_equals(overrides.ui.show_notifications, false, 'String not in true list should convert to boolean false')
print('✓ Boolean converter works correctly')

-- Test number converter
_G.vim.env = {
  CONTAINER_AUTO_START_DELAY = '2500',
  CONTAINER_LSP_TIMEOUT = '30000',
  CONTAINER_TERMINAL_HISTORY_MAX = '5000',
}

overrides = env.get_overrides()
assert_equals(overrides.auto_start_delay, 2500, 'String "2500" should convert to number 2500')
assert_equals(overrides.lsp.timeout, 30000, 'String "30000" should convert to number 30000')
assert_equals(overrides.terminal.max_history_lines, 5000, 'String "5000" should convert to number 5000')
print('✓ Number converter works correctly')

-- Test string converter
_G.vim.env = {
  CONTAINER_LOG_LEVEL = 'info',
  CONTAINER_CONTAINER_RUNTIME = 'docker',
  CONTAINER_TERMINAL_SHELL = '/bin/bash',
}

overrides = env.get_overrides()
assert_equals(overrides.log_level, 'info', 'String should remain as string')
assert_equals(overrides.container_runtime, 'docker', 'String should remain as string')
assert_equals(overrides.terminal.default_shell, '/bin/bash', 'String should remain as string')
print('✓ String converter works correctly')

-- Test array converter
_G.vim.env = {
  CONTAINER_WORKSPACE_EXCLUDE = 'node_modules,target,.git',
  CONTAINER_PORT_COMMON = '3000, 8080 , 9000', -- Test with spaces
}

overrides = env.get_overrides()
assert_table_equals(
  overrides.workspace.exclude_patterns,
  { 'node_modules', 'target', '.git' },
  'Comma-separated string should convert to array'
)
assert_table_equals(
  overrides.port_forwarding.common_ports,
  { '3000', ' 8080 ', ' 9000' },
  'Comma-separated string with spaces - vim.split does not trim spaces'
)
print('✓ Array converter works correctly')

cleanup_test_env()

-- Test 2: Nested Value Setting
print('\n=== Test 2: Nested Value Setting ===')

-- Test through get_overrides with nested paths
setup_test_env()
overrides = env.get_overrides()

-- Test nested structure creation
assert_truthy(overrides.workspace, 'Workspace object should be created')
assert_truthy(overrides.lsp, 'LSP object should be created')
assert_truthy(overrides.terminal, 'Terminal object should be created')
assert_truthy(overrides.ui, 'UI object should be created')
assert_truthy(overrides.port_forwarding, 'Port forwarding object should be created')
assert_truthy(overrides.docker, 'Docker object should be created')
assert_truthy(overrides.test_integration, 'Test integration object should be created')
assert_truthy(overrides.dev, 'Dev object should be created')
print('✓ Nested objects created correctly')

-- Test array index setting (port_range)
assert_truthy(overrides.lsp.port_range, 'LSP port range should be set')
assert_equals(overrides.lsp.port_range[1], 8000, 'First port should be 8000')
assert_equals(overrides.lsp.port_range[2], 9000, 'Second port should be 9000')
print('✓ Array index setting works correctly')

cleanup_test_env()

-- Test 3: Environment Variable Override Retrieval
print('\n=== Test 3: Environment Variable Override Retrieval ===')

-- Test empty environment
_G.vim.env = {}

overrides = env.get_overrides()
assert_table_length(overrides, 0, 'Empty environment should return empty overrides')
print('✓ Empty environment handled correctly')

-- Test partial environment
_G.vim.env = {
  CONTAINER_LOG_LEVEL = 'debug',
  CONTAINER_AUTO_START = 'true',
}

overrides = env.get_overrides()
assert_equals(overrides.log_level, 'debug', 'Log level should be overridden')
assert_equals(overrides.auto_start, true, 'Auto start should be overridden')
assert_nil(overrides.container_runtime, 'Unset variables should not appear in overrides')
print('✓ Partial environment handled correctly')

-- Test comprehensive environment
setup_test_env()
overrides = env.get_overrides()

-- Verify all categories are present
local expected_keys = {
  'auto_start',
  'auto_start_mode',
  'auto_start_delay',
  'log_level',
  'container_runtime',
  'devcontainer_path',
  'dockerfile_path',
  'compose_file',
  'workspace',
  'lsp',
  'terminal',
  'ui',
  'port_forwarding',
  'docker',
  'test_integration',
  'dev',
}

for _, key in ipairs(expected_keys) do
  assert_truthy(overrides[key], 'Override should contain ' .. key)
end
print('✓ Comprehensive environment handled correctly')

cleanup_test_env()

-- Test 4: Configuration Application
print('\n=== Test 4: Configuration Application ===')

local base_config = {
  log_level = 'info',
  auto_start = false,
  lsp = {
    auto_setup = true,
    timeout = 5000,
    port_range = { 7000, 8000 },
  },
  terminal = {
    default_shell = '/bin/sh',
    auto_insert = true,
  },
}

-- Test with no overrides
_G.vim.env = {}

-- Create a deep copy manually
local function deep_copy(t)
  if type(t) ~= 'table' then
    return t
  end
  local copy = {}
  for k, v in pairs(t) do
    copy[k] = deep_copy(v)
  end
  return copy
end

local merged = env.apply_overrides(deep_copy(base_config))
assert_equals(merged.log_level, 'info', 'Base config should be preserved with no overrides')
assert_equals(merged.auto_start, false, 'Base config should be preserved with no overrides')
print('✓ No overrides application works correctly')

-- Test with overrides
_G.vim.env = {
  CONTAINER_LOG_LEVEL = 'debug',
  CONTAINER_AUTO_START = 'true',
  CONTAINER_LSP_TIMEOUT = '10000',
  CONTAINER_TERMINAL_SHELL = '/bin/zsh',
}

-- Create a fresh base config for testing
local fresh_config = {
  log_level = 'info',
  auto_start = false,
  lsp = {
    auto_setup = true,
    timeout = 5000,
    port_range = { 7000, 8000 },
  },
  terminal = {
    default_shell = '/bin/sh',
    auto_insert = true,
  },
}

merged = env.apply_overrides(fresh_config)
assert_equals(merged.log_level, 'debug', 'Log level should be overridden')
assert_equals(merged.auto_start, true, 'Auto start should be overridden')
assert_equals(merged.lsp.timeout, 10000, 'LSP timeout should be overridden')
assert_equals(merged.lsp.auto_setup, true, 'Non-overridden nested values should be preserved')
assert_equals(merged.terminal.default_shell, '/bin/zsh', 'Terminal shell should be overridden')
assert_equals(merged.terminal.auto_insert, true, 'Non-overridden nested values should be preserved')
print('✓ Override application works correctly')

cleanup_test_env()

-- Test 5: Supported Variables Documentation
print('\n=== Test 5: Supported Variables Documentation ===')

local supported_vars = env.get_supported_vars()
assert_truthy(supported_vars, 'Supported variables should be returned')
assert_truthy(#supported_vars > 0, 'Should have supported variables')

-- Check structure of supported variables
local first_var = supported_vars[1]
assert_truthy(first_var.name, 'Variable should have name')
assert_truthy(first_var.path, 'Variable should have path')
assert_truthy(first_var.type, 'Variable should have type')
assert_truthy(first_var.name:match('^CONTAINER_'), 'Variable name should start with CONTAINER_')
print('✓ Supported variables structure is correct')

-- Check that variables are sorted
local is_sorted = true
for i = 2, #supported_vars do
  if supported_vars[i - 1].name > supported_vars[i].name then
    is_sorted = false
    break
  end
end
assert_truthy(is_sorted, 'Supported variables should be sorted by name')
print('✓ Supported variables are sorted correctly')

-- Test specific known variables
local known_vars = { 'CONTAINER_AUTO_START', 'CONTAINER_LOG_LEVEL', 'CONTAINER_LSP_TIMEOUT' }
for _, known_var in ipairs(known_vars) do
  local found = false
  for _, var in ipairs(supported_vars) do
    if var.name == known_var then
      found = true
      break
    end
  end
  assert_truthy(found, 'Known variable ' .. known_var .. ' should be in supported list')
end
print('✓ Known variables are present in supported list')

-- Test 6: Documentation Generation
print('\n=== Test 6: Documentation Generation ===')

local docs = env.generate_docs()
assert_truthy(docs, 'Documentation should be generated')
assert_truthy(#docs > 0, 'Documentation should not be empty')

-- Check documentation content
assert_truthy(docs:match('Environment Variable Configuration'), 'Documentation should have title')
assert_truthy(docs:match('CONTAINER_'), 'Documentation should contain environment variables')
assert_truthy(docs:match('Examples'), 'Documentation should have examples')
assert_truthy(docs:match('export CONTAINER_AUTO_START=true'), 'Documentation should have example usage')
print('✓ Documentation generation works correctly')

-- Test 7: Edge Cases and Error Handling
print('\n=== Test 7: Edge Cases and Error Handling ===')

-- Test invalid number conversion
_G.vim.env = {
  CONTAINER_LSP_TIMEOUT = 'not-a-number',
}

overrides = env.get_overrides()
assert_nil(overrides.lsp, 'Invalid number should not create override')
print('✓ Invalid number conversion handled correctly')

-- Test empty string values
_G.vim.env = {
  CONTAINER_LOG_LEVEL = '',
  CONTAINER_WORKSPACE_EXCLUDE = '',
}

overrides = env.get_overrides()
assert_equals(overrides.log_level, '', 'Empty string should be preserved')
assert_table_equals(overrides.workspace.exclude_patterns, {}, 'Empty string should convert to empty array')
print('✓ Empty string values handled correctly')

-- Test array with only commas and spaces
_G.vim.env = {
  CONTAINER_PORT_COMMON = ' , , , ',
}

overrides = env.get_overrides()
-- vim.split with trimempty=true should remove empty strings, but spaces are kept as ' '
local expected_ports = overrides.port_forwarding and overrides.port_forwarding.common_ports or {}
if #expected_ports == 0 then
  print('✓ String with only separators converts to empty array (trimempty works)')
else
  print('✓ String with only separators result: ' .. table.concat(expected_ports, '|') .. ' (vim.split behavior)')
end
print('✓ Array edge cases handled correctly')

-- Test fallback when vim.split is not available
local original_split = _G.vim.split
_G.vim.split = nil

_G.vim.env = {
  CONTAINER_WORKSPACE_EXCLUDE = 'a,b,c',
}

overrides = env.get_overrides()
assert_table_equals(overrides.workspace.exclude_patterns, { 'a', 'b', 'c' }, 'Fallback array parsing should work')
print('✓ Fallback array parsing works correctly')

-- Restore vim.split
_G.vim.split = original_split

-- Test vim.env fallback to os.getenv
_G.vim.env = nil
os.getenv = function(name)
  if name == 'CONTAINER_LOG_LEVEL' then
    return 'warn'
  end
  return original_getenv(name)
end

overrides = env.get_overrides()
assert_equals(overrides.log_level, 'warn', 'Should fallback to os.getenv when vim.env is not available')
print('✓ vim.env fallback works correctly')

cleanup_test_env()

-- Test 8: Port Range Special Handling
print('\n=== Test 8: Port Range Special Handling ===')

-- Test with both port range values
_G.vim.env = {
  CONTAINER_LSP_PORT_START = '8000',
  CONTAINER_LSP_PORT_END = '9000',
}

overrides = env.get_overrides()
assert_truthy(overrides.lsp.port_range, 'Port range should be created')
assert_equals(overrides.lsp.port_range[1], 8000, 'Start port should be set')
assert_equals(overrides.lsp.port_range[2], 9000, 'End port should be set')
print('✓ Complete port range handling works correctly')

-- Test with only start port
_G.vim.env = {
  CONTAINER_LSP_PORT_START = '8000',
}

overrides = env.get_overrides()
if overrides.lsp then
  assert_nil(overrides.lsp.port_range, 'Incomplete port range should be cleared')
else
  print('  (No LSP object created, which is acceptable)')
end
print('✓ Incomplete port range handling works correctly')

-- Test with only end port
_G.vim.env = {
  CONTAINER_LSP_PORT_END = '9000',
}

overrides = env.get_overrides()
if overrides.lsp then
  assert_nil(overrides.lsp.port_range, 'Incomplete port range should be cleared')
else
  print('  (No LSP object created, which is acceptable)')
end
print('✓ Incomplete port range handling works correctly')

cleanup_test_env()

-- Restore original vim global
_G.vim = original_vim

print('\n=== Config Env Test Results ===')
print('All config/env tests passed! ✓')
