#!/usr/bin/env lua

-- Test for environment variable expansion implementation - edge cases
-- Tests additional scenarios for ${containerEnv:PATH} expansion

-- Add project lua directory to package path
package.path = './lua/?.lua;./lua/?/init.lua;../lua/?.lua;../lua/?/init.lua;' .. package.path

-- Mock vim global for testing (simplified version from test_basic.lua)
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

print('Starting environment variable expansion edge case tests...')

local parser = require('container.parser')

-- Test case 1: Multiple nested expansions
local function test_multiple_expansions()
  print('\n=== Test 1: Multiple Environment Variable Expansions ===')

  local test_path = '/tmp/test_multiple_expansions.json'
  local content = [[
{
  "name": "Multiple Expansion Test",
  "image": "test:latest",
  "containerEnv": {
    "PATH": "/bin1:${containerEnv:PATH}:/bin2",
    "HOME": "${containerEnv:HOME}/extra",
    "MIXED": "pre-${containerEnv:USER}-post",
    "MULTIPLE": "${containerEnv:HOME}:${containerEnv:SHELL}"
  }
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

  -- Test PATH with multiple paths
  local expected_path =
    '/bin1:/usr/local/go/bin:/go/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/bin2'
  if config.containerEnv.PATH == expected_path then
    print('✓ Multiple PATH expansion:', config.containerEnv.PATH)
  else
    print('✗ Multiple PATH failed. Expected:', expected_path)
    print('  Got:', config.containerEnv.PATH)
    return false
  end

  -- Test HOME extension
  if config.containerEnv.HOME == '/root/extra' then
    print('✓ HOME extension:', config.containerEnv.HOME)
  else
    print('✗ HOME extension failed:', config.containerEnv.HOME)
    return false
  end

  -- Test mixed expansion
  if config.containerEnv.MIXED == 'pre-root-post' then
    print('✓ Mixed expansion:', config.containerEnv.MIXED)
  else
    print('✗ Mixed expansion failed:', config.containerEnv.MIXED)
    return false
  end

  -- Test multiple variables in one value
  if config.containerEnv.MULTIPLE == '/root:/bin/sh' then
    print('✓ Multiple variables:', config.containerEnv.MULTIPLE)
  else
    print('✗ Multiple variables failed:', config.containerEnv.MULTIPLE)
    return false
  end

  return true
end

-- Test case 2: Empty and special cases
local function test_edge_cases()
  print('\n=== Test 2: Edge Cases ===')

  local test_path = '/tmp/test_edge_cases.json'
  local content = [[
{
  "name": "Edge Case Test",
  "image": "test:latest",
  "containerEnv": {
    "EMPTY_PREFIX": "${containerEnv:PATH}",
    "EMPTY_SUFFIX": "${containerEnv:HOME}",
    "MALFORMED": "${containerEnv:}",
    "UNCLOSED": "${containerEnv:PATH",
    "NESTED": "${containerEnv:${containerEnv:USER}}"
  }
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

  -- Test expansion without prefix/suffix
  if
    config.containerEnv.EMPTY_PREFIX
    == '/usr/local/go/bin:/go/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'
  then
    print('✓ Empty prefix expansion')
  else
    print('✗ Empty prefix failed:', config.containerEnv.EMPTY_PREFIX)
    return false
  end

  if config.containerEnv.EMPTY_SUFFIX == '/root' then
    print('✓ Empty suffix expansion')
  else
    print('✗ Empty suffix failed:', config.containerEnv.EMPTY_SUFFIX)
    return false
  end

  -- Test malformed patterns (should remain unchanged)
  if config.containerEnv.MALFORMED == '${containerEnv:}' then
    print('✓ Malformed pattern preserved')
  else
    print('✗ Malformed pattern changed:', config.containerEnv.MALFORMED)
    return false
  end

  if config.containerEnv.UNCLOSED == '${containerEnv:PATH' then
    print('✓ Unclosed pattern preserved')
  else
    print('✗ Unclosed pattern changed:', config.containerEnv.UNCLOSED)
    return false
  end

  return true
end

-- Run all tests
local test1 = test_multiple_expansions()
local test2 = test_edge_cases()

if test1 and test2 then
  print('\n=== All Environment Variable Edge Case Tests Passed! ===')
  print('✓ Multiple variable expansions working')
  print('✓ Edge cases handled properly')
  print('✓ Malformed patterns preserved safely')
else
  print('\n=== Some Environment Variable Edge Case Tests Failed! ===')
  os.exit(1)
end
