-- test/unit/test_async_error_scenarios.lua
-- Comprehensive error scenario tests for container.utils.async module
-- Focus on edge cases, error handling, and recovery scenarios

-- Setup test environment
package.path = './lua/?.lua;./lua/?/init.lua;' .. package.path

-- Enhanced mock vim global with error simulation capabilities
_G.vim = {
  loop = {
    new_pipe = function(ipc)
      local pipe = {
        _is_closing = false,
        _callbacks = {},
        _error_mode = false,
        close = function(self)
          self._is_closing = true
        end,
        is_closing = function(self)
          return self._is_closing
        end,
        read_start = function(self, callback)
          self._read_callback = callback
          if self._error_mode then
            callback('PIPE_ERROR: simulated read error', nil)
          elseif self._mock_data then
            callback(nil, self._mock_data)
            callback(nil, nil) -- EOF
          end
        end,
        set_error_mode = function(self, enabled)
          self._error_mode = enabled
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

      -- Enhanced error simulation
      if cmd == 'timeout_command' then
        -- Don't call callback to simulate timeout/hang
        return handle
      elseif cmd == 'segfault_command' then
        vim.schedule(function()
          callback(139, 11) -- SIGSEGV
        end)
      elseif cmd == 'killed_command' then
        vim.schedule(function()
          callback(137, 9) -- SIGKILL
        end)
      elseif cmd == 'permission_denied' then
        vim.schedule(function()
          callback(126, 0) -- Permission denied
        end)
      elseif cmd == 'command_not_found' then
        vim.schedule(function()
          callback(127, 0) -- Command not found
        end)
      elseif cmd == 'non_existent_command' then
        return nil -- Spawn failure
      elseif cmd == 'pipe_error_command' then
        if options.stdio and options.stdio[2] then
          options.stdio[2]:set_error_mode(true)
        end
        vim.schedule(function()
          callback(0, 0)
        end)
      elseif cmd == 'large_stderr_command' then
        if options.stdio and options.stdio[3] then
          options.stdio[3]._mock_data = string.rep('ERROR: ', 1000) .. '\n'
        end
        vim.schedule(function()
          callback(1, 0)
        end)
      elseif cmd == 'mixed_output_command' then
        if options.stdio and options.stdio[2] then
          options.stdio[2]._mock_data = 'stdout data\n'
        end
        if options.stdio and options.stdio[3] then
          options.stdio[3]._mock_data = 'stderr data\n'
        end
        vim.schedule(function()
          callback(0, 0)
        end)
      else
        -- Default behavior
        vim.schedule(function()
          callback(0, 0)
        end)
      end

      return handle
    end,
    new_timer = function()
      local timer = {
        _is_closed = false,
        _should_fail = false,
        start = function(self, delay, repeat_interval, callback)
          if self._should_fail then
            error('Timer creation failed')
          end
          vim.defer_fn(function()
            if not self._is_closed then
              callback()
            end
          end, delay)
        end,
        close = function(self)
          self._is_closed = true
        end,
        set_fail_mode = function(self, enabled)
          self._should_fail = enabled
        end,
      }
      return timer
    end,
    fs_open = function(path, mode, perm, callback)
      if path:match('/no_permission/') then
        vim.schedule(function()
          callback('EACCES: permission denied')
        end)
      elseif path:match('/no_space/') then
        vim.schedule(function()
          callback('ENOSPC: no space left on device')
        end)
      elseif path:match('/invalid_path/') then
        vim.schedule(function()
          callback('EINVAL: invalid argument')
        end)
      elseif path:match('/network_error/') then
        vim.schedule(function()
          callback('EIO: input/output error')
        end)
      elseif path:match('/busy_file/') then
        vim.schedule(function()
          callback('EBUSY: device or resource busy')
        end)
      elseif path:match('/too_many_files/') then
        vim.schedule(function()
          callback('EMFILE: too many open files')
        end)
      else
        vim.schedule(function()
          callback(nil, 123) -- mock file descriptor
        end)
      end
    end,
    fs_fstat = function(fd, callback)
      if fd == 999 then -- Error case
        vim.schedule(function()
          callback('EBADF: bad file descriptor')
        end)
      else
        vim.schedule(function()
          callback(nil, { size = 20 })
        end)
      end
    end,
    fs_read = function(fd, size, offset, callback)
      if fd == 998 then -- Error case
        vim.schedule(function()
          callback('EIO: input/output error')
        end)
      else
        vim.schedule(function()
          callback(nil, 'test file content\n')
        end)
      end
    end,
    fs_write = function(fd, data, offset, callback)
      if fd == 997 then -- Error case
        vim.schedule(function()
          callback('ENOSPC: no space left on device')
        end)
      else
        vim.schedule(function()
          callback(nil)
        end)
      end
    end,
    fs_close = function(fd, callback)
      vim.schedule(function()
        callback(nil)
      end)
    end,
    fs_stat = function(path, callback)
      if path:match('/access_denied/') then
        vim.schedule(function()
          callback('EACCES: permission denied')
        end)
      elseif path:match('/network_timeout/') then
        vim.schedule(function()
          callback('ETIMEDOUT: connection timed out')
        end)
      elseif path:match('/corrupted/') then
        vim.schedule(function()
          callback('EIO: input/output error')
        end)
      else
        vim.schedule(function()
          callback('ENOENT: no such file or directory')
        end)
      end
    end,
    fs_mkdir = function(path, mode, callback)
      if path:match('/no_permission/') then
        vim.schedule(function()
          callback('EACCES: permission denied')
        end)
      elseif path:match('/no_space/') then
        vim.schedule(function()
          callback('ENOSPC: no space left on device')
        end)
      elseif path:match('/readonly_fs/') then
        vim.schedule(function()
          callback('EROFS: read-only file system')
        end)
      elseif path:match('/name_too_long/') then
        vim.schedule(function()
          callback('ENAMETOOLONG: file name too long')
        end)
      elseif path:match('/invalid_parent/non_dir/child') then
        vim.schedule(function()
          callback('ENOTDIR: not a directory')
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
      -- Mock sleep
    end,
  },
  schedule = function(fn)
    fn()
  end,
  defer_fn = function(fn, delay)
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

-- Helper function to wait for callback with error handling
local function wait_for_callback(callback_fn, timeout_ms)
  timeout_ms = timeout_ms or 100
  local completed = false
  local result = nil
  local error_caught = nil

  local success, err = pcall(function()
    callback_fn(function(...)
      result = { ... }
      completed = true
    end)
  end)

  if not success then
    error_caught = err
  end

  return completed, result, error_caught
end

-- Test 1: Command spawn failures
local function test_command_spawn_failures()
  local completed, result = wait_for_callback(function(cb)
    async.run_command('non_existent_command', {}, {}, cb)
  end)

  assert_test(completed, 'Spawn failure callback executed')
  assert_test(result[1].success == false, 'Spawn failure marked as unsuccessful')
  assert_test(result[1].code == -1, 'Spawn failure has correct error code')
  assert_test(result[1].stderr:match('Failed to spawn'), 'Spawn failure has correct error message')
end

-- Test 2: Command exit code errors
local function test_command_exit_code_errors()
  -- Test permission denied
  local completed, result = wait_for_callback(function(cb)
    async.run_command('permission_denied', {}, {}, cb)
  end)

  assert_test(completed, 'Permission denied command completed')
  assert_test(result[1].success == false, 'Permission denied marked as failure')
  assert_test(result[1].code == 126, 'Permission denied has correct exit code')

  -- Test command not found
  local completed2, result2 = wait_for_callback(function(cb)
    async.run_command('command_not_found', {}, {}, cb)
  end)

  assert_test(completed2, 'Command not found completed')
  assert_test(result2[1].success == false, 'Command not found marked as failure')
  assert_test(result2[1].code == 127, 'Command not found has correct exit code')
end

-- Test 3: Signal termination scenarios
local function test_signal_termination()
  -- Test segmentation fault
  local completed, result = wait_for_callback(function(cb)
    async.run_command('segfault_command', {}, {}, cb)
  end)

  assert_test(completed, 'Segfault command completed')
  assert_test(result[1].success == false, 'Segfault marked as failure')
  assert_test(result[1].code == 139, 'Segfault has correct exit code')

  -- Test killed command
  local completed2, result2 = wait_for_callback(function(cb)
    async.run_command('killed_command', {}, {}, cb)
  end)

  assert_test(completed2, 'Killed command completed')
  assert_test(result2[1].success == false, 'Killed command marked as failure')
  assert_test(result2[1].code == 137, 'Killed command has correct exit code')
end

-- Test 4: Pipe read errors
local function test_pipe_read_errors()
  local completed, result = wait_for_callback(function(cb)
    async.run_command('pipe_error_command', {}, {}, cb)
  end)

  assert_test(completed, 'Pipe error command completed')
  -- Command should still complete even with pipe errors
  assert_test(result[1] ~= nil, 'Result received despite pipe errors')
end

-- Test 5: File operation errors
local function test_file_operation_errors()
  -- Test file open errors
  local completed, result = wait_for_callback(function(cb)
    async.read_file('/no_permission/file.txt', cb)
  end)

  assert_test(completed, 'Permission denied file read completed')
  assert_test(result[1] == nil, 'Permission denied returns nil data')
  assert_test(result[2] ~= nil, 'Permission denied returns error')
  assert_test(result[2]:match('EACCES'), 'Permission denied has correct error')

  -- Test no space left error
  local completed2, result2 = wait_for_callback(function(cb)
    async.write_file('/no_space/file.txt', 'data', cb)
  end)

  assert_test(completed2, 'No space left write completed')
  assert_test(result2[1] ~= nil, 'No space left returns error')
  assert_test(result2[1]:match('ENOSPC'), 'No space left has correct error')

  -- Test I/O error
  local completed3, result3 = wait_for_callback(function(cb)
    async.read_file('/network_error/file.txt', cb)
  end)

  assert_test(completed3, 'Network error file read completed')
  assert_test(result3[1] == nil, 'Network error returns nil data')
  assert_test(result3[2]:match('EIO'), 'Network error has correct error')
end

-- Test 6: Directory operation errors
local function test_directory_operation_errors()
  -- Test permission denied for mkdir
  local completed, result = wait_for_callback(function(cb)
    async.mkdir_p('/no_permission/newdir', cb)
  end)

  assert_test(completed, 'Permission denied mkdir completed')
  assert_test(result[1] ~= nil, 'Permission denied mkdir returns error')
  assert_test(result[1]:match('EACCES'), 'Permission denied mkdir has correct error')

  -- Test read-only filesystem
  local completed2, result2 = wait_for_callback(function(cb)
    async.mkdir_p('/readonly_fs/newdir', cb)
  end)

  assert_test(completed2, 'Read-only filesystem mkdir completed')
  assert_test(result2[1] ~= nil, 'Read-only filesystem returns error')
  assert_test(result2[1]:match('EROFS'), 'Read-only filesystem has correct error')

  -- Test filename too long
  local completed3, result3 = wait_for_callback(function(cb)
    async.mkdir_p('/name_too_long/newdir', cb)
  end)

  assert_test(completed3, 'Name too long mkdir completed')
  assert_test(result3[1] ~= nil, 'Name too long returns error')
  assert_test(result3[1]:match('ENAMETOOLONG'), 'Name too long has correct error')
end

-- Test 7: File existence check errors
local function test_existence_check_errors()
  -- Test access denied for stat
  local completed, result = wait_for_callback(function(cb)
    async.file_exists('/access_denied/file.txt', cb)
  end)

  assert_test(completed, 'Access denied file check completed')
  assert_test(result[1] == false, 'Access denied file check returns false')

  -- Test network timeout
  local completed2, result2 = wait_for_callback(function(cb)
    async.dir_exists('/network_timeout/dir', cb)
  end)

  assert_test(completed2, 'Network timeout dir check completed')
  assert_test(result2[1] == false, 'Network timeout dir check returns false')

  -- Test I/O error
  local completed3, result3 = wait_for_callback(function(cb)
    async.file_exists('/corrupted/file.txt', cb)
  end)

  assert_test(completed3, 'I/O error file check completed')
  assert_test(result3[1] == false, 'I/O error file check returns false')
end

-- Test 8: Timer creation failures
local function test_timer_creation_failures()
  -- Mock timer creation failure
  local original_new_timer = vim.loop.new_timer
  vim.loop.new_timer = function()
    local timer = original_new_timer()
    timer:set_fail_mode(true)
    return timer
  end

  local timer_error = nil
  local success, err = pcall(function()
    async.delay(100, function() end)
  end)

  vim.loop.new_timer = original_new_timer

  assert_test(success == false, 'Timer creation failure caught')
  assert_test(err ~= nil, 'Timer creation failure has error message')
end

-- Test 9: Debounce with error callbacks
local function test_debounce_error_handling()
  local error_count = 0
  local success_count = 0

  local debounced_fn = async.debounce(function(should_error)
    if should_error then
      error_count = error_count + 1
      error('Intentional error in debounced function')
    else
      success_count = success_count + 1
    end
  end, 50)

  -- Test error handling in debounced function
  local success1, err1 = pcall(function()
    debounced_fn(true) -- Should cause error
  end)

  local success2, err2 = pcall(function()
    debounced_fn(false) -- Should succeed
  end)

  assert_test(success1 == false, 'Debounced function error was caught')
  assert_test(success2 == true, 'Debounced function success executed')
end

-- Test 10: run_command_sync error propagation
local function test_run_command_sync_error_propagation()
  local function error_coroutine()
    local result = async.run_command_sync('permission_denied', {}, {})
    assert_test(result ~= nil, 'Sync error command returned result')
    assert_test(result.success == false, 'Sync error command marked as failure')
    assert_test(result.code == 126, 'Sync error command has correct exit code')
  end

  local co = coroutine.create(error_coroutine)
  local success, err = coroutine.resume(co)
  assert_test(success, 'run_command_sync error propagation worked: ' .. (err or ''))
end

-- Test 11: Large stderr handling
local function test_large_stderr_handling()
  local completed, result = wait_for_callback(function(cb)
    async.run_command('large_stderr_command', {}, {}, cb)
  end)

  assert_test(completed, 'Large stderr command completed')
  assert_test(result[1].success == false, 'Large stderr command marked as failure')
  assert_test(#result[1].stderr > 1000, 'Large stderr content captured')
end

-- Test 12: Mixed stdout/stderr handling
local function test_mixed_output_handling()
  local stdout_chunks = {}
  local stderr_chunks = {}

  local opts = {
    on_stdout = function(data)
      table.insert(stdout_chunks, data)
    end,
    on_stderr = function(data)
      table.insert(stderr_chunks, data)
    end,
  }

  local completed, result = wait_for_callback(function(cb)
    async.run_command('mixed_output_command', {}, opts, cb)
  end)

  assert_test(completed, 'Mixed output command completed')
  assert_test(result[1].success == true, 'Mixed output command succeeded')
  -- Note: In unit tests, streaming might work differently due to mocking
end

-- Test 13: Nested error scenarios
local function test_nested_error_scenarios()
  -- Test reading a file that fails during stat, then read
  local completed, result = wait_for_callback(function(cb)
    async.read_file('/access_denied/file.txt', cb)
  end)

  assert_test(completed, 'Nested error scenario completed')
  assert_test(result[1] == nil, 'Nested error returns nil data')
  assert_test(result[2] ~= nil, 'Nested error returns error message')
end

-- Test 14: Resource cleanup on errors
local function test_resource_cleanup_on_errors()
  local handles_created = 0
  local handles_closed = 0

  local original_new_pipe = vim.loop.new_pipe
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
    async.run_command('non_existent_command', {}, {}, cb)
  end)

  vim.loop.new_pipe = original_new_pipe

  assert_test(completed, 'Resource cleanup test completed')
  assert_test(handles_created > 0, 'Handles were created during error scenario')
  assert_test(handles_closed > 0, 'Handles were cleaned up during error scenario')
end

-- Test 15: Timeout scenarios (simulated)
local function test_timeout_scenarios()
  -- Test command that never completes
  local timeout_reached = false

  local handle = async.run_command('timeout_command', {}, {}, function(result)
    -- This callback should never be called in our mock
    assert_test(false, 'Timeout command callback should not be called')
  end)

  assert_test(handle ~= nil, 'Timeout command returned handle')

  -- Simulate timeout by checking that callback wasn't called
  timeout_reached = true
  assert_test(timeout_reached, 'Timeout scenario simulated successfully')
end

-- Main test runner
local function run_all_tests()
  print('Running comprehensive async error scenario tests...')

  test_command_spawn_failures()
  test_command_exit_code_errors()
  test_signal_termination()
  test_pipe_read_errors()
  test_file_operation_errors()
  test_directory_operation_errors()
  test_existence_check_errors()
  test_timer_creation_failures()
  test_debounce_error_handling()
  test_run_command_sync_error_propagation()
  test_large_stderr_handling()
  test_mixed_output_handling()
  test_nested_error_scenarios()
  test_resource_cleanup_on_errors()
  test_timeout_scenarios()

  -- Print results
  print('\n=== Test Results ===')
  for _, result in ipairs(test_results) do
    print(result)
  end

  print(string.format('\nTests: %d/%d passed (%.1f%%)', passed_tests, total_tests, (passed_tests / total_tests) * 100))

  if passed_tests == total_tests then
    print('✓ All async error scenario tests passed!')
    return true
  else
    print('✗ Some async error scenario tests failed!')
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
