-- test_ftplugin_integration.lua
-- Tests for ftplugin integration with multi-language support

-- Add project lua directory to package path
package.path = './lua/?.lua;./lua/?/init.lua;../lua/?.lua;../lua/?/init.lua;' .. package.path

local M = {}

-- Mock vim functions
local function setup_vim_mocks()
  _G.vim = _G.vim or {}
  _G.vim.fn = _G.vim.fn or {}

  -- Mock vim.fn.fnamemodify for path extraction
  _G.vim.fn.fnamemodify = function(path, modifier)
    if modifier == ':p' then
      return path
    elseif modifier == ':h' then
      return path:match('(.+)/[^/]+$') or path
    end
    return path
  end
end

-- Test state
local test_state = {
  original_require = nil,
  loaded_ftplugins = {},
}

-- Mock ftplugin manager
local mock_ftplugin_manager = {
  setup_for_filetype = function(filetype)
    test_state.loaded_ftplugins[filetype] = true
    return true
  end,
}

local function setup_test()
  setup_vim_mocks()

  -- Reset test state
  test_state.loaded_ftplugins = {}

  -- Store original require
  test_state.original_require = require

  -- Override require for mock
  _G.require = function(module)
    if module == 'container.lsp.ftplugin_manager' then
      return mock_ftplugin_manager
    end
    return test_state.original_require(module)
  end
end

local function teardown_test()
  -- Restore original require
  if test_state.original_require then
    _G.require = test_state.original_require
  end

  test_state.original_require = nil
end

-- Test 1: Go ftplugin loading
function M.test_go_ftplugin()
  setup_test()

  -- Load Go ftplugin
  local success = pcall(function()
    dofile('ftplugin/go.lua')
  end)

  assert(success, 'Go ftplugin should load successfully')
  assert(test_state.loaded_ftplugins.go, 'Go ftplugin should call setup_for_filetype')

  print('✓ Go ftplugin loading verified')
  teardown_test()
  return true
end

-- Test 2: Python ftplugin loading
function M.test_python_ftplugin()
  setup_test()

  -- Load Python ftplugin
  local success = pcall(function()
    dofile('ftplugin/python.lua')
  end)

  assert(success, 'Python ftplugin should load successfully')
  assert(test_state.loaded_ftplugins.python, 'Python ftplugin should call setup_for_filetype')

  print('✓ Python ftplugin loading verified')
  teardown_test()
  return true
end

-- Test 3: TypeScript ftplugin loading
function M.test_typescript_ftplugin()
  setup_test()

  -- Load TypeScript ftplugin
  local success = pcall(function()
    dofile('ftplugin/typescript.lua')
  end)

  assert(success, 'TypeScript ftplugin should load successfully')
  assert(test_state.loaded_ftplugins.typescript, 'TypeScript ftplugin should call setup_for_filetype')

  print('✓ TypeScript ftplugin loading verified')
  teardown_test()
  return true
end

-- Test 4: JavaScript ftplugin loading
function M.test_javascript_ftplugin()
  setup_test()

  -- Load JavaScript ftplugin
  local success = pcall(function()
    dofile('ftplugin/javascript.lua')
  end)

  assert(success, 'JavaScript ftplugin should load successfully')
  assert(test_state.loaded_ftplugins.javascript, 'JavaScript ftplugin should call setup_for_filetype')

  print('✓ JavaScript ftplugin loading verified')
  teardown_test()
  return true
end

-- Test 5: Rust ftplugin loading
function M.test_rust_ftplugin()
  setup_test()

  -- Load Rust ftplugin
  local success = pcall(function()
    dofile('ftplugin/rust.lua')
  end)

  assert(success, 'Rust ftplugin should load successfully')
  assert(test_state.loaded_ftplugins.rust, 'Rust ftplugin should call setup_for_filetype')

  print('✓ Rust ftplugin loading verified')
  teardown_test()
  return true
end

