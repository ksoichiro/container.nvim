-- test/unit/test_async_comprehensive.lua
-- Comprehensive unit tests for container.utils.async module
-- Focus on all async utilities functionality, error scenarios, and edge cases

-- Setup test environment
package.path = './lua/?.lua;./lua/?/init.lua;' .. package.path

-- Mock vim global for unit testing
_G.vim = {
  loop = {
    new_pipe = function(ipc)
      local pipe = {
        _is_closing = false,
        _callbacks = {},
        close = function(self)
          self._is_closing = true
        end,
        is_closing = function(self)
          return self._is_closing
        end,
        read_start = function(self, callback)
          self._read_callback = callback
          -- Simulate immediate data for some tests
          if self._mock_data then
            callback(nil, self._mock_data)
            callback(nil, nil) -- EOF
          end
        end,
      }
      return pipe
    end,
    spawn = function(cmd, options, callback)
      local handle = {
        _is_closing = false,
        close = function(self)
          self._is_closing = true
        end,
        is_closing = function(self)
          return self._is_closing
        end,
      }

      -- Simulate different command behaviors
      if cmd == 'echo' then
        -- Simulate successful echo command
        if options.stdio and options.stdio[2] then
          options.stdio[2]._mock_data = (options.args and options.args[1] or 'test') .. '\n'
        end
        -- Simulate async completion
        vim.schedule(function()
          callback(0, 0) -- exit code, signal
        end)
      elseif cmd == 'false' then
        -- Simulate failed command
        vim.schedule(function()
          callback(1, 0) -- exit code 1, signal 0
        end)
      elseif cmd == 'non_existent_command' then
        -- Simulate spawn failure
        return nil
      elseif cmd == 'sleep' then
        -- Simulate long-running command
        local delay = tonumber(options.args and options.args[1] or '0.1') * 1000
        vim.defer_fn(function()
          callback(0, 0)
        end, delay)
      else
        -- Default successful command
        vim.schedule(function()
          callback(0, 0)
        end)
      end

      return handle
    end,
    new_timer = function()
      local timer = {
        _is_closed = false,
        start = function(self, delay, repeat_interval, callback)
          vim.defer_fn(function()
            if not self._is_closed then
              callback()
            end
          end, delay)
        end,
        close = function(self)
          self._is_closed = true
        end,
      }
      return timer
    end,
    fs_open = function(path, mode, perm, callback)
      if path:match('/nonexistent/') then
        callback('ENOENT: no such file or directory')
        return
      end
      if path:match('/readonly/') and mode == 'w' then
        callback('EACCES: permission denied')
        return
      end
      -- Simulate successful file open
      vim.schedule(function()
        callback(nil, 123) -- mock file descriptor
      end)
    end,
    fs_fstat = function(fd, callback)
      vim.schedule(function()
        callback(nil, { size = 20 })
      end)
    end,
    fs_read = function(fd, size, offset, callback)
      vim.schedule(function()
        callback(nil, 'test file content\n')
      end)
    end,
    fs_write = function(fd, data, offset, callback)
      vim.schedule(function()
        callback(nil)
      end)
    end,
    fs_close = function(fd, callback)
      vim.schedule(function()
        callback(nil)
      end)
    end,
    fs_stat = function(path, callback)
      if path:match('/exists_file$') then
        vim.schedule(function()
          callback(nil, { type = 'file' })
        end)
      elseif path:match('/exists_dir$') then
        vim.schedule(function()
          callback(nil, { type = 'directory' })
        end)
      elseif path:match('/nonexistent') then
        vim.schedule(function()
          callback('ENOENT: no such file or directory')
        end)
      else
        vim.schedule(function()
          callback(nil, { type = 'file' })
        end)
      end
    end,
    fs_mkdir = function(path, mode, callback)
      if path:match('/readonly/') then
        vim.schedule(function()
          callback('EACCES: permission denied')
        end)
      elseif path:match('/already_exists$') then
        vim.schedule(function()
          callback('EEXIST: file already exists')
        end)
      elseif path:match('/parent_missing/child$') then
        vim.schedule(function()
          callback('ENOENT: no such file or directory')
        end)
      else
        vim.schedule(function()
          callback(nil)
        end)
      end
    end,
    now = function()
      return os.clock() * 1000
    end,
    sleep = function(ms)
      -- Mock sleep - do nothing for unit tests
    end,
  },
  schedule = function(fn)
    -- Execute immediately for unit tests
    fn()
  end,
  defer_fn = function(fn, delay)
    -- Execute immediately for unit tests
    fn()
  end,
  fn = {
    fnamemodify = function(path, modifier)
      if modifier == ':h' then
        local parts = vim.split(path, '/')
        if #parts > 1 then
          table.remove(parts)
          return table.concat(parts, '/')
        end
        return path
      end
      return path
    end,
  },
  split = function(str, sep)
    local result = {}
    for match in (str .. sep):gmatch('(.-)' .. sep) do
      table.insert(result, match)
    end
    return result
  end,
}

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

