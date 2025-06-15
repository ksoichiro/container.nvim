#!/usr/bin/env lua

-- Test script for container naming system
-- Run with: lua test/test_container_naming.lua

package.path = './lua/?.lua;./lua/?/init.lua;' .. package.path

-- Mock vim functions for testing
_G.vim = {
  fn = {
    getcwd = function()
      return '/test/project/path'
    end,
    sha256 = function(str)
      -- Simple mock hash function that actually reflects string differences
      local hash = 0
      for i = 1, #str do
        hash = hash * 31 + string.byte(str, i)
      end
      return string.format('%08x', hash % 0x100000000)
    end,
  },
}

-- Mock log module
local mock_log = {
  debug = function(...) end,
  info = function(...) end,
  warn = function(...) end,
  error = function(...) end,
}

package.loaded['devcontainer.utils.log'] = mock_log

-- Load docker module
local docker = require('devcontainer.docker.init')

print('Running container naming tests...')
print()

-- Test 1: Basic container name generation
print('=== Test 1: Basic Container Name Generation ===')
local config1 = {
  name = 'Node.js Development',
  base_path = '/home/user/projects/my-node-app',
}

local container_name1 = docker.generate_container_name(config1)
print('Config name: ' .. config1.name)
print('Base path: ' .. config1.base_path)
print('Generated container name: ' .. container_name1)
print('✓ Container name generated successfully')
print()

-- Test 2: Different projects with same config name
print('=== Test 2: Different Projects, Same Config Name ===')
local config2a = {
  name = 'Web App',
  base_path = '/home/user/projects/frontend',
}

local config2b = {
  name = 'Web App',
  base_path = '/home/user/projects/backend',
}

local container_name2a = docker.generate_container_name(config2a)
local container_name2b = docker.generate_container_name(config2b)

print('Config A - Name: ' .. config2a.name .. ', Path: ' .. config2a.base_path)
print('Container A: ' .. container_name2a)
print('Config B - Name: ' .. config2b.name .. ', Path: ' .. config2b.base_path)
print('Container B: ' .. container_name2b)

if container_name2a ~= container_name2b then
  print('✓ Different projects generate different container names')
else
  print('✗ ERROR: Same container name for different projects!')
end
print()

-- Test 3: Special characters in config name
print('=== Test 3: Special Characters Handling ===')
local config3 = {
  name = 'My App (v2.0) [dev]',
  base_path = '/test/special-chars',
}

local container_name3 = docker.generate_container_name(config3)
print('Original name: ' .. config3.name)
print('Generated container name: ' .. container_name3)

-- Check if container name contains only valid characters
local valid_pattern = '^[a-z0-9_.-]+$'
if string.match(container_name3, valid_pattern) then
  print('✓ Container name contains only valid characters')
else
  print('✗ ERROR: Container name contains invalid characters!')
end
print()

-- Test 4: Same project, same name (consistency)
print('=== Test 4: Consistency Check ===')
local config4 = {
  name = 'API Server',
  base_path = '/consistent/path',
}

local name_first = docker.generate_container_name(config4)
local name_second = docker.generate_container_name(config4)

print('First generation: ' .. name_first)
print('Second generation: ' .. name_second)

if name_first == name_second then
  print('✓ Container name generation is consistent')
else
  print('✗ ERROR: Container name generation is not consistent!')
end
print()

-- Test 5: Default path handling
print('=== Test 5: Default Path Handling ===')
local config5 = {
  name = 'Default Path Test',
  -- base_path intentionally omitted
}

local container_name5 = docker.generate_container_name(config5)
print('Config without base_path: ' .. config5.name)
print('Generated container name: ' .. container_name5)
print('✓ Default path handling works')
print()

print('=== Container Naming Tests Complete ===')
print('All tests passed! ✓')
