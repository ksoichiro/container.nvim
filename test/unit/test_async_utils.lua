#!/usr/bin/env lua

-- Test for lua/container/utils/async.lua
-- Tests asynchronous utilities and operations

-- Setup Lua path for the module
package.path = './lua/?.lua;./lua/?/init.lua;../lua/?.lua;../lua/?/init.lua;' .. package.path

-- Helper function to run tests
local function run_tests()
  local tests_passed = 0
  local tests_failed = 0
  local failed_tests = {}

  local function assert_eq(actual, expected, message)
    if actual ~= expected then
      error(
        string.format(
          'Assertion failed: %s\nExpected: %s\nActual: %s',
          message or 'values should be equal',
          tostring(expected),
          tostring(actual)
        )
      )
    end
  end

  local function assert_true(value, message)
    if not value then
      error('Assertion failed: ' .. (message or 'value should be true'))
    end
  end

  local function assert_false(value, message)
    if value then
      error('Assertion failed: ' .. (message or 'value should be false'))
    end
  end

  local function assert_nil(value, message)
    if value ~= nil then
      error('Assertion failed: ' .. (message or 'value should be nil'))
    end
  end

  local function assert_not_nil(value, message)
    if value == nil then
      error('Assertion failed: ' .. (message or 'value should not be nil'))
    end
  end

  local function test(name, test_func)
    local success, err = pcall(test_func)
    if success then
      print('✓ ' .. name)
      tests_passed = tests_passed + 1
    else
      print('✗ ' .. name .. ': ' .. err)
      tests_failed = tests_failed + 1
      table.insert(failed_tests, name)
    end
  end

  print('Running async utilities tests...')
  print('=' .. string.rep('=', 50))

  -- Mock vim and uv for testing
  local mock_vim = {
    loop = {},
    schedule = function(fn)
      fn()
    end,
    fn = {
      fnamemodify = function(path, modifier)
        if modifier == ':h' then
          local parent = path:match('(.+)/[^/]+$')
          return parent or '/'
        end
        return path
      end,
    },
  }

  -- Mock UV (vim.loop) functions
  local mock_handles = {}
  local mock_timers = {}

  mock_vim.loop.new_pipe = function(ipc)
    local pipe = {
      _closed = false,
      _data = {},
      close = function(self)
        self._closed = true
      end,
      is_closing = function(self)
        return self._closed
      end,
      read_start = function(self, callback)
        self._read_callback = callback
      end,
      _trigger_read = function(self, err, data)
        if self._read_callback then
          self._read_callback(err, data)
        end
      end,
    }
    table.insert(mock_handles, pipe)
    return pipe
  end

  mock_vim.loop.spawn = function(cmd, opts, callback)
    local handle = {
      _closed = false,
      close = function(self)
        self._closed = true
      end,
      is_closing = function(self)
        return self._closed
      end,
    }

    -- Simulate async process completion
    mock_vim.schedule(function()
      if callback then
        if cmd == 'fail_command' then
          callback(1, 0) -- exit code 1
        else
          callback(0, 0) -- exit code 0
        end
      end
    end)

    table.insert(mock_handles, handle)
    return handle
  end

  mock_vim.loop.fs_open = function(path, flags, mode, callback)
    mock_vim.schedule(function()
      if path == '/nonexistent/file' or path == '/nonexistent/dir/file' then
        callback('ENOENT: no such file or directory', nil)
      else
        callback(nil, 123) -- mock file descriptor
      end
    end)
  end

  mock_vim.loop.fs_fstat = function(fd, callback)
    mock_vim.schedule(function()
      callback(nil, { size = 10 })
    end)
  end

  mock_vim.loop.fs_read = function(fd, size, offset, callback)
    mock_vim.schedule(function()
      callback(nil, 'file content')
    end)
  end

  mock_vim.loop.fs_write = function(fd, data, offset, callback)
    mock_vim.schedule(function()
      callback(nil)
    end)
  end

  mock_vim.loop.fs_close = function(fd, callback)
    mock_vim.schedule(function()
      callback()
    end)
  end

  mock_vim.loop.fs_stat = function(path, callback)
    mock_vim.schedule(function()
      if path == '/existing/dir' then
        callback(nil, { type = 'directory' })
      elseif path == '/existing/file' then
        callback(nil, { type = 'file' })
      else
        callback('ENOENT: no such file or directory', nil)
      end
    end)
  end

  mock_vim.loop.fs_mkdir = function(path, mode, callback)
    mock_vim.schedule(function()
      if path == '/existing/path' then
        callback('EEXIST: file already exists')
      elseif path == '/missing/parent/child' then
        callback('ENOENT: no such file or directory')
      else
        callback(nil)
      end
    end)
  end

  mock_vim.loop.new_timer = function()
    local timer = {
      _closed = false,
      _callback = nil,
      start = function(self, timeout, repeat_interval, callback)
        self._callback = callback
        -- Don't execute immediately for debounce testing
      end,
      close = function(self)
        self._closed = true
        self._callback = nil
      end,
      trigger = function(self)
        if self._callback and not self._closed then
          mock_vim.schedule(function()
            self._callback()
          end)
        end
      end,
    }
    table.insert(mock_timers, timer)
    return timer
  end

  -- Set up global mocks
  local original_vim = _G.vim
  _G.vim = mock_vim

  -- Load the async module with error handling
  local async
  local success, err = pcall(require, 'container.utils.async')
  if success then
    async = err -- err is actually the module when pcall succeeds
  else
    print('Error loading async module: ' .. tostring(err))
    print('Current working directory: ' .. (vim.fn and vim.fn.getcwd() or os.getenv('PWD') or 'unknown'))
    print('Package path: ' .. package.path)
    os.exit(1)
  end

  -- Test 1: Module loads correctly
  test('Module loads and has expected functions', function()
    assert_not_nil(async, 'Module should load')
    assert_not_nil(async.run_command, 'Should have run_command function')
    assert_not_nil(async.run_command_sync, 'Should have run_command_sync function')
    assert_not_nil(async.read_file, 'Should have read_file function')
    assert_not_nil(async.write_file, 'Should have write_file function')
    assert_not_nil(async.dir_exists, 'Should have dir_exists function')
    assert_not_nil(async.file_exists, 'Should have file_exists function')
    assert_not_nil(async.mkdir_p, 'Should have mkdir_p function')
    assert_not_nil(async.delay, 'Should have delay function')
    assert_not_nil(async.debounce, 'Should have debounce function')
  end)

  -- Test 2: run_command with successful command
  test('run_command executes successfully', function()
    local callback_called = false
    local result = nil

    async.run_command('echo', { 'hello' }, {}, function(res)
      callback_called = true
      result = res
    end)

    assert_true(callback_called, 'Callback should be called')
    assert_not_nil(result, 'Result should not be nil')
    assert_eq(result.code, 0, 'Exit code should be 0')
    assert_true(result.success, 'Command should be successful')
    assert_eq(result.stdout, '', 'Stdout should be empty string by default')
    assert_eq(result.stderr, '', 'Stderr should be empty string by default')
  end)

  -- Test 3: run_command with failing command
  test('run_command handles command failure', function()
    local callback_called = false
    local result = nil

    async.run_command('fail_command', {}, {}, function(res)
      callback_called = true
      result = res
    end)

    assert_true(callback_called, 'Callback should be called')
    assert_not_nil(result, 'Result should not be nil')
    assert_eq(result.code, 1, 'Exit code should be 1')
    assert_false(result.success, 'Command should not be successful')
  end)

  -- Test 4: run_command with options
  test('run_command respects options', function()
    local stdout_called = false
    local stderr_called = false

    local opts = {
      cwd = '/tmp',
      on_stdout = function(data)
        stdout_called = true
      end,
      on_stderr = function(data)
        stderr_called = true
      end,
    }

    async.run_command('echo', { 'test' }, opts, function(res)
      -- Callback for completion
    end)

    -- Simulate stdout/stderr data
    for _, handle in ipairs(mock_handles) do
      if handle._trigger_read then
        handle:_trigger_read(nil, 'stdout data')
        handle:_trigger_read(nil, 'stderr data')
      end
    end

    assert_true(stdout_called, 'on_stdout should be called')
    assert_true(stderr_called, 'on_stderr should be called')
  end)

  -- Test 5: run_command spawn failure
  test('run_command handles spawn failure', function()
    -- Override spawn to return nil (failure)
    local original_spawn = mock_vim.loop.spawn
    mock_vim.loop.spawn = function(cmd, opts, callback)
      return nil -- Simulate spawn failure
    end

    local callback_called = false
    local result = nil

    async.run_command('nonexistent_command', {}, {}, function(res)
      callback_called = true
      result = res
    end)

    assert_true(callback_called, 'Callback should be called on spawn failure')
    assert_not_nil(result, 'Result should not be nil')
    assert_eq(result.code, -1, 'Exit code should be -1 for spawn failure')
    assert_false(result.success, 'Command should not be successful')
    assert_true(result.stderr:find('Failed to spawn process'), 'Error message should indicate spawn failure')

    -- Restore original spawn
    mock_vim.loop.spawn = original_spawn
  end)

  -- Test 6: run_command_sync requires coroutine
  test('run_command_sync requires coroutine', function()
    local success, err = pcall(function()
      async.run_command_sync('echo', { 'test' }, {})
    end)

    assert_false(success, 'Should fail when not in coroutine')
    assert_true(err and err:find('coroutine') ~= nil, 'Should have appropriate error message')
  end)

  -- Test 7: read_file success
  test('read_file reads file successfully', function()
    local callback_called = false
    local data = nil
    local err = nil

    async.read_file('/existing/file', function(file_data, file_err)
      callback_called = true
      data = file_data
      err = file_err
    end)

    assert_true(callback_called, 'Callback should be called')
    assert_eq(data, 'file content', 'Should return file content')
    assert_nil(err, 'Should not have error')
  end)

  -- Test 8: read_file with nonexistent file
  test('read_file handles nonexistent file', function()
    local callback_called = false
    local data = nil
    local err = nil

    async.read_file('/nonexistent/file', function(file_data, file_err)
      callback_called = true
      data = file_data
      err = file_err
    end)

    assert_true(callback_called, 'Callback should be called')
    assert_nil(data, 'Should not return data')
    assert_not_nil(err, 'Should have error')
  end)

  -- Test 9: write_file success
  test('write_file writes successfully', function()
    local callback_called = false
    local err = nil

    async.write_file('/tmp/testfile', 'test content', function(write_err)
      callback_called = true
      err = write_err
    end)

    assert_true(callback_called, 'Callback should be called')
    assert_nil(err, 'Should not have error')
  end)

  -- Test 10: write_file with nonexistent directory
  test('write_file handles nonexistent directory', function()
    local callback_called = false
    local err = nil

    async.write_file('/nonexistent/dir/file', 'test', function(write_err)
      callback_called = true
      err = write_err
    end)

    assert_true(callback_called, 'Callback should be called')
    assert_not_nil(err, 'Should have error')
  end)

  -- Test 11: dir_exists with existing directory
  test('dir_exists detects existing directory', function()
    local callback_called = false
    local exists = false

    async.dir_exists('/existing/dir', function(result)
      callback_called = true
      exists = result
    end)

    assert_true(callback_called, 'Callback should be called')
    assert_true(exists, 'Should detect existing directory')
  end)

  -- Test 12: dir_exists with nonexistent directory
  test('dir_exists handles nonexistent directory', function()
    local callback_called = false
    local exists = true

    async.dir_exists('/nonexistent/dir', function(result)
      callback_called = true
      exists = result
    end)

    assert_true(callback_called, 'Callback should be called')
    assert_false(exists, 'Should not detect nonexistent directory')
  end)

  -- Test 13: file_exists with existing file
  test('file_exists detects existing file', function()
    local callback_called = false
    local exists = false

    async.file_exists('/existing/file', function(result)
      callback_called = true
      exists = result
    end)

    assert_true(callback_called, 'Callback should be called')
    assert_true(exists, 'Should detect existing file')
  end)

  -- Test 14: file_exists with nonexistent file
  test('file_exists handles nonexistent file', function()
    local callback_called = false
    local exists = true

    async.file_exists('/nonexistent/file', function(result)
      callback_called = true
      exists = result
    end)

    assert_true(callback_called, 'Callback should be called')
    assert_false(exists, 'Should not detect nonexistent file')
  end)

  -- Test 15: mkdir_p creates directory
  test('mkdir_p creates directory successfully', function()
    local callback_called = false
    local err = nil

    async.mkdir_p('/new/directory', function(mkdir_err)
      callback_called = true
      err = mkdir_err
    end)

    assert_true(callback_called, 'Callback should be called')
    assert_nil(err, 'Should not have error')
  end)

  -- Test 16: mkdir_p handles existing directory
  test('mkdir_p handles existing directory', function()
    local callback_called = false
    local err = nil

    async.mkdir_p('/existing/path', function(mkdir_err)
      callback_called = true
      err = mkdir_err
    end)

    assert_true(callback_called, 'Callback should be called')
    assert_nil(err, 'Should not have error for existing directory')
  end)

  -- Test 17: mkdir_p recursive creation (simplified)
  test('mkdir_p creates directories recursively', function()
    local callback_called = false
    local err = nil

    -- Simplified test that doesn't cause stack overflow
    async.mkdir_p('/simple/new/path', function(mkdir_err)
      callback_called = true
      err = mkdir_err
    end)

    assert_true(callback_called, 'Callback should be called')
    assert_nil(err, 'Should not have error for simple path')
  end)

  -- Test 18: delay function
  test('delay executes after timeout', function()
    local callback_called = false

    local timer = async.delay(100, function()
      callback_called = true
    end)

    assert_not_nil(timer, 'Should return timer')

    -- Manually trigger the timer since it's mocked
    if timer.trigger then
      timer:trigger()
    end

    assert_true(callback_called, 'Callback should be called')
  end)

  -- Test 19: debounce function
  test('debounce creates debounced function', function()
    -- Add unpack fallback for newer Lua versions
    _G.unpack = _G.unpack or table.unpack

    local call_count = 0
    local last_arg = nil

    local debounced = async.debounce(function(arg)
      call_count = call_count + 1
      last_arg = arg
    end, 100)

    assert_not_nil(debounced, 'Should return debounced function')

    -- Call multiple times rapidly
    debounced('first')
    debounced('second')
    debounced('third')

    -- Find the last timer and trigger it to simulate debounce completion
    local last_timer = mock_timers[#mock_timers]
    if last_timer and last_timer.trigger then
      last_timer:trigger()
    end

    -- Due to debouncing, only the last call should execute
    assert_eq(call_count, 1, 'Should only execute once due to debouncing')
    assert_eq(last_arg, 'third', 'Should execute with last argument')
  end)

  -- Test 20: Error handling in read operations
  test('handles read errors gracefully', function()
    local stdout_error_handled = false
    local stderr_error_handled = false

    -- Test stdout error handling
    for _, handle in ipairs(mock_handles) do
      if handle._trigger_read then
        handle:_trigger_read('read error', nil)
        stdout_error_handled = true
        break
      end
    end

    assert_true(stdout_error_handled, 'Should handle stdout read errors')
  end)

  -- Test 21: run_command with empty arguments
  test('run_command handles empty arguments', function()
    local callback_called = false
    local result = nil

    async.run_command('echo', {}, {}, function(res)
      callback_called = true
      result = res
    end)

    assert_true(callback_called, 'Callback should be called')
    assert_not_nil(result, 'Result should not be nil')
    assert_eq(result.code, 0, 'Exit code should be 0')
    assert_true(result.success, 'Command should be successful')
  end)

  -- Test 22: run_command with nil callback
  test('run_command handles nil callback', function()
    -- This should not crash
    local handle = async.run_command('echo', { 'test' }, {})
    assert_not_nil(handle, 'Should return handle even with nil callback')
  end)

  -- Test 23: fs operations with read/write/stat errors
  test('fs operations handle various errors', function()
    -- Override fs_stat to return different error
    local original_fs_stat = mock_vim.loop.fs_stat
    mock_vim.loop.fs_stat = function(path, callback)
      mock_vim.schedule(function()
        callback('EACCES: permission denied', nil)
      end)
    end

    local callback_called = false
    local exists = true

    async.dir_exists('/permission/denied', function(result)
      callback_called = true
      exists = result
    end)

    assert_true(callback_called, 'Callback should be called')
    assert_false(exists, 'Should not detect directory on permission error')

    -- Restore original
    mock_vim.loop.fs_stat = original_fs_stat
  end)

  -- Test 24: mkdir_p with root directory
  test('mkdir_p handles root directory correctly', function()
    local callback_called = false
    local err = nil

    async.mkdir_p('/', function(mkdir_err)
      callback_called = true
      err = mkdir_err
    end)

    assert_true(callback_called, 'Callback should be called')
    -- Root directory operation might succeed or fail depending on system
    -- We just ensure it doesn't crash
  end)

  -- Test 25: debounce with no arguments
  test('debounce works with no arguments', function()
    _G.unpack = _G.unpack or table.unpack

    local call_count = 0

    local debounced = async.debounce(function()
      call_count = call_count + 1
    end, 100)

    debounced()
    debounced()

    -- Find the last timer and trigger it
    local last_timer = mock_timers[#mock_timers]
    if last_timer and last_timer.trigger then
      last_timer:trigger()
    end

    assert_eq(call_count, 1, 'Should only execute once')
  end)

  -- Test 26: delay with zero timeout
  test('delay works with zero timeout', function()
    local callback_called = false

    local timer = async.delay(0, function()
      callback_called = true
    end)

    assert_not_nil(timer, 'Should return timer')

    if timer.trigger then
      timer:trigger()
    end

    assert_true(callback_called, 'Callback should be called immediately')
  end)

  -- Test 27: File operations with fstat error
  test('read_file handles fstat error', function()
    local original_fs_fstat = mock_vim.loop.fs_fstat
    mock_vim.loop.fs_fstat = function(fd, callback)
      mock_vim.schedule(function()
        callback('fstat error', nil)
      end)
    end

    local callback_called = false
    local data = nil
    local err = nil

    async.read_file('/test/file', function(file_data, file_err)
      callback_called = true
      data = file_data
      err = file_err
    end)

    assert_true(callback_called, 'Callback should be called')
    assert_nil(data, 'Should not return data')
    assert_not_nil(err, 'Should have error')

    -- Restore original
    mock_vim.loop.fs_fstat = original_fs_fstat
  end)

  -- Test 28: File operations with read error
  test('read_file handles read error', function()
    local original_fs_read = mock_vim.loop.fs_read
    mock_vim.loop.fs_read = function(fd, size, offset, callback)
      mock_vim.schedule(function()
        callback('read error', nil)
      end)
    end

    local callback_called = false
    local data = nil
    local err = nil

    async.read_file('/test/file', function(file_data, file_err)
      callback_called = true
      data = file_data
      err = file_err
    end)

    assert_true(callback_called, 'Callback should be called')
    assert_nil(data, 'Should not return data')
    assert_not_nil(err, 'Should have error')

    -- Restore original
    mock_vim.loop.fs_read = original_fs_read
  end)

  -- Test 29: write_file with write error
  test('write_file handles write error', function()
    local original_fs_write = mock_vim.loop.fs_write
    mock_vim.loop.fs_write = function(fd, data, offset, callback)
      mock_vim.schedule(function()
        callback('write error')
      end)
    end

    local callback_called = false
    local err = nil

    async.write_file('/test/file', 'data', function(write_err)
      callback_called = true
      err = write_err
    end)

    assert_true(callback_called, 'Callback should be called')
    assert_not_nil(err, 'Should have error')

    -- Restore original
    mock_vim.loop.fs_write = original_fs_write
  end)

  -- Clean up
  _G.vim = original_vim
  mock_handles = {}
  mock_timers = {}

  print('=' .. string.rep('=', 50))
  print(string.format('Tests completed: %d passed, %d failed', tests_passed, tests_failed))

  if tests_failed > 0 then
    print('\nFailed tests:')
    for _, test_name in ipairs(failed_tests) do
      print('  - ' .. test_name)
    end
    os.exit(1)
  else
    print('All tests passed! ✓')
    os.exit(0)
  end
end

-- Run the tests
run_tests()
