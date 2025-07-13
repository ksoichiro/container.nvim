#!/usr/bin/env lua

-- Parser module test script
-- Tests devcontainer.json parsing functionality

-- Add project lua directory to package path
package.path = './lua/?.lua;./lua/?/init.lua;../lua/?.lua;../lua/?/init.lua;' .. package.path

-- Mock vim global for testing
_G.vim = {
  fn = {
    getcwd = function()
      return '/test/workspace'
    end,
    fnamemodify = function(path, modifier)
      if modifier == ':h' then
        return path:match('(.*/)')
      elseif modifier == ':t' then
        return path:match('.*/(.*)') or path
      elseif modifier == ':h:h' then
        local dir = path:match('(.*/)')
        if dir then
          return dir:match('(.*/)')
        end
        return path
      end
      return path
    end,
    tempname = function()
      return '/tmp/test_' .. os.time()
    end,
    mkdir = function(path, mode)
      return true
    end,
    writefile = function(lines, path)
      return true
    end,
    isdirectory = function(path)
      return 1
    end,
    delete = function(path, flags)
      return true
    end,
    readdir = function(path)
      return {}
    end,
    resolve = function(path)
      return path
    end,
    sha256 = function(str)
      return string.format('%08x', str:len() * 12345) -- Simple mock hash
    end,
  },
  json = {
    decode = function(str)
      -- Simple JSON parser for tests
      if str == '{}' then
        return {}
      end
      if str == '[]' then
        return {}
      end

      -- Handle basic JSON objects for testing
      if str:match('"name":%s*"([^"]+)"') then
        local name = str:match('"name":%s*"([^"]+)"')
        local image = str:match('"image":%s*"([^"]+)"')
        local result = { name = name }
        if image then
          result.image = image
        end

        -- Parse forwardPorts array
        local ports_str = str:match('"forwardPorts":%s*%[([^%]]+)%]')
        if ports_str then
          result.forwardPorts = {}
          for port in ports_str:gmatch('%d+') do
            table.insert(result.forwardPorts, tonumber(port))
          end
          -- Handle string port mappings
          for mapping in ports_str:gmatch('"([^"]+)"') do
            table.insert(result.forwardPorts, mapping)
          end
        end

        -- Parse workspaceFolder
        local workspace = str:match('"workspaceFolder":%s*"([^"]+)"')
        if workspace then
          result.workspaceFolder = workspace
        end

        -- Parse remoteUser
        local user = str:match('"remoteUser":%s*"([^"]+)"')
        if user then
          result.remoteUser = user
        end

        return result
      end

      return {}
    end,
  },
  log = {
    levels = {
      DEBUG = 1,
      INFO = 2,
      WARN = 3,
      ERROR = 4,
    },
  },
  notify = function(msg, level)
    print('[NOTIFY] ' .. tostring(msg))
  end,
  tbl_deep_extend = function(behavior, ...)
    local result = {}
    local sources = { ... }
    for _, source in ipairs(sources) do
      if type(source) == 'table' then
        for k, v in pairs(source) do
          result[k] = v
        end
      end
    end
    return result
  end,
}

-- Mock os.getenv for variable expansion tests
local original_getenv = os.getenv
os.getenv = function(var)
  if var == 'HOME' then
    return '/home/testuser'
  end
  return original_getenv(var)
end

print('Starting container.nvim parser tests...')

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
        'Assertion failed: %s\nValues should not be equal: %s',
        message or 'values should not be equal',
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