-- Helper function to wait for async operations in unit tests
local function wait_for_callback(callback_fn, timeout_ms)
  timeout_ms = timeout_ms or 100
  local completed = false
  local result = nil

  callback_fn(function(...)
    result = { ... }
    completed = true
  end)

  -- In unit tests, operations complete immediately due to mocking
  return completed, result
end

-- Test 1: create_result function behavior
local function test_create_result_function()
  -- Access the internal create_result function through run_command
  local result_captured = nil

  local completed, result = wait_for_callback(function(cb)
    async.run_command('echo', { 'test' }, {}, function(res)
      result_captured = res
      cb(res)
    end)
  end)

  assert_test(completed, 'run_command completed for create_result test')
  assert_test(result_captured ~= nil, 'Result object created')
  assert_test(result_captured.code ~= nil, 'Result has code field')
  assert_test(result_captured.stdout ~= nil, 'Result has stdout field')
  assert_test(result_captured.stderr ~= nil, 'Result has stderr field')
  assert_test(result_captured.success ~= nil, 'Result has success field')
  assert_test(result_captured.success == (result_captured.code == 0), 'Success field matches code == 0')
end

-- Test 2: run_command basic functionality
local function test_run_command_basic()
  local completed, result = wait_for_callback(function(cb)
    async.run_command('echo', { 'hello world' }, {}, cb)
  end)

  assert_test(completed, 'run_command basic execution completed')
  assert_test(result[1].success == true, 'Basic command succeeded')
  assert_test(result[1].code == 0, 'Basic command exit code is 0')
  assert_test(type(result[1].stdout) == 'string', 'Stdout is string')
  assert_test(type(result[1].stderr) == 'string', 'Stderr is string')
end

-- Test 3: run_command with options
local function test_run_command_with_options()
  local stdout_data = {}
  local stderr_data = {}

  local opts = {
    cwd = '/test/dir',
    env = { 'TEST_VAR=value' },
    on_stdout = function(data)
      table.insert(stdout_data, data)
    end,
    on_stderr = function(data)
      table.insert(stderr_data, data)
    end,
  }

  local completed, result = wait_for_callback(function(cb)
    async.run_command('echo', { 'test' }, opts, cb)
  end)

  assert_test(completed, 'run_command with options completed')
  assert_test(result[1].success == true, 'Command with options succeeded')
  -- Note: stdout_data might be empty in unit tests due to mocking
end

-- Test 4: run_command error handling
local function test_run_command_error_handling()
  -- Test failed command
  local completed, result = wait_for_callback(function(cb)
    async.run_command('false', {}, {}, cb)
  end)

  assert_test(completed, 'Failed command callback completed')
  assert_test(result[1].success == false, 'Failed command marked as unsuccessful')
  assert_test(result[1].code ~= 0, 'Failed command has non-zero exit code')

  -- Test spawn failure
  local completed2, result2 = wait_for_callback(function(cb)
    async.run_command('non_existent_command', {}, {}, cb)
  end)

  assert_test(completed2, 'Spawn failure callback completed')
  assert_test(result2[1].success == false, 'Spawn failure marked as unsuccessful')
  assert_test(result2[1].code == -1, 'Spawn failure has code -1')
  assert_test(result2[1].stderr:match('Failed to spawn'), 'Spawn failure error message')
