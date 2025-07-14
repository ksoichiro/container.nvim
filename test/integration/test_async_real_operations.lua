-- test/integration/test_async_real_operations.lua
-- Real integration tests for container.utils.async module
-- Tests with actual vim.loop operations and real file system interactions

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
  return condition
end

-- Helper function to wait for condition with timeout
local function wait_for_condition(condition_fn, timeout_ms, check_interval_ms)
  timeout_ms = timeout_ms or 2000
  check_interval_ms = check_interval_ms or 50

  local start_time = vim.loop.now()
  while vim.loop.now() - start_time < timeout_ms do
    if condition_fn() then
      return true
    end
    vim.loop.sleep(check_interval_ms)
  end
  return false
end

-- Create temporary test directory
local test_dir = '/tmp/container_async_tests_' .. os.time()
local function setup_test_environment()
  os.execute('mkdir -p ' .. test_dir)
  return test_dir
end

local function cleanup_test_environment()
  os.execute('rm -rf ' .. test_dir)
end

-- Test 1: Real command execution with actual output
local function test_real_command_execution()
  local completed = false
  local result = nil

  async.run_command('echo', { 'real_test_output' }, {}, function(res)
    result = res
    completed = true
  end)

  local success = wait_for_condition(function()
    return completed
  end, 1000)

  assert_test(success, 'Real command execution completed')
  assert_test(result ~= nil, 'Real command result received')
  assert_test(result.success == true, 'Real command succeeded')
  assert_test(result.code == 0, 'Real command exit code is 0')
  assert_test(result.stdout:match('real_test_output'), 'Real command output matches expected')
  assert_test(type(result.stderr) == 'string', 'Real command stderr is string')
end

-- Test 2: Real file operations with temporary files
local function test_real_file_operations()
  local test_file = test_dir .. '/test_file.txt'
  local test_content = 'This is test content for async file operations\nLine 2\nLine 3'

  -- Test file writing
  local write_completed = false
  local write_error = nil

  async.write_file(test_file, test_content, function(err)
    write_error = err
    write_completed = true
  end)

  local write_success = wait_for_condition(function()
    return write_completed
  end, 1000)
  assert_test(write_success, 'Real file write completed')
  assert_test(write_error == nil, 'Real file write no error')

  -- Verify file exists on filesystem
  local file_exists = vim.loop.fs_stat(test_file) ~= nil
  assert_test(file_exists, 'Written file exists on filesystem')

  -- Test file reading
  local read_completed = false
  local read_data = nil
  local read_error = nil

  async.read_file(test_file, function(data, err)
    read_data = data
    read_error = err
    read_completed = true
  end)

  local read_success = wait_for_condition(function()
    return read_completed
  end, 1000)
  assert_test(read_success, 'Real file read completed')
  assert_test(read_error == nil, 'Real file read no error')
  assert_test(read_data == test_content, 'Read content matches written content')
end

-- Test 3: Real directory operations
local function test_real_directory_operations()
  local test_subdir = test_dir .. '/nested/deep/directory'

  -- Test recursive directory creation
  local mkdir_completed = false
  local mkdir_error = nil

  async.mkdir_p(test_subdir, function(err)
    mkdir_error = err
    mkdir_completed = true
  end)

  local mkdir_success = wait_for_condition(function()
    return mkdir_completed
  end, 1000)
  assert_test(mkdir_success, 'Real recursive directory creation completed')
  assert_test(mkdir_error == nil, 'Real directory creation no error')

  -- Verify directory exists
  local dir_stat = vim.loop.fs_stat(test_subdir)
  assert_test(dir_stat ~= nil and dir_stat.type == 'directory', 'Created directory exists on filesystem')

  -- Test directory existence check
  local dir_exists_completed = false
  local dir_exists_result = nil

  async.dir_exists(test_subdir, function(exists)
    dir_exists_result = exists
    dir_exists_completed = true
  end)

  local dir_check_success = wait_for_condition(function()
    return dir_exists_completed
  end, 1000)
  assert_test(dir_check_success, 'Real directory existence check completed')
  assert_test(dir_exists_result == true, 'Directory existence check returns true')

  -- Test file existence check on directory (should return false)
  local file_exists_completed = false
  local file_exists_result = nil

  async.file_exists(test_subdir, function(exists)
    file_exists_result = exists
    file_exists_completed = true
  end)

  local file_check_success = wait_for_condition(function()
    return file_exists_completed
  end, 1000)
  assert_test(file_check_success, 'Real file existence check on directory completed')
  assert_test(file_exists_result == false, 'File existence check on directory returns false')