local function assert_nil(value, message)
  if value ~= nil then
    error(
      string.format('Assertion failed: %s\nExpected nil, got: %s', message or 'value should be nil', tostring(value))
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

local function assert_table_length(table, expected_length, message)
  local actual_length = #table
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

-- Load parser module
local parser = require('container.parser')

-- Test 1: generate_project_id function
print('\n=== Test 1: Project ID Generation ===')

local id1 = parser.generate_project_id('/test/project')
local id2 = parser.generate_project_id('/test/project')
assert_equals(id1, id2, 'Project IDs should be consistent')
print('✓ Project ID generation is consistent')

local id3 = parser.generate_project_id('/test/different-project')
assert_not_equals(id1, id3, 'Different paths should generate different IDs')
print('✓ Different paths generate different IDs')

local id4 = parser.generate_project_id('/test/my-project')
assert_truthy(id4:match('my%-project'), 'Project ID should contain project name')
print('✓ Project ID contains project name')

local id5 = parser.generate_project_id('/test/project with spaces & symbols!')
assert_truthy(id5 and #id5 > 0, 'Should handle special characters in path')
print('✓ Special characters in path handled')

-- Test 2: normalize_ports function
print('\n=== Test 2: Port Normalization ===')

-- Test empty ports
local normalized, deprecated = parser.normalize_ports(nil)
assert_table_length(normalized, 0, 'Empty ports should return empty table')
assert_table_length(deprecated, 0, 'No deprecated ports for empty input')
print('✓ Empty ports handled correctly')

-- Test numeric ports
local ports = { 3000, 8080 }
normalized, deprecated = parser.normalize_ports(ports)
assert_table_length(normalized, 2, 'Should normalize 2 numeric ports')
assert_table_length(deprecated, 0, 'No deprecated ports for numeric input')
assert_equals(normalized[1].type, 'fixed', 'Numeric port should be fixed type')
assert_equals(normalized[1].host_port, 3000, 'Host port should match input')
assert_equals(normalized[1].container_port, 3000, 'Container port should match input')
print('✓ Numeric ports normalized correctly')

-- Test string port mappings
local ports2 = { '8080:3000', '9090:80' }
normalized, deprecated = parser.normalize_ports(ports2)
assert_table_length(normalized, 2, 'Should normalize 2 string port mappings')
assert_equals(normalized[1].host_port, 8080, 'Host port should be parsed correctly')
assert_equals(normalized[1].container_port, 3000, 'Container port should be parsed correctly')
print('✓ String port mappings normalized correctly')

-- Test auto port allocation
local ports3 = { 'auto:3000', 'auto:8080' }
normalized, deprecated = parser.normalize_ports(ports3)
assert_table_length(normalized, 2, 'Should normalize 2 auto ports')
assert_table_length(deprecated, 2, 'Auto ports should be marked as deprecated')
assert_equals(normalized[1].type, 'auto', 'Auto port should have correct type')
assert_equals(normalized[1].container_port, 3000, 'Container port should be parsed')
assert_nil(normalized[1].host_port, 'Auto port should not have host port yet')
print('✓ Auto port allocation handled correctly')

-- Test range port allocation
local ports4 = { 'range:8000-8010:3000' }
normalized, deprecated = parser.normalize_ports(ports4)
assert_table_length(normalized, 1, 'Should normalize 1 range port')
assert_table_length(deprecated, 1, 'Range port should be marked as deprecated')
assert_equals(normalized[1].type, 'range', 'Range port should have correct type')
assert_equals(normalized[1].range_start, 8000, 'Range start should be parsed')
assert_equals(normalized[1].range_end, 8010, 'Range end should be parsed')
assert_equals(normalized[1].container_port, 3000, 'Container port should be parsed')
print('✓ Range port allocation handled correctly')

-- Test object port format
local ports5 = {
  { containerPort = 3000, hostPort = 8080, protocol = 'tcp' },
  { containerPort = 9000 },
}
normalized, deprecated = parser.normalize_ports(ports5)
assert_table_length(normalized, 2, 'Should normalize 2 object ports')
assert_equals(normalized[1].host_port, 8080, 'Object host port should be parsed')
assert_equals(normalized[1].container_port, 3000, 'Object container port should be parsed')
assert_equals(normalized[1].protocol, 'tcp', 'Object protocol should be parsed')
assert_equals(normalized[2].host_port, 9000, 'Missing host port should default to container port')
print('✓ Object port format handled correctly')

-- Test 3: Mock configuration parsing
print('\n=== Test 3: Configuration Parsing Mock ===')

-- Create a mock devcontainer.json content
local mock_config = {
  name = 'Test Container',
  image = 'ubuntu:20.04',
  workspaceFolder = '/workspace',
  remoteUser = 'vscode',
  forwardPorts = { 3000, '8080:80' },
}

-- Test that parser.normalize_for_plugin works with mock config
local normalized_config = parser.normalize_for_plugin(mock_config)
assert_equals(normalized_config.name, 'Test Container', 'Name should be preserved')
assert_equals(normalized_config.image, 'ubuntu:20.04', 'Image should be preserved')
assert_equals(normalized_config.workspace_folder, '/workspace', 'Workspace folder should be normalized')
assert_equals(normalized_config.remote_user, 'vscode', 'Remote user should be normalized')
print('✓ Configuration normalization works correctly')

-- Test default values
local minimal_config = { image = 'ubuntu' }
local normalized_minimal = parser.normalize_for_plugin(minimal_config)
assert_equals(normalized_minimal.name, 'devcontainer', 'Should use default name')
assert_equals(normalized_minimal.workspace_folder, '/workspace', 'Should use default workspace')
assert_table_length(normalized_minimal.environment, 0, 'Should have empty environment by default')
assert_table_length(normalized_minimal.ports, 0, 'Should have empty ports by default')
print('✓ Default values set correctly')

-- Test 4: Validation
print('\n=== Test 4: Configuration Validation ===')

local valid_config = {
  name = 'test',
  image = 'ubuntu',
  normalized_ports = {
    { type = 'fixed', host_port = 8080, container_port = 3000, protocol = 'tcp' },
  },
  normalized_mounts = {
    { type = 'bind', source = '/host', target = '/container' },
  },
}

local errors = parser.validate(valid_config)
assert_table_length(errors, 0, 'Valid configuration should have no errors')
print('✓ Valid configuration passes validation')

local invalid_config = {
  image = 'ubuntu', -- Missing name
}

local errors2 = parser.validate(invalid_config)
assert_truthy(#errors2 > 0, 'Invalid configuration should have errors')
print('✓ Invalid configuration caught by validation')

local no_image_config = {
  name = 'test', -- Missing image, dockerfile, or compose
}

local errors3 = parser.validate(no_image_config)
assert_truthy(#errors3 > 0, 'Configuration without image source should have errors')
print('✓ Missing image source caught by validation')

-- Test 5: Merge with plugin config
print('\n=== Test 5: Plugin Configuration Merge ===')

local devcontainer_config = { name = 'test' }
local plugin_config = {
  container_runtime = 'podman',
  log_level = 'debug',
}

local merged = parser.merge_with_plugin_config(devcontainer_config, plugin_config)
assert_equals(merged.container_runtime, 'podman', 'Container runtime should be merged')
assert_equals(merged.log_level, 'debug', 'Log level should be merged')
assert_table_contains(merged, 'plugin_config', 'Plugin config should be attached')
print('✓ Plugin configuration merged successfully')

print('\n=== Parser Test Results ===')
print('All parser tests passed! ✓')