-- Test 6: C ftplugin loading
function M.test_c_ftplugin()
  setup_test()

  -- Load C ftplugin
  local success = pcall(function()
    dofile('ftplugin/c.lua')
  end)

  assert(success, 'C ftplugin should load successfully')
  assert(test_state.loaded_ftplugins.c, 'C ftplugin should call setup_for_filetype')

  print('✓ C ftplugin loading verified')
  teardown_test()
  return true
end

-- Test 7: C++ ftplugin loading
function M.test_cpp_ftplugin()
  setup_test()

  -- Load C++ ftplugin
  local success = pcall(function()
    dofile('ftplugin/cpp.lua')
  end)

  assert(success, 'C++ ftplugin should load successfully')
  assert(test_state.loaded_ftplugins.cpp, 'C++ ftplugin should call setup_for_filetype')

  print('✓ C++ ftplugin loading verified')
  teardown_test()
  return true
end

-- Test 8: Lua ftplugin loading
function M.test_lua_ftplugin()
  setup_test()

  -- Load Lua ftplugin
  local success = pcall(function()
    dofile('ftplugin/lua.lua')
  end)

  assert(success, 'Lua ftplugin should load successfully')
  assert(test_state.loaded_ftplugins.lua, 'Lua ftplugin should call setup_for_filetype')

  print('✓ Lua ftplugin loading verified')
  teardown_test()
  return true
end

-- Test 9: All ftplugins use same pattern
function M.test_ftplugin_consistency()
  setup_test()

  local ftplugin_files = {
    'go',
    'python',
    'typescript',
    'javascript',
    'rust',
    'c',
    'cpp',
    'lua',
  }

  for _, lang in ipairs(ftplugin_files) do
    -- Reset state
    test_state.loaded_ftplugins = {}

    local success = pcall(function()
      dofile('ftplugin/' .. lang .. '.lua')
    end)

    assert(success, string.format('%s ftplugin should load', lang))
    assert(test_state.loaded_ftplugins[lang], string.format('%s ftplugin should call setup_for_filetype', lang))
  end

  print('✓ Ftplugin consistency verified')
  teardown_test()
  return true
end

-- Test 10: Error handling in ftplugin loading
function M.test_ftplugin_error_handling()
  setup_test()

  -- Mock ftplugin manager that throws error
  local error_manager = {
    setup_for_filetype = function(filetype)
      error('Mock error for testing')
    end,
  }

  _G.require = function(module)
    if module == 'container.lsp.ftplugin_manager' then
      return error_manager
    end
    return test_state.original_require(module)
  end

  -- Loading should fail gracefully
  local success = pcall(function()
    dofile('ftplugin/go.lua')
  end)

  -- Should not crash the ftplugin loading
  assert(not success, 'Should propagate error from ftplugin manager')

  print('✓ Ftplugin error handling verified')
  teardown_test()
  return true
end

-- Test runner function
function M.run_tests()
  print('=== Ftplugin Integration Tests ===')

  local tests = {
    'test_go_ftplugin',
    'test_python_ftplugin',
    'test_typescript_ftplugin',
    'test_javascript_ftplugin',
    'test_rust_ftplugin',
    'test_c_ftplugin',
    'test_cpp_ftplugin',
    'test_lua_ftplugin',
    'test_ftplugin_consistency',
    'test_ftplugin_error_handling',
  }

  local passed = 0
  local failed = 0

  for _, test_name in ipairs(tests) do
    local success, err = pcall(M[test_name])
    if success then
      passed = passed + 1
    else
      failed = failed + 1
      print(string.format('✗ %s: %s', test_name, err))
    end
  end

  print(string.format('\n=== Test Results ==='))
  print(string.format('Passed: %d', passed))
  print(string.format('Failed: %d', failed))
  print(string.format('Total: %d', passed + failed))

  if failed == 0 then
    print('All ftplugin integration tests passed! ✓')
  else
    print('Some ftplugin integration tests failed. ✗')
  end

  return failed == 0
end

-- Execute tests if run directly
if not pcall(debug.getlocal, 4, 1) then
  M.run_tests()
end

return M