end

-- Test 4: Error handling with real file system errors
local function test_real_error_handling()
  -- Test reading non-existent file
  local read_completed = false
  local read_data = nil
  local read_error = nil

  async.read_file('/nonexistent/path/file.txt', function(data, err)
    read_data = data
    read_error = err
    read_completed = true
  end)

  local read_success = wait_for_condition(function()
    return read_completed
  end, 1000)
  assert_test(read_success, 'Real file read error case completed')
  assert_test(read_data == nil, 'Non-existent file read returns nil data')
  assert_test(read_error ~= nil, 'Non-existent file read returns error')

  -- Test writing to invalid path
  local write_completed = false
  local write_error = nil

  async.write_file('/root/protected_file.txt', 'content', function(err)
    write_error = err
    write_completed = true
  end)

  local write_success = wait_for_condition(function()
    return write_completed
  end, 1000)
  assert_test(write_success, 'Real file write error case completed')
  assert_test(write_error ~= nil, 'Protected file write returns error')
end

-- Test 5: Real command with streaming output
local function test_real_command_streaming()
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

  -- Use a command that produces output
  async.run_command('printf', { 'line1\\nline2\\nline3\\n' }, opts, function(res)
    result = res
    completed = true
  end)

  local success = wait_for_condition(function()
    return completed
  end, 1000)
  assert_test(success, 'Real streaming command completed')
  assert_test(result.success == true, 'Streaming command succeeded')
  assert_test(#stdout_chunks > 0, 'Stdout chunks received during streaming')

  local combined_stdout = table.concat(stdout_chunks)
  assert_test(combined_stdout:match('line1'), 'Streamed output contains expected content')
end

-- Test 6: Real timing operations
local function test_real_timing_operations()
  local delay_start = vim.loop.now()
  local delay_completed = false
  local delay_end = nil

  async.delay(200, function() -- 200ms delay
    delay_end = vim.loop.now()
    delay_completed = true
  end)

  -- Wait for delay to complete
  local success = wait_for_condition(function()
    return delay_completed
  end, 500)
  assert_test(success, 'Real delay operation completed')

  if delay_end then
    local elapsed = delay_end - delay_start
    assert_test(elapsed >= 180 and elapsed <= 300, 'Real delay timing is approximately correct')
  end
end

-- Test 7: Real debounce with actual timing
local function test_real_debounce_timing()
  local call_count = 0
  local last_value = nil
  local debounce_delay = 150 -- 150ms

  local debounced_fn = async.debounce(function(value)
    call_count = call_count + 1
    last_value = value
  end, debounce_delay)

  -- Call multiple times rapidly
  debounced_fn('call1')
  vim.loop.sleep(50)
  debounced_fn('call2')
  vim.loop.sleep(50)
  debounced_fn('call3')

  -- Check that function hasn't been called yet
  assert_test(call_count == 0, 'Real debounced function not called immediately')

  -- Wait for debounce delay plus buffer
  vim.loop.sleep(debounce_delay + 50)

  assert_test(call_count == 1, 'Real debounced function called once after delay')
  assert_test(last_value == 'call3', 'Real debounced function called with last value')
end

-- Test 8: Real command with working directory
local function test_real_command_with_cwd()
  local completed = false
  local result = nil

  local opts = {
    cwd = test_dir,
  }

  async.run_command('pwd', {}, opts, function(res)
    result = res
    completed = true
  end)

  local success = wait_for_condition(function()
    return completed
  end, 1000)
  assert_test(success, 'Real command with cwd completed')
  assert_test(result.success == true, 'Command with cwd succeeded')
  assert_test(result.stdout:match(test_dir), 'Command executed in correct working directory')
end

-- Test 9: Real long-running command
local function test_real_long_running_command()
  local start_time = vim.loop.now()
  local completed = false
  local result = nil

  async.run_command('sleep', { '0.3' }, {}, function(res) -- 300ms sleep
    result = res
    completed = true
  end)

  -- Check that command is still running after short time
  vim.loop.sleep(150) -- 150ms
  assert_test(completed == false, 'Long-running command not completed prematurely')

  -- Wait for completion
  local success = wait_for_condition(function()
    return completed
  end, 1000)
  assert_test(success, 'Long-running command completed')
  assert_test(result.success == true, 'Long-running command succeeded')

  local elapsed = vim.loop.now() - start_time
  assert_test(elapsed >= 250, 'Long-running command took appropriate time')
end

-- Test 10: Real run_command_sync in coroutine
local function test_real_run_command_sync()
  local sync_result = nil
  local sync_completed = false

  local function sync_test_coroutine()
    sync_result = async.run_command_sync('echo', { 'sync_test_real' }, {})
    sync_completed = true
  end

  local co = coroutine.create(sync_test_coroutine)
  coroutine.resume(co)

  -- Wait for synchronous operation to complete
  local success = wait_for_condition(function()
    return sync_completed
  end, 1000)
  assert_test(success, 'Real run_command_sync completed')
  assert_test(sync_result ~= nil, 'Real run_command_sync returned result')
  assert_test(sync_result.success == true, 'Real run_command_sync succeeded')
  assert_test(sync_result.stdout:match('sync_test_real'), 'Real run_command_sync output correct')
end

-- Test 11: Stress test with real operations
local function test_real_stress_operations()
  local completed_count = 0
  local total_operations = 10
  local results = {}
  local start_time = vim.loop.now()

  for i = 1, total_operations do
    async.run_command('echo', { 'stress_test_' .. i }, {}, function(result)
      results[i] = result
      completed_count = completed_count + 1
    end)
  end

  -- Wait for all operations to complete
  local success = wait_for_condition(function()
    return completed_count == total_operations
  end, 3000)

  local elapsed = vim.loop.now() - start_time

  assert_test(success, 'Real stress test all operations completed')
  assert_test(#results == total_operations, 'Real stress test all results collected')
  assert_test(elapsed < 2000, 'Real stress test completed in reasonable time')

  for i = 1, total_operations do
    assert_test(results[i] ~= nil, 'Real stress test result ' .. i .. ' exists')
    assert_test(results[i].success == true, 'Real stress test operation ' .. i .. ' succeeded')
  end
end

-- Test 12: Real file operations with large content
local function test_real_large_file_operations()
  local large_content = string.rep('This is a line of test content.\n', 1000) -- ~30KB
  local large_file = test_dir .. '/large_test_file.txt'

  -- Write large file
  local write_completed = false
  local write_error = nil

  async.write_file(large_file, large_content, function(err)
    write_error = err
    write_completed = true
  end)

  local write_success = wait_for_condition(function()
    return write_completed
  end, 2000)
  assert_test(write_success, 'Large file write completed')
  assert_test(write_error == nil, 'Large file write no error')

  -- Read large file
  local read_completed = false
  local read_data = nil
  local read_error = nil

  async.read_file(large_file, function(data, err)
    read_data = data
    read_error = err
    read_completed = true
  end)

  local read_success = wait_for_condition(function()
    return read_completed
  end, 2000)
  assert_test(read_success, 'Large file read completed')
  assert_test(read_error == nil, 'Large file read no error')
  assert_test(read_data == large_content, 'Large file content matches')
  assert_test(#read_data > 25000, 'Large file size is correct')
end

-- Main test execution
local function run_all_tests()
  print('Running real async operations integration tests...')

  setup_test_environment()

  -- Run all tests
  test_real_command_execution()
  test_real_file_operations()
  test_real_directory_operations()
  test_real_error_handling()
  test_real_command_streaming()
  test_real_timing_operations()
  test_real_debounce_timing()
  test_real_command_with_cwd()
  test_real_long_running_command()
  test_real_run_command_sync()
  test_real_stress_operations()
  test_real_large_file_operations()

  cleanup_test_environment()

  -- Print results
  print('\n=== Test Results ===')
  for _, result in ipairs(test_results) do
    print(result)
  end

  print(string.format('\nTests: %d/%d passed (%.1f%%)', passed_tests, total_tests, (passed_tests / total_tests) * 100))

  if passed_tests == total_tests then
    print('✓ All real async operations tests passed!')
    return true
  else
    print('✗ Some real async operations tests failed!')
    return false
  end
end

-- Execute tests
if vim.fn.exists('*luaeval') == 1 then
  -- Running in Neovim
  local success = run_all_tests()
  if not success then
    vim.cmd('cquit 1') -- Exit with error code
  else
    vim.cmd('qa!')
  end
else
  -- Running standalone
  error('This test must be run within Neovim environment')
end
