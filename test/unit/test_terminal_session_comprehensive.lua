#!/usr/bin/env lua

-- Comprehensive tests for Terminal Session Management
-- This test suite aims to achieve >70% coverage for lua/container/terminal/session.lua

-- Setup vim API mocking
_G.vim = {
  tbl_extend = function(behavior, ...)
    local result = {}
    local sources = { ... }
    for _, source in ipairs(sources) do
      if type(source) == 'table' then
        for k, v in pairs(source) do
          result[k] = v
        end
      end
    end
    return result
  end,
  api = {
    nvim_buf_is_valid = function(buf_id)
      -- Return false for buffer id 999 to simulate invalid buffer
      return buf_id ~= 999
    end,
    nvim_buf_delete = function(buf_id, opts)
      -- Mock successful buffer deletion
    end,
  },
  fn = {
    jobwait = function(jobs, timeout)
      -- Return running status for most jobs
      local results = {}
      for _, job_id in ipairs(jobs) do
        -- Job id 999 simulates stopped job
        results[#results + 1] = job_id == 999 and 0 or -1
      end
      return results
    end,
    jobstop = function(job_id)
      -- Mock successful job stop
      return true
    end,
  },
}

-- Mock utilities
package.loaded['container.utils.log'] = {
  debug = function(...) end,
  info = function(...) end,
  warn = function(...) end,
  error = function(...) end,
}

package.loaded['container.utils.fs'] = {
  ensure_directory = function(dir)
    return true
  end,
}

-- Set up package path
package.path = './lua/?.lua;./lua/?/init.lua;' .. package.path

-- Test utilities
local function assert_equal(actual, expected, message)
  if actual ~= expected then
    error(string.format('%s: expected %s, got %s', message or 'Assertion failed', tostring(expected), tostring(actual)))
  end
end

local function assert_not_nil(value, message)
  if value == nil then
    error(message or 'Expected non-nil value')
  end
end

local function assert_nil(value, message)
  if value ~= nil then
    error(string.format('%s: expected nil, got %s', message or 'Expected nil value', tostring(value)))
  end
end

local function assert_true(value, message)
  if not value then
    error(message or 'Expected true value')
  end
end

local function assert_false(value, message)
  if value then
    error(message or 'Expected false value')
  end
end

-- Helper to reset session manager state
local function reset_session_manager()
  -- Force reload the module to clear internal state
  package.loaded['container.terminal.session'] = nil
  local session_manager = require('container.terminal.session')
  session_manager.setup({})
  return session_manager
end

-- Test Session Class
local function test_session_creation()
  print('=== Testing Session Creation ===')

  local session_manager = reset_session_manager()

  -- Test valid session creation
  local session, err = session_manager.create_session('test_session_create', 'container123', {})
  assert_not_nil(session, 'Session should be created successfully')
  assert_nil(err, 'Error should be nil for valid session creation')
  assert_equal(session.name, 'test_session_create', 'Session name should match')
  assert_equal(session.container_id, 'container123', 'Container ID should match')
  assert_not_nil(session.created_at, 'Created time should be set')
  assert_not_nil(session.last_accessed, 'Last accessed time should be set')

  -- Test invalid session creation - empty name
  local session2, err2 = session_manager.create_session('', 'container123', {})
  assert_nil(session2, 'Session should not be created with empty name')
  assert_not_nil(err2, 'Error should be returned for empty name')

  -- Test invalid session creation - nil name
  local session3, err3 = session_manager.create_session(nil, 'container123', {})
  assert_nil(session3, 'Session should not be created with nil name')
  assert_not_nil(err3, 'Error should be returned for nil name')

  -- Test invalid session creation - missing container ID
  local session4, err4 = session_manager.create_session('test_session2', nil, {})
  assert_nil(session4, 'Session should not be created without container ID')
  assert_not_nil(err4, 'Error should be returned for missing container ID')

  -- Set valid buffer and job for duplicate test
  session.buffer_id = 1
  session.job_id = 1

  -- Test duplicate session creation
  local session5, err5 = session_manager.create_session('test_session_create', 'container456', {})
  assert_nil(session5, 'Duplicate session should not be created')
  assert_not_nil(err5, 'Error should be returned for duplicate session')

  print('✓ Session creation tests passed')
end

local function test_session_validity()
  print('=== Testing Session Validity ===')

  local session_manager = reset_session_manager()

  -- Create a test session
  local session, _ = session_manager.create_session('validity_test', 'container123', {})

  -- Test session without buffer and job (invalid)
  assert_false(session:is_valid(), 'Session without buffer/job should be invalid')

  -- Set valid buffer and job
  session.buffer_id = 1
  session.job_id = 1
  assert_true(session:is_valid(), 'Session with valid buffer/job should be valid')

  -- Test with invalid buffer
  session.buffer_id = 999 -- This will return false from nvim_buf_is_valid mock
  assert_false(session:is_valid(), 'Session with invalid buffer should be invalid')

  -- Reset to valid buffer and test with stopped job
  session.buffer_id = 1
  session.job_id = 999 -- This will return 0 (stopped) from jobwait mock
  assert_false(session:is_valid(), 'Session with stopped job should be invalid')

  print('✓ Session validity tests passed')
end

local function test_session_methods()
  print('=== Testing Session Methods ===')

  local session_manager = reset_session_manager()

  -- Create a test session
  local session, _ = session_manager.create_session('methods_test', 'container123', {})
  session.buffer_id = 1
  session.job_id = 1

  -- Test update_access_time
  local original_time = session.last_accessed
  -- Simulate time passage
  session.last_accessed = original_time - 10
  session:update_access_time()
  assert_true(session.last_accessed >= original_time, 'Access time should be updated')

  -- Test get_display_name
  local display_name = session:get_display_name()
  assert_not_nil(display_name, 'Display name should not be nil')
  assert_true(display_name:find('methods_test'), 'Display name should contain session name')

  -- Test close method
  session:close(false)
  assert_nil(session.job_id, 'Job ID should be nil after close')
  assert_nil(session.buffer_id, 'Buffer ID should be nil after close')

  print('✓ Session methods tests passed')
end

local function test_session_manager_setup()
  print('=== Testing Session Manager Setup ===')

  local session_manager = reset_session_manager()

  -- Test setup with minimal config
  session_manager.setup({})

  -- Test setup with full config
  local config = {
    persistent_history = true,
    history_dir = '/test/history',
    max_history_lines = 1000,
    close_on_exit = true,
  }
  session_manager.setup(config)
  assert_equal(session_manager.config.persistent_history, true, 'Config should be stored')

  print('✓ Session manager setup tests passed')
end

local function test_session_retrieval()
  print('=== Testing Session Retrieval ===')

  local session_manager = reset_session_manager()

  -- Create a valid session
  local session, _ = session_manager.create_session('retrieval_test', 'container123', {})
  session.buffer_id = 1
  session.job_id = 1

  -- Test get_session with valid session
  local retrieved = session_manager.get_session('retrieval_test')
  assert_not_nil(retrieved, 'Should retrieve valid session')
  assert_equal(retrieved.name, 'retrieval_test', 'Retrieved session should match')

  -- Test get_session with non-existent session
  local not_found = session_manager.get_session('non_existent')
  assert_nil(not_found, 'Should return nil for non-existent session')

  -- Create an invalid session (will be cleaned up on retrieval)
  local invalid_session, _ = session_manager.create_session('invalid_test', 'container456', {})
  invalid_session.buffer_id = 999 -- Invalid buffer
  invalid_session.job_id = 999 -- Stopped job

  local retrieved_invalid = session_manager.get_session('invalid_test')
  assert_nil(retrieved_invalid, 'Invalid session should be cleaned up and return nil')

  print('✓ Session retrieval tests passed')
end

local function test_session_listing()
  print('=== Testing Session Listing ===')

  local session_manager = reset_session_manager()

  -- Create multiple sessions
  local session1, _ = session_manager.create_session('list_test1', 'container1', {})
  session1.buffer_id = 1
  session1.job_id = 1

  local session2, _ = session_manager.create_session('list_test2', 'container2', {})
  session2.buffer_id = 2
  session2.job_id = 2

  -- Create an invalid session
  local session3, _ = session_manager.create_session('list_test3', 'container3', {})
  session3.buffer_id = 999 -- Invalid
  session3.job_id = 999 -- Stopped

  -- Test list_sessions
  local sessions = session_manager.list_sessions()
  assert_equal(#sessions, 2, 'Should return 2 valid sessions')

  -- Sessions should be sorted by last_accessed (most recent first)
  assert_true(sessions[1].last_accessed >= sessions[2].last_accessed, 'Sessions should be sorted by access time')

  print('✓ Session listing tests passed')
end

local function test_active_session_management()
  print('=== Testing Active Session Management ===')

  local session_manager = reset_session_manager()

  -- Test get_active_session with no active session
  local active = session_manager.get_active_session()
  assert_nil(active, 'Should return nil when no active session')

  -- Create a session and set it as active
  local session, _ = session_manager.create_session('active_test', 'container123', {})
  session.buffer_id = 1
  session.job_id = 1

  session_manager.set_active_session(session)
  local retrieved_active = session_manager.get_active_session()
  assert_not_nil(retrieved_active, 'Should return active session')
  assert_equal(retrieved_active.name, 'active_test', 'Active session should match')

  -- Test set_active_session with invalid session
  session_manager.set_active_session(nil)
  assert_nil(session_manager.get_active_session(), 'Active session should be nil after setting to nil')

  -- Test with invalid session object
  local invalid_session = {
    name = 'invalid',
    is_valid = function()
      return false
    end,
  }
  session_manager.set_active_session(invalid_session)
  assert_nil(session_manager.get_active_session(), 'Active session should be nil for invalid session')

  print('✓ Active session management tests passed')
end

local function test_session_closing()
  print('=== Testing Session Closing ===')

  local session_manager = reset_session_manager()

  -- Create a session to close
  local session, _ = session_manager.create_session('close_test', 'container123', {})
  session.buffer_id = 1
  session.job_id = 1

  -- Set as active session
  session_manager.set_active_session(session)

  -- Test close_session
  local success, err = session_manager.close_session('close_test', false)
  assert_true(success, 'Session closing should succeed')
  assert_nil(err, 'Error should be nil for successful close')

  -- Verify session is removed
  local retrieved = session_manager.get_session('close_test')
  assert_nil(retrieved, 'Closed session should not be retrievable')

  -- Verify active session is cleared
  assert_nil(session_manager.get_active_session(), 'Active session should be cleared')

  -- Test closing non-existent session
  local success2, err2 = session_manager.close_session('non_existent', false)
  assert_false(success2, 'Closing non-existent session should fail')
  assert_not_nil(err2, 'Error should be returned for non-existent session')

  print('✓ Session closing tests passed')
end

local function test_close_all_sessions()
  print('=== Testing Close All Sessions ===')

  local session_manager = reset_session_manager()

  -- Create multiple sessions
  local session1, _ = session_manager.create_session('all_test1', 'container1', {})
  session1.buffer_id = 1
  session1.job_id = 1

  local session2, _ = session_manager.create_session('all_test2', 'container2', {})
  session2.buffer_id = 2
  session2.job_id = 2

  session_manager.set_active_session(session1)

  -- Test close_all_sessions
  local count = session_manager.close_all_sessions(true)
  assert_equal(count, 2, 'Should close 2 sessions')

  -- Verify all sessions are closed
  local sessions = session_manager.list_sessions()
  assert_equal(#sessions, 0, 'No sessions should remain')

  -- Verify active session is cleared
  assert_nil(session_manager.get_active_session(), 'Active session should be cleared')

  print('✓ Close all sessions tests passed')
end

local function test_session_navigation()
  print('=== Testing Session Navigation ===')

  local session_manager = reset_session_manager()

  -- Test with no sessions
  local next_session = session_manager.get_next_session('current')
  assert_nil(next_session, 'Should return nil when no sessions exist')

  local prev_session = session_manager.get_prev_session('current')
  assert_nil(prev_session, 'Should return nil when no sessions exist')

  -- Create single session
  local session1, _ = session_manager.create_session('nav_test1', 'container1', {})
  session1.buffer_id = 1
  session1.job_id = 1

  -- Test with single session
  next_session = session_manager.get_next_session('nav_test1')
  assert_nil(next_session, 'Should return nil for single session')

  prev_session = session_manager.get_prev_session('nav_test1')
  assert_nil(prev_session, 'Should return nil for single session')

  -- Create multiple sessions
  local session2, _ = session_manager.create_session('nav_test2', 'container2', {})
  session2.buffer_id = 2
  session2.job_id = 2

  local session3, _ = session_manager.create_session('nav_test3', 'container3', {})
  session3.buffer_id = 3
  session3.job_id = 3

  -- Test navigation with multiple sessions
  next_session = session_manager.get_next_session('nav_test1')
  assert_not_nil(next_session, 'Should return next session')

  prev_session = session_manager.get_prev_session('nav_test1')
  assert_not_nil(prev_session, 'Should return previous session')

  -- Test navigation with non-existent current session
  next_session = session_manager.get_next_session('non_existent')
  assert_not_nil(next_session, 'Should return first session for non-existent current')

  prev_session = session_manager.get_prev_session('non_existent')
  assert_not_nil(prev_session, 'Should return first session for non-existent current')

  print('✓ Session navigation tests passed')
end

local function test_unique_name_generation()
  print('=== Testing Unique Name Generation ===')

  local session_manager = reset_session_manager()

  -- Test with available base name
  local unique_name = session_manager.generate_unique_name('terminal')
  assert_equal(unique_name, 'terminal', 'Should return base name when available')

  -- Create session with base name
  local session1, _ = session_manager.create_session('terminal', 'container1', {})

  -- Test with occupied base name
  unique_name = session_manager.generate_unique_name('terminal')
  assert_equal(unique_name, 'terminal_1', 'Should append _1 when base name is taken')

  -- Create session with first variant
  local session2, _ = session_manager.create_session('terminal_1', 'container2', {})

  -- Test with multiple occupied variants
  unique_name = session_manager.generate_unique_name('terminal')
  assert_equal(unique_name, 'terminal_2', 'Should append _2 when terminal_1 is taken')

  -- Test with nil base name (should start with base name since we reset the session manager)
  unique_name = session_manager.generate_unique_name(nil)
  assert_equal(unique_name, 'terminal_2', 'Should use default base name when nil provided')

  print('✓ Unique name generation tests passed')
end

local function test_session_stats()
  print('=== Testing Session Stats ===')

  local session_manager = reset_session_manager()

  -- Test with no sessions
  local stats = session_manager.get_session_stats()
  assert_equal(stats.total, 0, 'Total should be 0 with no sessions')
  assert_equal(stats.active, 0, 'Active should be 0 with no sessions')
  assert_equal(stats.inactive, 0, 'Inactive should be 0 with no sessions')
  assert_equal(#stats.sessions, 0, 'Sessions list should be empty')

  -- Create valid session
  local session1, _ = session_manager.create_session('stats_test1', 'container123456789', {})
  session1.buffer_id = 1
  session1.job_id = 1

  -- Create invalid session
  local session2, _ = session_manager.create_session('stats_test2', 'container987654321', {})
  session2.buffer_id = 999 -- Invalid buffer
  session2.job_id = 999 -- Stopped job

  -- Test stats with mixed sessions
  stats = session_manager.get_session_stats()
  assert_equal(stats.total, 2, 'Total should be 2')
  assert_equal(stats.active, 1, 'Active should be 1')
  assert_equal(stats.inactive, 1, 'Inactive should be 1')
  assert_equal(#stats.sessions, 2, 'Sessions list should contain 2 entries')

  -- Check session details in stats
  local found_valid = false
  local found_invalid = false
  for _, session_stat in ipairs(stats.sessions) do
    if session_stat.name == 'stats_test1' then
      found_valid = true
      assert_true(session_stat.valid, 'stats_test1 should be valid')
      assert_equal(session_stat.container, 'container123', 'Container ID should be truncated')
    elseif session_stat.name == 'stats_test2' then
      found_invalid = true
      assert_false(session_stat.valid, 'stats_test2 should be invalid')
    end
  end
  assert_true(found_valid, 'Should find valid session in stats')
  assert_true(found_invalid, 'Should find invalid session in stats')

  print('✓ Session stats tests passed')
end

local function test_session_config_inheritance()
  print('=== Testing Session Config Inheritance ===')

  local session_manager = reset_session_manager()

  -- Setup manager with default config
  local default_config = {
    close_on_exit = true,
    persistent_history = false,
  }
  session_manager.setup(default_config)

  -- Create session with custom config
  local custom_config = {
    close_on_exit = false,
    auto_insert = true,
  }
  local session, _ = session_manager.create_session('config_test', 'container123', custom_config)

  -- Test config inheritance and override
  assert_false(session.config.close_on_exit, 'Custom config should override default')
  assert_true(session.config.auto_insert, 'Custom config should be preserved')
  assert_false(session.config.persistent_history, 'Default config should be inherited')

  print('✓ Session config inheritance tests passed')
end

local function test_session_close_with_config()
  print('=== Testing Session Close with Config ===')

  local session_manager = reset_session_manager()

  -- Create session with close_on_exit = true
  local session1, _ = session_manager.create_session('close_config_test1', 'container123', { close_on_exit = true })
  session1.buffer_id = 1
  session1.job_id = 1

  -- Test close without force (should use config)
  session1:close(false)
  -- This should have deleted the buffer according to config

  -- Create session with close_on_exit = false
  local session2, _ = session_manager.create_session('close_config_test2', 'container456', { close_on_exit = false })
  session2.buffer_id = 2
  session2.job_id = 2

  -- Test close with force override
  session2:close(true)
  -- This should have deleted the buffer despite config

  print('✓ Session close with config tests passed')
end

-- Main test runner
local function run_all_tests()
  print('Running Comprehensive Terminal Session Tests...\n')

  local tests = {
    test_session_creation,
    test_session_validity,
    test_session_methods,
    test_session_manager_setup,
    test_session_retrieval,
    test_session_listing,
    test_active_session_management,
    test_session_closing,
    test_close_all_sessions,
    test_session_navigation,
    test_unique_name_generation,
    test_session_stats,
    test_session_config_inheritance,
    test_session_close_with_config,
  }

  local passed = 0
  local total = #tests

  for _, test in ipairs(tests) do
    local success, error_message = pcall(test)
    if success then
      passed = passed + 1
    else
      print('✗ Test failed: ' .. error_message)
    end
  end

  print(string.format('\n=== Test Results ==='))
  print(string.format('Passed: %d/%d', passed, total))

  if passed == total then
    print('All tests passed! ✓')
    return 0
  else
    print('Some tests failed! ✗')
    return 1
  end
end

-- Run the tests
local exit_code = run_all_tests()
os.exit(exit_code)
