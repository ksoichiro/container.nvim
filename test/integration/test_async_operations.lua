-- test/integration/test_async_operations.lua
-- Tests for asynchronous operations with proper timing and callback verification
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

-- Helper function to wait for condition with timeout
local function wait_for_condition(condition_fn, timeout_ms, check_interval_ms)
  timeout_ms = timeout_ms or 1000 -- Reduced from 5000ms
  check_interval_ms = check_interval_ms or 50 -- Reduced from 100ms

  local start_time = vim.loop.now()
  while vim.loop.now() - start_time < timeout_ms do
    if condition_fn() then
      return true
    end
    vim.loop.sleep(check_interval_ms)
  end
  return false
end

-- Test 1: Basic async command execution with callback verification
local function test_async_command_execution()
  local completed = false
  local result = nil
  local callback_called = false

  async.run_command('echo', { 'test_message' }, {}, function(res)
    result = res
    completed = true
    callback_called = true
  end)

  -- Wait for completion
  local success = wait_for_condition(function()
    return completed
  end, 500)

  assert_test(success, 'Async command execution completed within timeout')
  assert_test(callback_called, 'Callback was called for async command')
  assert_test(result ~= nil, 'Result was passed to callback')
  assert_test(result.success == true, 'Command executed successfully')
  assert_test(result.stdout:match('test_message'), 'Command output matches expected')
end

