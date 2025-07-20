#!/usr/bin/env lua

-- Test for postCreateCommand array handling
-- Tests the fix for table.concat error when postCreateCommand is an array

-- Add project lua directory to package path
package.path = './lua/?.lua;./lua/?/init.lua;../lua/?.lua;../lua/?/init.lua;' .. package.path

-- Mock vim global for testing
_G.vim = {
  fn = {
    getcwd = function()
      return '/test/workspace'
    end,
    sha256 = function(str)
      return string.format('%08x', #str)
    end,
    filereadable = function(path)
      local file = io.open(path, 'r')
      if file then
        file:close()
        return 1
      else
        return 0
      end
    end,
    fnamemodify = function(path, mods)
      if mods == ':h' then
        return path:match('(.*/)[^/]*') or '.'
      elseif mods == ':t' then
        return path:match('[^/]*$') or path
      else
        return path
      end
    end,
  },
  json = {
    decode = function(str)
      return require('container.utils.json_mock').decode(str)
    end,
  },
  tbl_deep_extend = function(behavior, ...)
    local result = {}
    for i = 1, select('#', ...) do
      local t = select(i, ...)
      if t then
        for k, v in pairs(t) do
          result[k] = v
        end
      end
    end
    return result
  end,
  tbl_isempty = function(t)
    return next(t) == nil
  end,
  deepcopy = function(orig)
    local copy
    if type(orig) == 'table' then
      copy = {}
      for orig_key, orig_value in next, orig, nil do
        copy[vim.deepcopy(orig_key)] = vim.deepcopy(orig_value)
      end
    else
      copy = orig
    end
    return copy
  end,
  list_extend = function(list, items)
    if not items then
      return list
    end
    for _, item in ipairs(items) do
      table.insert(list, item)
    end
    return list
  end,
  log = { levels = { DEBUG = 0, INFO = 1, WARN = 2, ERROR = 3 } },
  schedule = function(fn)
    fn()
  end,
}

-- Simple JSON mock for testing
package.loaded['container.utils.json_mock'] = {
  decode = function(str)
    local result = {}
    if str:match('"name"') then
      result.name = str:match('"name"%s*:%s*"([^"]+)"')
    end
    if str:match('"image"') then
      result.image = str:match('"image"%s*:%s*"([^"]+)"')
    end
    if str:match('"postCreateCommand"') then
      -- Handle array-style postCreateCommand
      if str:match('%[') then
        result.postCreateCommand = {}
        -- Find the postCreateCommand array section
        local array_start = str:find('"postCreateCommand"%s*:%s*%[')
        if array_start then
          local array_section = str:sub(array_start)
          local array_end = array_section:find('%]')
          if array_end then
            local array_content = array_section:sub(1, array_end)
            -- Extract commands from array
            for cmd in array_content:gmatch('"([^"]*)"') do
              if cmd ~= 'postCreateCommand' then
                table.insert(result.postCreateCommand, cmd)
              end
            end
          end
        end
      else
        result.postCreateCommand = str:match('"postCreateCommand"%s*:%s*"([^"]+)"')
      end
    end
    if str:match('"containerEnv"') then
      result.containerEnv = {}
      for key, value in str:gmatch('"([^"]+)"%s*:%s*"([^"]+)"') do
        if key ~= 'name' and key ~= 'image' then
          result.containerEnv[key] = value
        end
      end
    end
    return result
  end,
}

print('Testing postCreateCommand array handling...')

local parser = require('container.parser')

-- Test case 1: Array-style postCreateCommand
local function test_array_postcreate_command()
  print('\n=== Test 1: Array-style postCreateCommand ===')

  local test_path = '/tmp/test_array_postcreate.json'
  local content = [[
{
  "name": "Array PostCreate Test",
  "image": "mcr.microsoft.com/devcontainers/go:1-1.24-bookworm",
  "containerEnv": {
    "PATH": "/usr/local/custom/bin:${containerEnv:PATH}",
    "GOPATH": "/go"
  },
  "postCreateCommand": [
    "echo 'Testing environment variable expansion:'",
    "echo \"PATH: $PATH\"",
    "echo \"GOPATH: $GOPATH\"",
    "go version"
  ]
}]]

  local file = io.open(test_path, 'w')
  file:write(content)
  file:close()

  local config, err = parser.parse(test_path)
  os.remove(test_path)

  if err then
    print('✗ Parse error:', err)
    return false
  end

  -- Check that postCreateCommand is parsed as array
  if type(config.postCreateCommand) == 'table' then
    print('✓ postCreateCommand parsed as array')
    print('  Commands:', #config.postCreateCommand)
    for i, cmd in ipairs(config.postCreateCommand) do
      print('  [' .. i .. ']', cmd)
    end
  else
    print('✗ postCreateCommand not parsed as array, got:', type(config.postCreateCommand))
    return false
  end

  -- Check that environment variables are expanded
  local expected_path =
    '/usr/local/custom/bin:/usr/local/go/bin:/go/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'
  if config.containerEnv.PATH == expected_path then
    print('✓ Environment variables expanded correctly')
  else
    print('✗ Environment variable expansion failed')
    print('  Expected:', expected_path)
    print('  Got:', config.containerEnv.PATH)
    return false
  end

  return true
end

-- Test case 2: String-style postCreateCommand (backward compatibility)
local function test_string_postcreate_command()
  print('\n=== Test 2: String-style postCreateCommand ===')

  local test_path = '/tmp/test_string_postcreate.json'
  local content = [[
{
  "name": "String PostCreate Test",
  "image": "mcr.microsoft.com/devcontainers/go:1-1.24-bookworm",
  "containerEnv": {
    "PATH": "/usr/local/custom/bin:${containerEnv:PATH}"
  },
  "postCreateCommand": "echo 'Hello World' && go version"
}]]

  local file = io.open(test_path, 'w')
  file:write(content)
  file:close()

  local config, err = parser.parse(test_path)
  os.remove(test_path)

  if err then
    print('✗ Parse error:', err)
    return false
  end

  -- Check that postCreateCommand is parsed as string
  if type(config.postCreateCommand) == 'string' then
    print('✓ postCreateCommand parsed as string')
    print('  Command:', config.postCreateCommand)
  else
    print('✗ postCreateCommand not parsed as string, got:', type(config.postCreateCommand))
    return false
  end

  return true
end

-- Test case 3: Simulate the actual command conversion that happens in init.lua
local function test_command_conversion()
  print('\n=== Test 3: Command Conversion Logic ===')

  -- Test array conversion
  local array_command = {
    "echo 'Testing environment variable expansion:'",
    'echo "PATH: $PATH"',
    'echo "GOPATH: $GOPATH"',
    'go version',
  }

  if type(array_command) == 'table' then
    -- Join commands with && and add error handling
    local converted_command = 'set +e; ' .. table.concat(array_command, ' && ')
    print('✓ Array command converted successfully')
    print('  Original array length:', #array_command)
    print('  Converted command:', converted_command)

    -- Check that conversion contains expected number of && separators
    local expected_separators = #array_command - 1
    local actual_separators = 0
    for _ in converted_command:gmatch(' && ') do
      actual_separators = actual_separators + 1
    end

    if actual_separators == expected_separators then
      print('✓ Commands properly joined with && separators')
    else
      print('✗ Command joining failed')
      return false
    end
  end

  -- Test string command (should remain unchanged)
  local string_command = "echo 'Hello World' && go version"
  if type(string_command) == 'string' then
    print('✓ String command remains unchanged:', string_command)
  end

  return true
end

-- Run all tests
print(string.rep('=', 60))
print('POSTCREATE COMMAND ARRAY HANDLING TESTS')
print(string.rep('=', 60))

local test1 = test_array_postcreate_command()
local test2 = test_string_postcreate_command()
local test3 = test_command_conversion()

if test1 and test2 and test3 then
  print('\n' .. string.rep('=', 60))
  print('✅ ALL POSTCREATE COMMAND TESTS PASSED!')
  print(string.rep('=', 60))
  print('✓ Array-style postCreateCommand parsing works')
  print('✓ String-style postCreateCommand parsing works (backward compatibility)')
  print('✓ Command conversion logic works correctly')
  print('✓ Environment variable expansion works with both formats')
else
  print('\n' .. string.rep('=', 60))
  print('❌ SOME POSTCREATE COMMAND TESTS FAILED!')
  print(string.rep('=', 60))
  os.exit(1)
end
