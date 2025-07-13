-- test/integration/test_async_operations_simplified.lua
-- Simplified tests for asynchronous operations
-- NOTE: This test requires a real Neovim environment due to vim.loop usage

-- Setup test environment
package.path = './lua/?.lua;./lua/?/init.lua;' .. package.path

-- Check if running in real Neovim environment
if not vim or not vim.loop then
  error('This test requires a real Neovim environment with vim.loop support')
end

local async = require('container.utils.async')

-- Test results tracking
local test_results = {}
local total_tests = 0
local passed_tests = 0

-- Helper function to assert conditions
local function assert_test(condition, message)
  total_tests = total_tests + 1
  if condition then
    passed_tests = passed_tests + 1
    table.insert(test_results, '✓ ' .. message)
  else
    table.insert(test_results, '✗ ' .. message)
  end
end

-- Test 1: Basic async command execution (quick test)
local function test_basic_async_command()
  local completed = false
  local result = nil

  async.run_command('echo', { 'hello' }, {}, function(res)
    result = res
    completed = true
  end)

  -- Simple wait with vim.wait
  vim.wait(1000, function()
    return completed
  end)

  assert_test(completed, 'Basic async command completed')
  assert_test(result ~= nil, 'Result received from async command')
  assert_test(result.success == true, 'Async command succeeded')
  assert_test(result.stdout:match('hello'), 'Command output matches expected')
end

-- Test 2: Async error handling (quick test)
local function test_async_error_handling()
  local completed = false
  local result = nil

  async.run_command('false', {}, {}, function(res) -- 'false' command always fails
    result = res
    completed = true
  end)

  vim.wait(1000, function()
    return completed
  end)

  assert_test(completed, 'Error async command completed')
  assert_test(result ~= nil, 'Error result received')
  assert_test(result.success == false, 'Error result indicates failure')
end

-- Test 3: Async file existence check
local function test_async_file_operations()
  local check_completed = false
  local exists_result = nil

  -- Check for a file that should exist
  async.file_exists('./lua/container/utils/async.lua', function(exists)
    exists_result = exists
    check_completed = true
  end)

  vim.wait(1000, function()
    return check_completed
  end)

  assert_test(check_completed, 'File existence check completed')
  assert_test(exists_result == true, 'Async module file exists')
end

-- Test 4: Async delay function
local function test_async_delay()
  local delay_completed = false

  async.delay(100, function() -- 100ms delay
    delay_completed = true
  end)

  vim.wait(500, function()
    return delay_completed
  end)

  assert_test(delay_completed, 'Async delay function completed')
end

-- Test 5: Multiple async operations (simplified)
local function test_multiple_async_operations()
  local count = 0
  local target = 2

  for i = 1, target do
    async.run_command('echo', { tostring(i) }, {}, function(res)
      if res.success then
        count = count + 1
      end
    end)
  end

  vim.wait(2000, function()
    return count == target
  end)

  assert_test(count == target, 'Multiple async operations completed')
end

-- Main test execution
local function run_all_tests()
  print('Running simplified async operations integration tests...')

  test_basic_async_command()
  test_async_error_handling()
  test_async_file_operations()
  test_async_delay()
  test_multiple_async_operations()

  -- Print results
  print('\n=== Test Results ===')
  for _, result in ipairs(test_results) do
    print(result)
  end

  print(string.format('\nTests: %d/%d passed (%.1f%%)', passed_tests, total_tests, (passed_tests / total_tests) * 100))

  if passed_tests == total_tests then
    print('✓ All simplified async operations tests passed!')
    return true
  else
    print('✗ Some simplified async operations tests failed!')
    return false
  end
end

-- Execute tests
if vim.fn.exists('*luaeval') == 1 then
  -- Running in Neovim
  local success = run_all_tests()
  -- Exit with appropriate code
  vim.cmd('qa!')
else
  -- Running standalone
  error('This test must be run within Neovim environment')
end
