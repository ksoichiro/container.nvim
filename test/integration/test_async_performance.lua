-- test/integration/test_async_performance.lua
-- Performance and stress tests for container.utils.async module
-- Tests scalability, memory usage, and performance characteristics

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
  timeout_ms = timeout_ms or 5000
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

-- Helper to measure memory usage (basic estimation)
local function get_memory_usage()
  collectgarbage('collect')
  return collectgarbage('count') * 1024 -- Convert to bytes
end

-- Helper to measure execution time
local function measure_time(fn)
  local start_time = vim.loop.now()
  fn()
  return vim.loop.now() - start_time
end

-- Test 1: High concurrency command execution
local function test_high_concurrency_commands()
  local total_operations = 50
  local completed_count = 0
  local results = {}
  local start_time = vim.loop.now()
  local memory_start = get_memory_usage()

  for i = 1, total_operations do
    async.run_command('echo', { 'concurrent_test_' .. i }, {}, function(result)
      results[i] = result
      completed_count = completed_count + 1
    end)
  end

  local success = wait_for_condition(function()
    return completed_count == total_operations
  end, 10000)

  local elapsed = vim.loop.now() - start_time
  local memory_end = get_memory_usage()
  local memory_used = memory_end - memory_start

  assert_test(success, 'High concurrency test completed')
  assert_test(#results == total_operations, 'All concurrent operations returned results')
  assert_test(elapsed < 5000, 'High concurrency completed in reasonable time (' .. elapsed .. 'ms)')
  assert_test(
    memory_used < 10 * 1024 * 1024,
    'Memory usage stayed reasonable (' .. math.floor(memory_used / 1024) .. 'KB)'
  )

  -- Verify all operations succeeded
  local success_count = 0
  for i = 1, total_operations do
    if results[i] and results[i].success then
      success_count = success_count + 1
    end
  end
  assert_test(success_count == total_operations, 'All concurrent operations succeeded')
end

-- Test 2: Rapid successive file operations
local function test_rapid_file_operations()
  local test_dir = '/tmp/async_perf_test_' .. os.time()
  os.execute('mkdir -p ' .. test_dir)

  local total_files = 30
  local completed_count = 0
  local write_errors = 0
  local read_errors = 0
  local start_time = vim.loop.now()

  -- Write multiple files rapidly
  for i = 1, total_files do
    local file_path = test_dir .. '/test_file_' .. i .. '.txt'
    local content = 'Test content for file ' .. i .. '\n' .. string.rep('data', 100)

    async.write_file(file_path, content, function(err)
      if err then
        write_errors = write_errors + 1
      else
        -- Immediately read the file back
        async.read_file(file_path, function(data, read_err)
          if read_err then
            read_errors = read_errors + 1
          else
            assert_test(data == content, 'File ' .. i .. ' content matches')
          end
          completed_count = completed_count + 1
        end)
      end
    end)
  end

  local success = wait_for_condition(function()
    return completed_count == total_files
  end, 8000)

  local elapsed = vim.loop.now() - start_time

  assert_test(success, 'Rapid file operations completed')
  assert_test(write_errors == 0, 'No write errors in rapid file operations')
  assert_test(read_errors == 0, 'No read errors in rapid file operations')
  assert_test(elapsed < 6000, 'Rapid file operations completed in reasonable time (' .. elapsed .. 'ms)')

  -- Cleanup
  os.execute('rm -rf ' .. test_dir)
end

-- Test 3: Large file handling performance
local function test_large_file_performance()
  local test_dir = '/tmp/async_large_file_test_' .. os.time()
  os.execute('mkdir -p ' .. test_dir)

  -- Create content of different sizes
  local test_sizes = {
    { name = 'small', size = 1024, content = string.rep('S', 1024) },
    { name = 'medium', size = 100 * 1024, content = string.rep('M', 100 * 1024) },
    { name = 'large', size = 1024 * 1024, content = string.rep('L', 1024 * 1024) },
  }

  local completed_tests = 0
  local total_subtests = #test_sizes
  local results = {}

  for _, test_case in ipairs(test_sizes) do
    local file_path = test_dir .. '/' .. test_case.name .. '_file.txt'
    local write_start = vim.loop.now()

    async.write_file(file_path, test_case.content, function(write_err)
      local write_time = vim.loop.now() - write_start

      assert_test(write_err == nil, test_case.name .. ' file write succeeded')

      local read_start = vim.loop.now()
      async.read_file(file_path, function(data, read_err)
        local read_time = vim.loop.now() - read_start

        assert_test(read_err == nil, test_case.name .. ' file read succeeded')
        assert_test(#data == test_case.size, test_case.name .. ' file size correct')
        assert_test(data == test_case.content, test_case.name .. ' file content correct')

        results[test_case.name] = {
          write_time = write_time,
          read_time = read_time,
          size = test_case.size,
        }

        completed_tests = completed_tests + 1
      end)
    end)
  end

  local success = wait_for_condition(function()
    return completed_tests == total_subtests
  end, 15000)

  assert_test(success, 'Large file performance tests completed')

  -- Check performance characteristics
  for name, result in pairs(results) do
    local write_speed = result.size / result.write_time * 1000 -- bytes per second
    local read_speed = result.size / result.read_time * 1000

    assert_test(write_speed > 1024, name .. ' write speed reasonable (' .. math.floor(write_speed / 1024) .. ' KB/s)')
    assert_test(read_speed > 1024, name .. ' read speed reasonable (' .. math.floor(read_speed / 1024) .. ' KB/s)')
  end

  -- Cleanup
  os.execute('rm -rf ' .. test_dir)
end

-- Test 4: Directory tree creation performance
local function test_directory_tree_performance()
  local base_dir = '/tmp/async_dir_perf_test_' .. os.time()
  local total_dirs = 20
  local completed_count = 0
  local start_time = vim.loop.now()

  -- Create nested directory structures
  for i = 1, total_dirs do
    local dir_path = base_dir .. '/level1_' .. i .. '/level2_' .. i .. '/level3_' .. i

    async.mkdir_p(dir_path, function(err)
      assert_test(err == nil, 'Directory creation ' .. i .. ' succeeded')

      -- Verify directory exists
      async.dir_exists(dir_path, function(exists)
        assert_test(exists == true, 'Created directory ' .. i .. ' exists')
        completed_count = completed_count + 1
      end)
    end)
  end

  local success = wait_for_condition(function()
    return completed_count == total_dirs
  end, 8000)

  local elapsed = vim.loop.now() - start_time

  assert_test(success, 'Directory tree creation performance test completed')
  assert_test(elapsed < 6000, 'Directory creation completed in reasonable time (' .. elapsed .. 'ms)')

  -- Cleanup
  os.execute('rm -rf ' .. base_dir)
end

-- Test 5: Debounce performance under load
local function test_debounce_performance()
  local call_count = 0
  local total_calls = 1000
  local debounce_delay = 100

  local debounced_fn = async.debounce(function(value)
    call_count = call_count + 1
  end, debounce_delay)

  local start_time = vim.loop.now()

  -- Make many rapid calls
  for i = 1, total_calls do
    debounced_fn('call_' .. i)
  end

  local call_time = vim.loop.now() - start_time

  -- Wait for debounce to trigger
  vim.loop.sleep(debounce_delay + 50)

  assert_test(call_count == 1, 'Debounce correctly limited calls to 1')
  assert_test(call_time < 100, 'Rapid debounce calls completed quickly (' .. call_time .. 'ms)')
end

-- Test 6: Timer performance and accuracy
local function test_timer_performance()
  local timer_count = 20
  local completed_timers = 0
  local timing_errors = {}
  local start_time = vim.loop.now()

  for i = 1, timer_count do
    local delay = 50 + (i * 10) -- Delays from 60ms to 250ms
    local timer_start = vim.loop.now()

    async.delay(delay, function()
      local actual_delay = vim.loop.now() - timer_start
      local error_margin = math.abs(actual_delay - delay)

      table.insert(timing_errors, error_margin)
      completed_timers = completed_timers + 1
    end)
  end

  local success = wait_for_condition(function()
    return completed_timers == timer_count
  end, 5000)

  assert_test(success, 'All timers completed')

  -- Check timing accuracy
  local max_error = 0
  local total_error = 0
  for _, error in ipairs(timing_errors) do
    max_error = math.max(max_error, error)
    total_error = total_error + error
  end

  local avg_error = total_error / #timing_errors

  assert_test(max_error < 50, 'Maximum timing error acceptable (' .. max_error .. 'ms)')
  assert_test(avg_error < 20, 'Average timing error acceptable (' .. avg_error .. 'ms)')
end

-- Test 7: Memory usage under sustained load
local function test_memory_usage_sustained_load()
  local memory_start = get_memory_usage()
  local operations_per_batch = 20
  local total_batches = 5
  local completed_batches = 0

  local function run_batch(batch_num)
    local batch_completed = 0

    for i = 1, operations_per_batch do
      async.run_command('echo', { 'batch_' .. batch_num .. '_op_' .. i }, {}, function(result)
        batch_completed = batch_completed + 1

        if batch_completed == operations_per_batch then
          completed_batches = completed_batches + 1

          -- Force garbage collection between batches
          collectgarbage('collect')

          if completed_batches < total_batches then
            -- Schedule next batch
            vim.defer_fn(function()
              run_batch(completed_batches + 1)
            end, 100)
          end
        end
      end)
    end
  end

  run_batch(1)

  local success = wait_for_condition(function()
    return completed_batches == total_batches
  end, 10000)

  assert_test(success, 'Sustained load test completed')

  local memory_end = get_memory_usage()
  local memory_growth = memory_end - memory_start

  assert_test(
    memory_growth < 5 * 1024 * 1024,
    'Memory growth under sustained load acceptable (' .. math.floor(memory_growth / 1024) .. 'KB)'
  )
end

-- Test 8: Mixed operation performance
local function test_mixed_operation_performance()
  local total_operations = 40
  local completed_operations = 0
  local test_dir = '/tmp/async_mixed_perf_test_' .. os.time()
  os.execute('mkdir -p ' .. test_dir)

  local start_time = vim.loop.now()
  local operation_types = { 'command', 'file_write', 'file_read', 'dir_create', 'existence_check' }

  for i = 1, total_operations do
    local op_type = operation_types[(i % #operation_types) + 1]

    if op_type == 'command' then
      async.run_command('echo', { 'mixed_test_' .. i }, {}, function(result)
        completed_operations = completed_operations + 1
      end)
    elseif op_type == 'file_write' then
      async.write_file(test_dir .. '/file_' .. i .. '.txt', 'content_' .. i, function(err)
        completed_operations = completed_operations + 1
      end)
    elseif op_type == 'file_read' then
      -- Create a file first, then read it
      local test_file = test_dir .. '/read_test_' .. i .. '.txt'
      local f = io.open(test_file, 'w')
      if f then
        f:write('read_content_' .. i)
        f:close()
        async.read_file(test_file, function(data, err)
          completed_operations = completed_operations + 1
        end)
      else
        completed_operations = completed_operations + 1
      end
    elseif op_type == 'dir_create' then
      async.mkdir_p(test_dir .. '/subdir_' .. i, function(err)
        completed_operations = completed_operations + 1
      end)
    elseif op_type == 'existence_check' then
      async.file_exists(test_dir .. '/file_' .. math.max(1, i - 5) .. '.txt', function(exists)
        completed_operations = completed_operations + 1
      end)
    end
  end

  local success = wait_for_condition(function()
    return completed_operations == total_operations
  end, 12000)

  local elapsed = vim.loop.now() - start_time

  assert_test(success, 'Mixed operation performance test completed')
  assert_test(elapsed < 10000, 'Mixed operations completed in reasonable time (' .. elapsed .. 'ms)')

  -- Calculate operations per second
  local ops_per_second = total_operations / (elapsed / 1000)
  assert_test(
    ops_per_second > 5,
    'Mixed operations throughput reasonable (' .. string.format('%.1f', ops_per_second) .. ' ops/sec)'
  )

  -- Cleanup
  os.execute('rm -rf ' .. test_dir)
end

-- Test 9: Error handling performance impact
local function test_error_handling_performance()
  local total_operations = 30
  local completed_operations = 0
  local error_count = 0
  local success_count = 0

  local start_time = vim.loop.now()

  for i = 1, total_operations do
    if i % 3 == 0 then
      -- Every third operation should fail
      async.run_command('false', {}, {}, function(result)
        if not result.success then
          error_count = error_count + 1
        end
        completed_operations = completed_operations + 1
      end)
    else
      -- Regular successful operation
      async.run_command('echo', { 'success_' .. i }, {}, function(result)
        if result.success then
          success_count = success_count + 1
        end
        completed_operations = completed_operations + 1
      end)
    end
  end

  local success = wait_for_condition(function()
    return completed_operations == total_operations
  end, 8000)

  local elapsed = vim.loop.now() - start_time

  assert_test(success, 'Error handling performance test completed')
  assert_test(error_count == math.floor(total_operations / 3), 'Expected number of errors occurred')
  assert_test(success_count == total_operations - error_count, 'Expected number of successes occurred')
  assert_test(elapsed < 6000, 'Error handling did not significantly impact performance (' .. elapsed .. 'ms)')
end

-- Test 10: Resource cleanup performance
local function test_resource_cleanup_performance()
  local handles_created = 0
  local handles_closed = 0
  local operations = 25
  local completed = 0

  -- Track handle creation and cleanup
  local original_spawn = vim.loop.spawn
  local original_new_pipe = vim.loop.new_pipe

  vim.loop.spawn = function(...)
    handles_created = handles_created + 1
    local result = original_spawn(...)
    return result
  end

  vim.loop.new_pipe = function(...)
    handles_created = handles_created + 1
    local pipe = original_new_pipe(...)
    local original_close = pipe.close
    pipe.close = function(self)
      handles_closed = handles_closed + 1
      return original_close(self)
    end
    return pipe
  end

  local start_time = vim.loop.now()

  for i = 1, operations do
    async.run_command('echo', { 'cleanup_test_' .. i }, {}, function(result)
      completed = completed + 1
    end)
  end

  local success = wait_for_condition(function()
    return completed == operations
  end, 5000)

  vim.loop.spawn = original_spawn
  vim.loop.new_pipe = original_new_pipe

  local elapsed = vim.loop.now() - start_time

  assert_test(success, 'Resource cleanup performance test completed')
  assert_test(handles_created > 0, 'Handles were created (' .. handles_created .. ')')
  assert_test(handles_closed > 0, 'Handles were cleaned up (' .. handles_closed .. ')')
  assert_test(elapsed < 4000, 'Resource cleanup did not impact performance (' .. elapsed .. 'ms)')

  -- Allow time for any remaining cleanup
  vim.loop.sleep(100)
end

-- Main test execution
local function run_all_tests()
  print('Running async performance and stress tests...')
  print('Note: These tests may take several seconds to complete.')

  test_high_concurrency_commands()
  test_rapid_file_operations()
  test_large_file_performance()
  test_directory_tree_performance()
  test_debounce_performance()
  test_timer_performance()
  test_memory_usage_sustained_load()
  test_mixed_operation_performance()
  test_error_handling_performance()
  test_resource_cleanup_performance()

  -- Print results
  print('\n=== Test Results ===')
  for _, result in ipairs(test_results) do
    print(result)
  end

  print(string.format('\nTests: %d/%d passed (%.1f%%)', passed_tests, total_tests, (passed_tests / total_tests) * 100))

  if passed_tests == total_tests then
    print('✓ All async performance tests passed!')
    return true
  else
    print('✗ Some async performance tests failed!')
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