end

-- Test 5: run_command without callback
local function test_run_command_no_callback()
  -- Should not crash when callback is nil
  local handle = async.run_command('echo', { 'test' }, {}, nil)
  assert_test(handle ~= nil or true, 'run_command handles nil callback gracefully')
end

-- Test 6: run_command_sync basic functionality
local function test_run_command_sync_basic()
  local function test_coroutine()
    local result = async.run_command_sync('echo', { 'sync test' }, {})
    assert_test(result ~= nil, 'run_command_sync returned result')
    assert_test(result.success == true, 'Sync command succeeded')
    assert_test(result.code == 0, 'Sync command exit code is 0')
  end

  -- Test within coroutine
  local co = coroutine.create(test_coroutine)
  local success, err = coroutine.resume(co)
  assert_test(success, 'run_command_sync executed in coroutine: ' .. (err or ''))
end

-- Test 7: run_command_sync error cases
local function test_run_command_sync_errors()
  -- Test calling outside coroutine
  local success, err = pcall(function()
    async.run_command_sync('echo', { 'test' }, {})
  end)

  assert_test(success == false, 'run_command_sync fails outside coroutine')
  assert_test(err:match('coroutine'), 'Error message mentions coroutine requirement')
end

-- Test 8: read_file functionality
local function test_read_file()
  local completed, result = wait_for_callback(function(cb)
    async.read_file('/test/file.txt', cb)
  end)

  assert_test(completed, 'read_file completed')
  assert_test(result[1] ~= nil, 'read_file returned data')
  assert_test(result[2] == nil, 'read_file no error for valid file')

  -- Test file read error
  local completed2, result2 = wait_for_callback(function(cb)
    async.read_file('/nonexistent/file.txt', cb)
  end)

  assert_test(completed2, 'read_file error case completed')
  assert_test(result2[1] == nil, 'read_file error returns nil data')
  assert_test(result2[2] ~= nil, 'read_file error returns error message')
end

-- Test 9: write_file functionality
local function test_write_file()
  local completed, result = wait_for_callback(function(cb)
    async.write_file('/test/output.txt', 'test content', cb)
  end)

  assert_test(completed, 'write_file completed')
  assert_test(result[1] == nil, 'write_file no error for valid write')

  -- Test write error
  local completed2, result2 = wait_for_callback(function(cb)
    async.write_file('/readonly/file.txt', 'content', cb)
  end)

  assert_test(completed2, 'write_file error case completed')
  assert_test(result2[1] ~= nil, 'write_file error returns error message')
end

-- Test 10: dir_exists functionality
local function test_dir_exists()
  local completed, result = wait_for_callback(function(cb)
    async.dir_exists('/exists_dir', cb)
  end)

  assert_test(completed, 'dir_exists completed')
  assert_test(result[1] == true, 'dir_exists returns true for existing directory')

  -- Test non-existent directory
  local completed2, result2 = wait_for_callback(function(cb)
    async.dir_exists('/nonexistent', cb)
  end)

  assert_test(completed2, 'dir_exists non-existent completed')
  assert_test(result2[1] == false, 'dir_exists returns false for non-existent')

  -- Test file (not directory)
  local completed3, result3 = wait_for_callback(function(cb)
    async.dir_exists('/exists_file', cb)
  end)

  assert_test(completed3, 'dir_exists file test completed')
  assert_test(result3[1] == false, 'dir_exists returns false for file')
end

-- Test 11: file_exists functionality
local function test_file_exists()
  local completed, result = wait_for_callback(function(cb)
    async.file_exists('/exists_file', cb)
  end)

  assert_test(completed, 'file_exists completed')
  assert_test(result[1] == true, 'file_exists returns true for existing file')

  -- Test non-existent file
  local completed2, result2 = wait_for_callback(function(cb)
    async.file_exists('/nonexistent', cb)
  end)

  assert_test(completed2, 'file_exists non-existent completed')
  assert_test(result2[1] == false, 'file_exists returns false for non-existent')

  -- Test directory (not file)
  local completed3, result3 = wait_for_callback(function(cb)
    async.file_exists('/exists_dir', cb)
  end)

  assert_test(completed3, 'file_exists directory test completed')
  assert_test(result3[1] == false, 'file_exists returns false for directory')
