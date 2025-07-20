#!/usr/bin/env lua

-- Test for environment variable expansion implementation
-- Tests the fix for ${containerEnv:PATH} expansion issues

-- Add project lua directory to package path
package.path = './lua/?.lua;./lua/?/init.lua;../lua/?.lua;../lua/?/init.lua;' .. package.path

-- Mock vim global for testing (minimal setup for parser)
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
      -- Simple JSON decoder for testing
      local result = {}
      if str:match('"name"') then
        result.name = str:match('"name"%s*:%s*"([^"]+)"')
      end
      if str:match('"image"') then
        result.image = str:match('"image"%s*:%s*"([^"]+)"')
      end
      if str:match('"containerEnv"') then
        result.containerEnv = {}
        -- Extract environment variables with proper escaping
        for key, value in str:gmatch('"([^"]+)"%s*:%s*"([^"]+)"') do
          if key ~= 'name' and key ~= 'image' then
            result.containerEnv[key] = value
          end
        end
      end
      return result
    end,
  },
  tbl_deep_extend = function(behavior, ...)
    local result = {}
    for i = 1, select('#', ...) do
      local t = select(i, ...)
      if t then
        for k, v in pairs(t) do
          if type(v) == 'table' and type(result[k]) == 'table' then
            result[k] = vim.tbl_deep_extend(behavior, result[k], v)
          else
            result[k] = v
          end
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
      setmetatable(copy, vim.deepcopy(getmetatable(orig)))
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
  log = {
    levels = {
      DEBUG = 0,
      INFO = 1,
      WARN = 2,
      ERROR = 3,
    },
  },
  schedule = function(fn)
    fn()
  end,
}

print('Starting environment variable expansion implementation tests...')

-- Test the parser expansion
local parser = require('container.parser')

-- Create test file
local test_devcontainer_path = '/tmp/test_devcontainer_expansion_fixed.json'
local devcontainer_content = [[
{
  "name": "Test Environment Expansion Implementation",
  "image": "mcr.microsoft.com/containers/go:1-1.23-bookworm",
  "containerEnv": {
    "PATH": "/custom/bin:${containerEnv:PATH}",
    "GOPATH": "/go",
    "CUSTOM_VAR": "test_value",
    "HOME_VAR": "/custom/home:${containerEnv:HOME}",
    "UNKNOWN_VAR": "${containerEnv:UNKNOWN}"
  }
}
]]

local file = io.open(test_devcontainer_path, 'w')
file:write(devcontainer_content)
file:close()

local function test_env_expansion()
  -- Test 1: Should expand ${containerEnv:PATH} to fallback value
  print('\nTest 1: Expanding ${containerEnv:PATH}')
  local config, err = parser.parse(test_devcontainer_path)

  if err then
    print('✗ Parse error:', err)
    return false
  end

  local expected_path =
    '/custom/bin:/usr/local/go/bin:/go/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'
  if config.containerEnv.PATH == expected_path then
    print('✓ PATH expanded correctly:', config.containerEnv.PATH)
  else
    print('✗ PATH expansion failed. Expected:', expected_path)
    print('  Got:', config.containerEnv.PATH)
    return false
  end

  -- Verify the placeholder is no longer present
  if not config.containerEnv.PATH:find('${containerEnv:PATH}') then
    print('✓ PATH placeholder removed successfully')
  else
    print('✗ PATH placeholder still present')
    return false
  end

  -- Test 2: Should expand ${containerEnv:HOME} to fallback value
  print('\nTest 2: Expanding ${containerEnv:HOME}')
  local expected_home = '/custom/home:/root'
  if config.containerEnv.HOME_VAR == expected_home then
    print('✓ HOME_VAR expanded correctly:', config.containerEnv.HOME_VAR)
  else
    print('✗ HOME_VAR expansion failed. Expected:', expected_home)
    print('  Got:', config.containerEnv.HOME_VAR)
    return false
  end

  -- Test 3: Should keep unknown variables as placeholders
  print('\nTest 3: Unknown variables')
  if config.containerEnv.UNKNOWN_VAR == '${containerEnv:UNKNOWN}' then
    print('✓ Unknown variable kept as placeholder:', config.containerEnv.UNKNOWN_VAR)
  else
    print('✗ Unknown variable handling failed. Expected: ${containerEnv:UNKNOWN}')
    print('  Got:', config.containerEnv.UNKNOWN_VAR)
    return false
  end

  -- Test 4: Should work with normalized plugin config
  print('\nTest 4: Normalized configuration')
  local normalized = parser.normalize_for_plugin(config)
  if normalized.environment.PATH == expected_path then
    print('✓ Normalized PATH correct:', normalized.environment.PATH)
  else
    print('✗ Normalized PATH failed. Expected:', expected_path)
    print('  Got:', normalized.environment.PATH)
    return false
  end

  -- Test 5: Should not affect regular environment variables
  print('\nTest 5: Regular variables unchanged')
  if config.containerEnv.GOPATH == '/go' and config.containerEnv.CUSTOM_VAR == 'test_value' then
    print('✓ Regular variables unchanged')
    print('  GOPATH:', config.containerEnv.GOPATH)
    print('  CUSTOM_VAR:', config.containerEnv.CUSTOM_VAR)
  else
    print('✗ Regular variables affected')
    print('  GOPATH:', config.containerEnv.GOPATH, '(expected: /go)')
    print('  CUSTOM_VAR:', config.containerEnv.CUSTOM_VAR, '(expected: test_value)')
    return false
  end

  return true
end

-- Run the test
local success = test_env_expansion()

-- Cleanup
os.remove(test_devcontainer_path)

if success then
  print('\n=== All Environment Variable Expansion Tests Passed! ===')
  print('✓ ${containerEnv:PATH} expansion working')
  print('✓ ${containerEnv:HOME} expansion working')
  print('✓ Unknown variable handling working')
  print('✓ Normalized configuration working')
  print('✓ Regular variables preserved')
else
  print('\n=== Environment Variable Expansion Tests Failed! ===')
  os.exit(1)
end