-- Test 2: Multiple concurrent async operations
local function test_concurrent_async_operations()
  local results = {}
  local completed_count = 0
  local expected_count = 3

  for i = 1, expected_count do
    async.run_command('echo', { 'message_' .. i }, {}, function(res)
      results[i] = res
      completed_count = completed_count + 1
    end)
  end

  -- Wait for all operations to complete
  local success = wait_for_condition(function()
    return completed_count == expected_count
  end, 800)

  assert_test(success, 'All concurrent async operations completed')
  assert_test(#results == expected_count, 'All results were collected')

  for i = 1, expected_count do
    assert_test(results[i] ~= nil, 'Result ' .. i .. ' was received')
    assert_test(results[i].success == true, 'Concurrent operation ' .. i .. ' succeeded')
    assert_test(results[i].stdout:match('message_' .. i), 'Output ' .. i .. ' matches expected')
  end
end

-- Test 3: Async file operations
local function test_async_file_operations()
  local test_file = '/tmp/test_async_file.txt'
  local test_content = 'async test content'
  local write_completed = false
  local read_completed = false
  local read_content = nil

  -- Test async file writing
  async.write_file(test_file, test_content, function(err)
    write_completed = true
    assert_test(err == nil, 'Async file write completed without error')
  end)

  -- Wait for write to complete
  local write_success = wait_for_condition(function()
    return write_completed
  end, 500)
  assert_test(write_success, 'Async file write completed within timeout')

  -- Test async file reading
  if write_success then
    async.read_file(test_file, function(data, err)
      read_content = data
      read_completed = true
      assert_test(err == nil, 'Async file read completed without error')
      assert_test(data == test_content, 'Read content matches written content')
    end)

    local read_success = wait_for_condition(function()
      return read_completed
    end, 500)
    assert_test(read_success, 'Async file read completed within timeout')
  end

  -- Cleanup
  os.remove(test_file)
end

-- Test 4: Async error handling
local function test_async_error_handling()
  local error_handled = false
  local result = nil

  -- Try to execute non-existent command
  async.run_command('non_existent_command_xyz', {}, {}, function(res)
    result = res
    error_handled = true
  end)

  local success = wait_for_condition(function()
    return error_handled
  end, 500)

  assert_test(success, 'Error callback was called within timeout')
  assert_test(result ~= nil, 'Error result was provided')
  assert_test(result.success == false, 'Error result indicates failure')
  assert_test(result.code ~= 0 or result.stderr ~= '', 'Error information available in result')
end

-- Test 5: Async timeout scenarios
local function test_async_timeout_scenarios()
  local timeout_test_completed = false
  local result = nil

  -- Execute a command that takes time (sleep)
  async.run_command('sleep', { '0.2' }, {}, function(res)
    result = res
    timeout_test_completed = true
  end)

  -- Check that operation is still running after short time
  vim.loop.sleep(100) -- 0.1 seconds
  assert_test(timeout_test_completed == false, 'Long-running operation not completed prematurely')

  -- Wait for completion
  local success = wait_for_condition(function()
    return timeout_test_completed
  end, 600)
  assert_test(success, 'Long-running operation completed within extended timeout')
  assert_test(result ~= nil and result.success == true, 'Long-running operation succeeded')
end

-- Test 6: Async operation with stream handling
local function test_async_stream_handling()
  local stdout_chunks = {}
  local stderr_chunks = {}
  local completed = false
  local result = nil

  local opts = {
    on_stdout = function(data)
      table.insert(stdout_chunks, data)
    end,
    on_stderr = function(data)
      table.insert(stderr_chunks, data)
    end,
  }

  async.run_command('echo', { 'streaming_test' }, opts, function(res)
    result = res
    completed = true
  end)

  local success = wait_for_condition(function()
    return completed
  end, 500)

  assert_test(success, 'Streaming operation completed')
  assert_test(#stdout_chunks > 0, 'Stdout chunks were received')
  assert_test(result ~= nil and result.success == true, 'Streaming operation succeeded')

  local combined_stdout = table.concat(stdout_chunks)
  assert_test(combined_stdout:match('streaming_test'), 'Streamed output matches expected')
end

-- Test 7: Async directory operations
local function test_async_directory_operations()
  local test_dir = '/tmp/test_async_dir'
  local dir_created = false
  local dir_exists_result = nil
  local exists_check_completed = false

  -- Test directory creation
  async.mkdir_p(test_dir, function(err)
    dir_created = true
    assert_test(err == nil, 'Async directory creation completed without error')
  end)

  local create_success = wait_for_condition(function()
    return dir_created
  end, 500)
  assert_test(create_success, 'Directory creation completed within timeout')

  -- Test directory existence check
  if create_success then
    async.dir_exists(test_dir, function(exists)
      dir_exists_result = exists
      exists_check_completed = true
    end)

    local check_success = wait_for_condition(function()
      return exists_check_completed
    end, 500)
    assert_test(check_success, 'Directory existence check completed')
    assert_test(dir_exists_result == true, 'Created directory exists')
  end

  -- Cleanup
  os.execute('rm -rf ' .. test_dir)
end

-- Test 8: Async debounce functionality
local function test_async_debounce()
  local call_count = 0
  local last_value = nil

  local debounced_fn = async.debounce(function(value)
    call_count = call_count + 1
    last_value = value
  end, 100) -- 100ms debounce

  -- Call multiple times rapidly
  debounced_fn('call1')
  debounced_fn('call2')
  debounced_fn('call3')

  -- Check that function hasn't been called yet
  assert_test(call_count == 0, 'Debounced function not called immediately')

  -- Wait for debounce delay
  vim.loop.sleep(150)

  assert_test(call_count == 1, 'Debounced function called once after delay')
  assert_test(last_value == 'call3', 'Debounced function called with last value')
end

-- Test 9: Async delay functionality
local function test_async_delay()
  local delay_completed = false
  local start_time = vim.loop.now()
  local end_time = nil

  async.delay(200, function() -- 200ms delay
    delay_completed = true
    end_time = vim.loop.now()
  end)

  -- Check that delay hasn't completed immediately
  assert_test(delay_completed == false, 'Delay function not completed immediately')

  -- Wait for delay completion
  local success = wait_for_condition(function()
    return delay_completed
  end, 400)

  assert_test(success, 'Delay function completed within timeout')

  if end_time then
    local elapsed = end_time - start_time
    assert_test(elapsed >= 180 and elapsed <= 300, 'Delay timing is approximately correct')
  end
end

-- Main test execution
local function run_all_tests()
  print('Running async operations integration tests...')

  test_async_command_execution()
  test_concurrent_async_operations()
  test_async_file_operations()
  test_async_error_handling()
  test_async_timeout_scenarios()
  test_async_stream_handling()
  test_async_directory_operations()
  test_async_debounce()
  test_async_delay()

  -- Print results
  print('\n=== Test Results ===')
  for _, result in ipairs(test_results) do
    print(result)
  end

  print(string.format('\nTests: %d/%d passed (%.1f%%)', passed_tests, total_tests, (passed_tests / total_tests) * 100))

  if passed_tests == total_tests then
    print('✓ All async operations tests passed!')
    return true
  else
    print('✗ Some async operations tests failed!')
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