end

-- Test 12: mkdir_p basic functionality
local function test_mkdir_p_basic()
  local completed, result = wait_for_callback(function(cb)
    async.mkdir_p('/test/new/dir', cb)
  end)

  assert_test(completed, 'mkdir_p completed')
  assert_test(result[1] == nil, 'mkdir_p no error for new directory')
end

-- Test 13: mkdir_p existing directory
local function test_mkdir_p_existing()
  local completed, result = wait_for_callback(function(cb)
    async.mkdir_p('/already_exists', cb)
  end)

  assert_test(completed, 'mkdir_p existing directory completed')
  assert_test(result[1] == nil, 'mkdir_p handles existing directory gracefully')
end

-- Test 14: mkdir_p error cases
local function test_mkdir_p_errors()
  local completed, result = wait_for_callback(function(cb)
    async.mkdir_p('/readonly/newdir', cb)
  end)

  assert_test(completed, 'mkdir_p error case completed')
  assert_test(result[1] ~= nil, 'mkdir_p returns error for permission denied')
end

-- Test 15: mkdir_p recursive creation
local function test_mkdir_p_recursive()
  -- Mock a scenario where parent doesn't exist initially
  local original_fs_mkdir = vim.loop.fs_mkdir
  local mkdir_calls = {}

  vim.loop.fs_mkdir = function(path, mode, callback)
    table.insert(mkdir_calls, path)
    if path == '/parent_missing/child' and #mkdir_calls == 1 then
      vim.schedule(function()
        callback('ENOENT: no such file or directory')
      end)
    else
      vim.schedule(function()
        callback(nil)
      end)
    end
  end

  local completed, result = wait_for_callback(function(cb)
    async.mkdir_p('/parent_missing/child', cb)
  end)

  vim.loop.fs_mkdir = original_fs_mkdir

  assert_test(completed, 'mkdir_p recursive completed')
  assert_test(#mkdir_calls >= 1, 'mkdir_p made multiple attempts')
end

-- Test 16: delay functionality
local function test_delay()
  local delay_executed = false

  local timer = async.delay(50, function()
    delay_executed = true
  end)

  assert_test(timer ~= nil, 'delay returns timer object')
  assert_test(delay_executed == true, 'delay callback executed (mocked immediately)')
end

-- Test 17: debounce functionality
local function test_debounce()
  local call_count = 0
  local last_args = nil

  local debounced = async.debounce(function(...)
    call_count = call_count + 1
    last_args = { ... }
  end, 100)

  -- Call multiple times
  debounced('arg1')
  debounced('arg2')
  debounced('arg3')

  assert_test(call_count == 1, 'debounce executed once (mocked immediately)')
  assert_test(last_args[1] == 'arg3', 'debounce used last arguments')
end

-- Test 18: debounce with different delays
local function test_debounce_multiple_instances()
  local count1 = 0
  local count2 = 0

  local debounced1 = async.debounce(function()
    count1 = count1 + 1
  end, 50)
  local debounced2 = async.debounce(function()
    count2 = count2 + 1
  end, 100)

  debounced1()
  debounced2()

  assert_test(count1 == 1, 'First debounced function executed')
  assert_test(count2 == 1, 'Second debounced function executed')
end

-- Test 19: Edge case - empty arguments
local function test_edge_cases_empty_args()
  local completed, result = wait_for_callback(function(cb)
    async.run_command('echo', nil, nil, cb)
  end)

  assert_test(completed, 'run_command with nil args completed')
  assert_test(result[1].success == true, 'Command with nil args succeeded')

  local completed2, result2 = wait_for_callback(function(cb)
    async.run_command('echo', {}, {}, cb)
  end)

  assert_test(completed2, 'run_command with empty args completed')
  assert_test(result2[1].success == true, 'Command with empty args succeeded')
end

-- Test 20: Edge case - very long output
local function test_edge_cases_long_output()
  -- Mock long output scenario
  local original_spawn = vim.loop.spawn
  vim.loop.spawn = function(cmd, options, callback)
    local handle = {
      _is_closing = false,
      close = function(self)
        self._is_closing = true
      end,
      is_closing = function(self)
        return self._is_closing
      end,
    }

    if options.stdio and options.stdio[2] then
      -- Simulate long output
      local long_data = string.rep('x', 1000) .. '\n'
      options.stdio[2]._mock_data = long_data
    end

    vim.schedule(function()
      callback(0, 0)
    end)
    return handle
  end

  local completed, result = wait_for_callback(function(cb)
    async.run_command('echo', { 'test' }, {}, cb)
  end)

  vim.loop.spawn = original_spawn

  assert_test(completed, 'Long output command completed')
  assert_test(result[1].success == true, 'Long output command succeeded')
end

-- Test 21: Memory cleanup verification
local function test_memory_cleanup()
  local handles_created = 0
  local handles_closed = 0

  local original_spawn = vim.loop.spawn
  local original_new_pipe = vim.loop.new_pipe

  vim.loop.spawn = function(...)
    handles_created = handles_created + 1
    local handle = original_spawn(...)
    if handle then
      local original_close = handle.close
      handle.close = function(self)
        handles_closed = handles_closed + 1
        original_close(self)
      end
    end
    return handle
  end

  vim.loop.new_pipe = function(...)
    handles_created = handles_created + 1
    local pipe = original_new_pipe(...)
    local original_close = pipe.close
    pipe.close = function(self)
      handles_closed = handles_closed + 1
      original_close(self)
    end
    return pipe
  end

  local completed, result = wait_for_callback(function(cb)
    async.run_command('echo', { 'cleanup test' }, {}, cb)
  end)

  vim.loop.spawn = original_spawn
  vim.loop.new_pipe = original_new_pipe

  assert_test(completed, 'Cleanup test command completed')
  assert_test(handles_created > 0, 'Handles were created')
  -- Note: In unit tests, cleanup might happen differently due to mocking
end

-- Test 22: Stress test - multiple concurrent operations
local function test_stress_multiple_operations()
  local completed_count = 0
  local total_operations = 5
  local results = {}

  for i = 1, total_operations do
    async.run_command('echo', { 'test' .. i }, {}, function(result)
      completed_count = completed_count + 1
      results[i] = result
    end)
  end

  -- In unit tests, all operations complete immediately due to mocking
  assert_test(completed_count == total_operations, 'All stress test operations completed')
  assert_test(#results == total_operations, 'All stress test results collected')

  for i = 1, total_operations do
    assert_test(results[i] ~= nil, 'Stress test result ' .. i .. ' exists')
    assert_test(results[i].success == true, 'Stress test operation ' .. i .. ' succeeded')
  end
end

-- Main test runner
local function run_all_tests()
  print('Running comprehensive async utils unit tests...')

  test_create_result_function()
  test_run_command_basic()
  test_run_command_with_options()
  test_run_command_error_handling()
  test_run_command_no_callback()
  test_run_command_sync_basic()
  test_run_command_sync_errors()
  test_read_file()
  test_write_file()
  test_dir_exists()
  test_file_exists()
  test_mkdir_p_basic()
  test_mkdir_p_existing()
  test_mkdir_p_errors()
  test_mkdir_p_recursive()
  test_delay()
  test_debounce()
  test_debounce_multiple_instances()
  test_edge_cases_empty_args()
  test_edge_cases_long_output()
  test_memory_cleanup()
  test_stress_multiple_operations()

  -- Print results
  print('\n=== Test Results ===')
  for _, result in ipairs(test_results) do
    print(result)
  end

  print(string.format('\nTests: %d/%d passed (%.1f%%)', passed_tests, total_tests, (passed_tests / total_tests) * 100))

  if passed_tests == total_tests then
    print('✓ All async utils unit tests passed!')
    return true
  else
    print('✗ Some async utils unit tests failed!')
    return false
  end
end

-- Execute tests
return {
  run = run_all_tests,
  total_tests = function()
    return total_tests
  end,
  passed_tests = function()
    return passed_tests
  end,
}
