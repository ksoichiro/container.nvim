#!/usr/bin/env lua

-- Comprehensive tests for Terminal Display Management
-- This test suite aims to achieve >70% coverage for lua/container/terminal/display.lua

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
    nvim_create_buf = function(listed, scratch)
      -- Return incrementing buffer IDs
      if not _G.buffer_id_counter then
        _G.buffer_id_counter = 1
      end
      local buf_id = _G.buffer_id_counter
      _G.buffer_id_counter = _G.buffer_id_counter + 1
      return buf_id
    end,
    nvim_get_current_win = function()
      return _G.current_win_id or 1000
    end,
    nvim_win_set_buf = function(win_id, buf_id)
      -- Mock setting buffer to window
    end,
    nvim_open_win = function(buf_id, enter, config)
      -- Return window ID
      if not _G.win_id_counter then
        _G.win_id_counter = 2000
      end
      local win_id = _G.win_id_counter
      _G.win_id_counter = _G.win_id_counter + 1
      return win_id
    end,
    nvim_buf_set_lines = function(buf_id, start, end_, strict, lines)
      -- Mock setting buffer lines
    end,
    nvim_buf_set_option = function(buf_id, option, value)
      -- Mock setting buffer options
    end,
    nvim_buf_set_name = function(buf_id, name)
      -- Mock setting buffer name
      _G.buffer_names = _G.buffer_names or {}
      _G.buffer_names[buf_id] = name
    end,
    nvim_create_augroup = function(name, opts)
      -- Mock creating augroup
      return 'group_' .. name
    end,
    nvim_create_autocmd = function(event, opts)
      -- Mock creating autocmd
      if opts.callback then
        -- Store for later trigger if needed
        _G.autocmds = _G.autocmds or {}
        table.insert(_G.autocmds, { event = event, opts = opts })
      end
    end,
    nvim_buf_set_keymap = function(buf_id, mode, lhs, rhs, opts)
      -- Mock setting buffer keymap
      _G.keymaps = _G.keymaps or {}
      _G.keymaps[buf_id] = _G.keymaps[buf_id] or {}
      table.insert(_G.keymaps[buf_id], { mode = mode, lhs = lhs, rhs = rhs, opts = opts })
    end,
    nvim_list_wins = function()
      -- Return mock window list
      return _G.mock_windows or { 1000, 1001, 1002 }
    end,
    nvim_win_get_buf = function(win_id)
      -- Mock getting buffer from window
      _G.win_buf_map = _G.win_buf_map or {}
      return _G.win_buf_map[win_id] or 1
    end,
    nvim_set_current_win = function(win_id)
      -- Mock setting current window
      _G.current_win_id = win_id
    end,
  },
  cmd = function(command)
    -- Mock vim command execution
    _G.executed_commands = _G.executed_commands or {}
    table.insert(_G.executed_commands, command)

    -- Handle specific commands
    if command == 'tabnew' then
      _G.current_win_id = _G.current_win_id and (_G.current_win_id + 1) or 1001
    elseif command:match('^belowright %d+ new$') then
      _G.current_win_id = _G.current_win_id and (_G.current_win_id + 1) or 1002
    elseif command == 'startinsert' then
      -- Mock entering insert mode
    elseif command == 'close' then
      -- Mock closing window
    end
  end,
  o = {
    columns = 120,
    lines = 40,
  },
  bo = {
    buftype = '',
  },
}

-- Mock utilities
package.loaded['container.utils.log'] = {
  debug = function(...) end,
  info = function(...) end,
  warn = function(...) end,
  error = function(...) end,
}

-- Mock terminal session manager
package.loaded['container.terminal.session'] = {
  set_active_session = function(session)
    _G.active_session = session
  end,
}

-- Mock container terminal module
package.loaded['container.terminal'] = {
  new_session = function()
    return true
  end,
  list_sessions = function()
    return true
  end,
  next_session = function()
    return true
  end,
  prev_session = function()
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

local function assert_contains(str, substr, message)
  if not str or not str:find(substr, 1, true) then
    error(
      string.format(
        '%s: "%s" should contain "%s"',
        message or 'String should contain substring',
        tostring(str),
        tostring(substr)
      )
    )
  end
end

-- Helper to reset global state
local function reset_state()
  _G.buffer_id_counter = nil
  _G.win_id_counter = nil
  _G.current_win_id = nil
  _G.buffer_names = nil
  _G.autocmds = nil
  _G.keymaps = nil
  _G.executed_commands = nil
  _G.win_buf_map = nil
  _G.active_session = nil
  _G.mock_windows = nil
end

-- Helper to create a mock session
local function create_mock_session(name, container_id, config)
  config = config or {}
  return {
    name = name or 'test_session',
    container_id = container_id or 'container123',
    config = vim.tbl_extend('force', {
      default_position = 'split',
      split_command = 'belowright 15',
      auto_insert = false,
      keymaps = {
        close = '<C-d>',
        escape = '<C-\\><C-n>',
        new_session = '<C-n>',
        list_sessions = '<C-l>',
        next_session = '<C-j>',
        prev_session = '<C-k>',
      },
      float = {
        width = 0.8,
        height = 0.6,
        border = 'rounded',
        title = 'Container Terminal',
        title_pos = 'center',
      },
    }, config),
    buffer_id = nil,
    window_id = nil,
    is_valid = function(self)
      return self.buffer_id ~= nil
    end,
  }
end

-- Test create_terminal_buffer function
local function test_create_terminal_buffer()
  print('=== Testing create_terminal_buffer ===')

  reset_state()
  local display = require('container.terminal.display')

  -- Test split position (default)
  local session = create_mock_session('test_split')
  local buf_id, win_id, err = display.create_terminal_buffer(session, nil, {})

  assert_not_nil(buf_id, 'Buffer ID should be returned')
  assert_not_nil(win_id, 'Window ID should be returned')
  assert_nil(err, 'Error should be nil for successful creation')

  -- Test explicit split position
  reset_state()
  buf_id, win_id, err = display.create_terminal_buffer(session, 'split', {})
  assert_not_nil(buf_id, 'Buffer ID should be returned for split position')
  assert_not_nil(win_id, 'Window ID should be returned for split position')
  assert_nil(err, 'Error should be nil for split position')

  -- Test tab position
  reset_state()
  buf_id, win_id, err = display.create_terminal_buffer(session, 'tab', {})
  assert_not_nil(buf_id, 'Buffer ID should be returned for tab position')
  assert_not_nil(win_id, 'Window ID should be returned for tab position')
  assert_nil(err, 'Error should be nil for tab position')

  -- Test float position
  reset_state()
  buf_id, win_id, err = display.create_terminal_buffer(session, 'float', {})
  assert_not_nil(buf_id, 'Buffer ID should be returned for float position')
  assert_not_nil(win_id, 'Window ID should be returned for float position')
  assert_nil(err, 'Error should be nil for float position')

  -- Test unknown position
  reset_state()
  buf_id, win_id, err = display.create_terminal_buffer(session, 'unknown', {})
  assert_nil(buf_id, 'Buffer ID should be nil for unknown position')
  assert_nil(win_id, 'Window ID should be nil for unknown position')
  assert_not_nil(err, 'Error should be returned for unknown position')
  assert_contains(err, 'Unknown position', 'Error should mention unknown position')

  print('✓ create_terminal_buffer tests passed')
end

-- Test _create_split_terminal function
local function test_create_split_terminal()
  print('=== Testing _create_split_terminal ===')

  reset_state()
  local display = require('container.terminal.display')

  -- Test with default split command
  local session = create_mock_session('test_split')
  local buf_id, win_id = display._create_split_terminal(session, {})

  assert_not_nil(buf_id, 'Buffer ID should be returned')
  assert_not_nil(win_id, 'Window ID should be returned')
  assert_true(#_G.executed_commands > 0, 'Commands should be executed')

  -- Test with custom split command
  reset_state()
  session.config.split_command = 'rightbelow 20'
  buf_id, win_id = display._create_split_terminal(session, {})

  assert_not_nil(buf_id, 'Buffer ID should be returned for custom split')
  assert_not_nil(win_id, 'Window ID should be returned for custom split')

  -- Test with split command that already includes 'new'
  reset_state()
  session.config.split_command = 'belowright 10 new'
  buf_id, win_id = display._create_split_terminal(session, {})

  assert_not_nil(buf_id, 'Buffer ID should be returned for split with new')
  assert_not_nil(win_id, 'Window ID should be returned for split with new')

  print('✓ _create_split_terminal tests passed')
end

-- Test _create_tab_terminal function
local function test_create_tab_terminal()
  print('=== Testing _create_tab_terminal ===')

  reset_state()
  local display = require('container.terminal.display')

  local session = create_mock_session('test_tab')
  local buf_id, win_id = display._create_tab_terminal(session, {})

  assert_not_nil(buf_id, 'Buffer ID should be returned')
  assert_not_nil(win_id, 'Window ID should be returned')

  -- Check that tabnew command was executed
  local tabnew_executed = false
  for _, cmd in ipairs(_G.executed_commands or {}) do
    if cmd == 'tabnew' then
      tabnew_executed = true
      break
    end
  end
  assert_true(tabnew_executed, 'tabnew command should be executed')

  print('✓ _create_tab_terminal tests passed')
end

-- Test _create_float_terminal function
local function test_create_float_terminal()
  print('=== Testing _create_float_terminal ===')

  reset_state()
  local display = require('container.terminal.display')

  -- Test with default float config
  local session = create_mock_session('test_float')
  local buf_id, win_id = display._create_float_terminal(session, {})

  assert_not_nil(buf_id, 'Buffer ID should be returned')
  assert_not_nil(win_id, 'Window ID should be returned')

  -- Test with custom width/height in opts
  reset_state()
  buf_id, win_id = display._create_float_terminal(session, { width = 100, height = 30 })

  assert_not_nil(buf_id, 'Buffer ID should be returned for custom size')
  assert_not_nil(win_id, 'Window ID should be returned for custom size')

  -- Test with fractional width/height
  reset_state()
  session.config.float.width = 0.5
  session.config.float.height = 0.7
  buf_id, win_id = display._create_float_terminal(session, {})

  assert_not_nil(buf_id, 'Buffer ID should be returned for fractional size')
  assert_not_nil(win_id, 'Window ID should be returned for fractional size')

  -- Test with integer width/height
  reset_state()
  session.config.float.width = 80
  session.config.float.height = 25
  buf_id, win_id = display._create_float_terminal(session, {})

  assert_not_nil(buf_id, 'Buffer ID should be returned for integer size')
  assert_not_nil(win_id, 'Window ID should be returned for integer size')

  print('✓ _create_float_terminal tests passed')
end

-- Test _configure_terminal_buffer function
local function test_configure_terminal_buffer()
  print('=== Testing _configure_terminal_buffer ===')

  reset_state()
  local display = require('container.terminal.display')

  local session = create_mock_session('test_config')
  local buf_id = 1

  display._configure_terminal_buffer(buf_id, session)

  -- Check that buffer name was set
  assert_not_nil(_G.buffer_names, 'Buffer names should be tracked')
  assert_not_nil(_G.buffer_names[buf_id], 'Buffer name should be set')
  assert_contains(_G.buffer_names[buf_id], 'DevContainer', 'Buffer name should contain DevContainer')
  assert_contains(_G.buffer_names[buf_id], session.name, 'Buffer name should contain session name')

  -- Check that autocmds were created
  assert_not_nil(_G.autocmds, 'Autocmds should be created')
  assert_true(#_G.autocmds > 0, 'At least one autocmd should be created')

  -- Test with auto_insert enabled
  reset_state()
  session.config.auto_insert = true
  display._configure_terminal_buffer(buf_id, session)

  assert_not_nil(_G.autocmds, 'Autocmds should be created with auto_insert')

  print('✓ _configure_terminal_buffer tests passed')
end

-- Test _setup_terminal_keymaps function
local function test_setup_terminal_keymaps()
  print('=== Testing _setup_terminal_keymaps ===')

  reset_state()
  local display = require('container.terminal.display')

  local session = create_mock_session('test_keymaps')
  local buf_id = 1

  display._setup_terminal_keymaps(buf_id, session)

  -- Check that keymaps were set
  assert_not_nil(_G.keymaps, 'Keymaps should be tracked')
  assert_not_nil(_G.keymaps[buf_id], 'Keymaps should be set for buffer')
  assert_true(#_G.keymaps[buf_id] > 0, 'At least one keymap should be set')

  -- Test with empty keymaps
  reset_state()
  session.config.keymaps = {}
  display._setup_terminal_keymaps(buf_id, session)

  -- Should still work with empty keymaps

  -- Test with nil keymaps
  reset_state()
  session.config.keymaps = nil
  display._setup_terminal_keymaps(buf_id, session)

  -- Should work with nil keymaps

  print('✓ _setup_terminal_keymaps tests passed')
end

-- Test switch_to_session function
local function test_switch_to_session()
  print('=== Testing switch_to_session ===')

  reset_state()
  local display = require('container.terminal.display')

  -- Test with nil session
  local success, err = display.switch_to_session(nil)
  assert_false(success, 'Should fail with nil session')
  assert_not_nil(err, 'Error should be returned for nil session')

  -- Test with invalid session
  local invalid_session = {
    is_valid = function()
      return false
    end,
  }
  success, err = display.switch_to_session(invalid_session)
  assert_false(success, 'Should fail with invalid session')
  assert_not_nil(err, 'Error should be returned for invalid session')

  -- Test with valid session that has existing window
  local session = create_mock_session('test_switch')
  session.buffer_id = 1
  session.is_valid = function()
    return true
  end

  -- Mock existing window for the buffer
  _G.win_buf_map = { [1000] = 1 }

  success, err = display.switch_to_session(session)
  assert_true(success, 'Should succeed with valid session')
  assert_nil(err, 'Error should be nil for valid session')
  assert_equal(_G.current_win_id, 1000, 'Should focus existing window')

  -- Test with valid session that needs new window
  reset_state()
  session.buffer_id = 2
  _G.win_buf_map = {} -- No existing window for buffer 2

  success, err = display.switch_to_session(session)
  assert_true(success, 'Should succeed when creating new window')
  assert_nil(err, 'Error should be nil when creating new window')

  -- Test with auto_insert enabled
  reset_state()
  session.config.auto_insert = true
  session.buffer_id = 3
  _G.win_buf_map = {}

  success, err = display.switch_to_session(session)
  assert_true(success, 'Should succeed with auto_insert')
  assert_nil(err, 'Error should be nil with auto_insert')

  -- Check that startinsert command was executed
  local startinsert_executed = false
  for _, cmd in ipairs(_G.executed_commands or {}) do
    if cmd == 'startinsert' then
      startinsert_executed = true
      break
    end
  end
  assert_true(startinsert_executed, 'startinsert should be executed with auto_insert')

  print('✓ switch_to_session tests passed')
end

-- Test build_terminal_command function
local function test_build_terminal_command()
  print('=== Testing build_terminal_command ===')

  local display = require('container.terminal.display')

  -- Test basic command
  local cmd = display.build_terminal_command('container123', nil, nil)
  assert_not_nil(cmd, 'Command should be returned')
  assert_equal(cmd[1], 'docker', 'First argument should be docker')
  assert_equal(cmd[2], 'exec', 'Second argument should be exec')
  assert_equal(cmd[3], '-it', 'Third argument should be -it')
  assert_equal(cmd[#cmd - 1], 'container123', 'Container ID should be second to last')
  assert_equal(cmd[#cmd], '/bin/sh', 'Default shell should be /bin/sh')

  -- Test with custom shell
  cmd = display.build_terminal_command('container456', '/bin/bash', nil)
  assert_equal(cmd[#cmd], '/bin/bash', 'Custom shell should be used')

  -- Test with environment variables
  local env = { 'DEBUG=true', 'NODE_ENV=development' }
  cmd = display.build_terminal_command('container789', '/bin/zsh', env)

  -- Check that environment variables are included
  local has_debug = false
  local has_node_env = false
  for i, arg in ipairs(cmd) do
    if arg == '-e' and cmd[i + 1] == 'DEBUG=true' then
      has_debug = true
    elseif arg == '-e' and cmd[i + 1] == 'NODE_ENV=development' then
      has_node_env = true
    end
  end
  assert_true(has_debug, 'DEBUG environment variable should be included')
  assert_true(has_node_env, 'NODE_ENV environment variable should be included')
  assert_equal(cmd[#cmd], '/bin/zsh', 'Custom shell should be used with environment')

  -- Test with empty environment
  cmd = display.build_terminal_command('container101', '/bin/fish', {})
  assert_equal(cmd[#cmd], '/bin/fish', 'Custom shell should be used with empty environment')

  print('✓ build_terminal_command tests passed')
end

-- Test format_session_list function
local function test_format_session_list()
  print('=== Testing format_session_list ===')

  local display = require('container.terminal.display')

  -- Test with empty list
  local formatted = display.format_session_list({})
  assert_not_nil(formatted, 'Formatted list should be returned')
  assert_equal(#formatted, 0, 'Empty list should return empty formatted list')

  -- Create mock sessions
  local sessions = {
    {
      name = 'session1',
      container_id = 'container123456789012',
      last_accessed = os.time() - 3600, -- 1 hour ago
      is_valid = function()
        return true
      end,
    },
    {
      name = 'session2',
      container_id = 'container987654321098',
      last_accessed = os.time() - 7200, -- 2 hours ago
      is_valid = function()
        return false
      end,
    },
    {
      name = 'session3',
      container_id = nil,
      last_accessed = os.time() - 1800, -- 30 minutes ago
      is_valid = function()
        return true
      end,
    },
  }

  formatted = display.format_session_list(sessions)
  assert_equal(#formatted, 3, 'Should format all sessions')

  -- Check first session (valid)
  assert_not_nil(formatted[1].display, 'Display string should be present')
  assert_equal(formatted[1].session, sessions[1], 'Session object should be preserved')
  assert_contains(formatted[1].display, '●', 'Valid session should have filled circle')
  assert_contains(formatted[1].display, 'session1', 'Display should contain session name')
  assert_contains(formatted[1].display, 'container123', 'Display should contain truncated container ID')

  -- Check second session (invalid)
  assert_contains(formatted[2].display, '○', 'Invalid session should have empty circle')
  assert_contains(formatted[2].display, 'session2', 'Display should contain session name')

  -- Check third session (no container)
  assert_contains(formatted[3].display, 'session3', 'Display should contain session name')
  assert_contains(formatted[3].display, 'unknown', 'Display should show unknown for missing container')

  print('✓ format_session_list tests passed')
end

-- Test edge cases and error conditions
local function test_edge_cases()
  print('=== Testing Edge Cases ===')

  reset_state()
  local display = require('container.terminal.display')

  -- Test create_terminal_buffer with session missing config
  local minimal_session = { name = 'minimal', container_id = 'test', config = {} }
  local buf_id, win_id, err = display.create_terminal_buffer(minimal_session, 'split', {})
  -- Should handle missing config gracefully

  -- Test _configure_terminal_buffer with minimal session
  display._configure_terminal_buffer(1, minimal_session)

  -- Test switch_to_session with session missing buffer_id
  local session_no_buffer = {
    is_valid = function()
      return false
    end,
  }
  local success, err = display.switch_to_session(session_no_buffer)
  assert_false(success, 'Should fail without buffer_id')

  -- Test build_terminal_command with empty container_id
  local cmd = display.build_terminal_command('', nil, nil)
  assert_not_nil(cmd, 'Command should be returned even with empty container_id')

  -- Test build_terminal_command with nil shell (should use default)
  cmd = display.build_terminal_command('container123', nil, nil)
  assert_equal(cmd[#cmd], '/bin/sh', 'Should use default shell when nil provided')

  print('✓ Edge cases tests passed')
end

-- Test error conditions to reach uncovered lines
local function test_error_conditions()
  print('=== Testing Error Conditions ===')

  reset_state()
  local display = require('container.terminal.display')

  -- Mock nvim_create_buf to return nil to test "Failed to create terminal buffer" path
  local original_create_buf = _G.vim.api.nvim_create_buf
  _G.vim.api.nvim_create_buf = function(listed, scratch)
    return nil -- Simulate buffer creation failure
  end

  local session = create_mock_session('test_error')
  local buf_id, win_id, err = display.create_terminal_buffer(session, 'split', {})

  assert_nil(buf_id, 'Buffer ID should be nil on creation failure')
  assert_nil(win_id, 'Window ID should be nil on creation failure')
  assert_not_nil(err, 'Error should be returned on buffer creation failure')
  assert_contains(err, 'Failed to create terminal buffer', 'Error should mention buffer creation failure')

  -- Restore original function
  _G.vim.api.nvim_create_buf = original_create_buf

  print('✓ Error conditions tests passed')
end

-- Test auto-insert functionality with terminal buftype
local function test_auto_insert_terminal()
  print('=== Testing Auto Insert with Terminal ===')

  reset_state()
  local display = require('container.terminal.display')

  -- Mock vim.bo.buftype to be 'terminal'
  _G.vim.bo.buftype = 'terminal'

  local session = create_mock_session('test_auto_insert_terminal')
  session.config.auto_insert = true

  display._configure_terminal_buffer(1, session)

  -- Execute the BufEnter autocmd that should trigger startinsert for terminal buftype
  for _, autocmd in ipairs(_G.autocmds or {}) do
    if autocmd.event == 'BufEnter' and autocmd.opts.callback then
      autocmd.opts.callback()
    end
  end

  -- Check that startinsert command was executed
  local startinsert_executed = false
  for _, cmd in ipairs(_G.executed_commands or {}) do
    if cmd == 'startinsert' then
      startinsert_executed = true
      break
    end
  end
  assert_true(startinsert_executed, 'startinsert should be executed for terminal buffer')

  -- Reset buftype
  _G.vim.bo.buftype = ''

  print('✓ Auto insert terminal tests passed')
end

-- Test more comprehensive scenarios
local function test_comprehensive_scenarios()
  print('=== Testing Comprehensive Scenarios ===')

  reset_state()
  local display = require('container.terminal.display')

  -- Test with completely empty session config
  local empty_config_session = {
    name = 'empty_config',
    container_id = 'container123',
    config = {}, -- Completely empty config
  }

  local buf_id, win_id, err = display.create_terminal_buffer(empty_config_session, nil, {})
  assert_not_nil(buf_id, 'Should create buffer even with empty config')
  assert_not_nil(win_id, 'Should create window even with empty config')
  assert_nil(err, 'No error should occur with empty config')

  -- Test format_session_list with edge case sessions
  local edge_sessions = {
    {
      name = '',
      container_id = '',
      last_accessed = 0,
      is_valid = function()
        return true
      end,
    },
    {
      name = 'very_long_session_name_that_might_cause_display_issues',
      container_id = 'very_long_container_id_that_might_be_truncated_in_display',
      last_accessed = os.time(),
      is_valid = function()
        return false
      end,
    },
  }

  local formatted = display.format_session_list(edge_sessions)
  assert_equal(#formatted, 2, 'Should format edge case sessions')
  assert_not_nil(formatted[1].display, 'Should format empty name session')
  assert_not_nil(formatted[2].display, 'Should format long name session')

  print('✓ Comprehensive scenarios tests passed')
end

-- Test session configuration override scenarios
local function test_config_override_scenarios()
  print('=== Testing Config Override Scenarios ===')

  reset_state()
  local display = require('container.terminal.display')

  -- Test with session that has no default_position but config split_command
  local session = create_mock_session('test_override')
  session.config.default_position = nil
  session.config.split_command = 'rightbelow 20'

  local buf_id, win_id, err = display.create_terminal_buffer(session, nil, {})
  assert_not_nil(buf_id, 'Should create buffer with nil default_position')
  assert_not_nil(win_id, 'Should create window with nil default_position')
  assert_nil(err, 'No error should occur with nil default_position')

  -- Test with session that has config with no float section
  reset_state()
  session.config.float = nil
  buf_id, win_id, err = display.create_terminal_buffer(session, 'float', {})
  assert_not_nil(buf_id, 'Should create buffer with no float config')
  assert_not_nil(win_id, 'Should create window with no float config')

  print('✓ Config override scenarios tests passed')
end

-- Test additional split terminal scenarios
local function test_split_terminal_edge_cases()
  print('=== Testing Split Terminal Edge Cases ===')

  reset_state()
  local display = require('container.terminal.display')

  -- Test with session config that has split_command ending with 'new'
  local session = create_mock_session('test_split_edge')
  session.config.split_command = 'vertical new'

  local buf_id, win_id = display._create_split_terminal(session, {})
  assert_not_nil(buf_id, 'Should create buffer with split command ending in new')
  assert_not_nil(win_id, 'Should create window with split command ending in new')

  -- Verify command was executed properly
  local vertical_new_executed = false
  for _, cmd in ipairs(_G.executed_commands or {}) do
    if cmd == 'vertical new' then
      vertical_new_executed = true
      break
    end
  end
  assert_true(vertical_new_executed, 'vertical new should be executed')

  -- Test with nil split_command
  reset_state()
  session.config.split_command = nil
  buf_id, win_id = display._create_split_terminal(session, {})
  assert_not_nil(buf_id, 'Should create buffer with nil split_command')
  assert_not_nil(win_id, 'Should create window with nil split_command')

  print('✓ Split terminal edge cases tests passed')
end

-- Test switch_to_session with different split commands
local function test_switch_session_split_commands()
  print('=== Testing Switch Session Split Commands ===')

  reset_state()
  local display = require('container.terminal.display')

  -- Test with custom split command
  local session = create_mock_session('test_switch_split')
  session.buffer_id = 5
  session.config.split_command = 'rightbelow 25'
  session.is_valid = function()
    return true
  end

  -- No existing window for this buffer
  _G.win_buf_map = {}

  local success, err = display.switch_to_session(session)
  assert_true(success, 'Should succeed with custom split command')
  assert_nil(err, 'Error should be nil with custom split command')

  -- Check that custom split command was used
  local custom_split_executed = false
  for _, cmd in ipairs(_G.executed_commands or {}) do
    if cmd == 'rightbelow 25 new' then
      custom_split_executed = true
      break
    end
  end
  assert_true(custom_split_executed, 'Custom split command should be executed')

  -- Test with split command that already includes 'new'
  reset_state()
  session.config.split_command = 'leftabove 30 new'
  _G.win_buf_map = {}

  success, err = display.switch_to_session(session)
  assert_true(success, 'Should succeed with split command including new')

  print('✓ Switch session split commands tests passed')
end

-- Test terminal keymaps edge cases and all keymap types
local function test_terminal_keymaps_comprehensive()
  print('=== Testing Terminal Keymaps Comprehensive ===')

  reset_state()
  local display = require('container.terminal.display')

  -- Test with session that has only some keymaps defined
  local session = create_mock_session('test_keymaps_partial')
  session.config.keymaps = {
    close = '<C-q>',
    -- other keymaps intentionally missing
  }

  display._setup_terminal_keymaps(1, session)

  -- Should handle partial keymaps
  assert_not_nil(_G.keymaps, 'Keymaps should be set with partial config')

  -- Test with session that has all keymaps as nil
  reset_state()
  session.config.keymaps = {
    close = nil,
    escape = nil,
    new_session = nil,
    list_sessions = nil,
    next_session = nil,
    prev_session = nil,
  }

  display._setup_terminal_keymaps(1, session)

  -- Should handle all nil keymaps

  -- Test session keymap setup helper function edge cases
  reset_state()
  session.config.keymaps = {
    new_session = '<Leader>n',
    list_sessions = '<Leader>l',
    next_session = '<Tab>',
    prev_session = '<S-Tab>',
  }

  display._setup_terminal_keymaps(1, session)

  -- Verify that normal mode keymaps were set
  local normal_keymaps = 0
  for _, keymap in ipairs(_G.keymaps[1] or {}) do
    if keymap.mode == 'n' then
      normal_keymaps = normal_keymaps + 1
    end
  end
  assert_true(normal_keymaps > 0, 'Normal mode keymaps should be set')

  print('✓ Terminal keymaps comprehensive tests passed')
end

-- Test build_terminal_command with various environment configurations
local function test_build_terminal_command_comprehensive()
  print('=== Testing Build Terminal Command Comprehensive ===')

  local display = require('container.terminal.display')

  -- Test with single environment variable
  local env = { 'SINGLE=value' }
  local cmd = display.build_terminal_command('container123', '/bin/bash', env)

  local env_count = 0
  for i, arg in ipairs(cmd) do
    if arg == '-e' then
      env_count = env_count + 1
    end
  end
  assert_equal(env_count, 1, 'Should have one environment variable')

  -- Test with many environment variables
  env = { 'VAR1=value1', 'VAR2=value2', 'VAR3=value3', 'PATH=/custom/path' }
  cmd = display.build_terminal_command('test_container', '/bin/zsh', env)

  env_count = 0
  for i, arg in ipairs(cmd) do
    if arg == '-e' then
      env_count = env_count + 1
    end
  end
  assert_equal(env_count, 4, 'Should have four environment variables')

  -- Verify all variables are present
  local has_var1, has_var2, has_var3, has_path = false, false, false, false
  for i, arg in ipairs(cmd) do
    if arg == '-e' and i + 1 <= #cmd then
      local env_var = cmd[i + 1]
      if env_var == 'VAR1=value1' then
        has_var1 = true
      elseif env_var == 'VAR2=value2' then
        has_var2 = true
      elseif env_var == 'VAR3=value3' then
        has_var3 = true
      elseif env_var == 'PATH=/custom/path' then
        has_path = true
      end
    end
  end
  assert_true(has_var1, 'VAR1 should be present')
  assert_true(has_var2, 'VAR2 should be present')
  assert_true(has_var3, 'VAR3 should be present')
  assert_true(has_path, 'PATH should be present')

  -- Test with special characters in environment variables
  env = { 'SPECIAL_VAR=value with spaces and symbols!@#$%' }
  cmd = display.build_terminal_command('container456', '/bin/fish', env)

  local has_special = false
  for i, arg in ipairs(cmd) do
    if arg == '-e' and cmd[i + 1] == 'SPECIAL_VAR=value with spaces and symbols!@#$%' then
      has_special = true
      break
    end
  end
  assert_true(has_special, 'Special characters in environment should be preserved')

  print('✓ Build terminal command comprehensive tests passed')
end

-- Test format_session_list edge cases
local function test_format_session_list_edge_cases()
  print('=== Testing Format Session List Edge Cases ===')

  local display = require('container.terminal.display')

  -- Test with session that has very old timestamp
  local old_sessions = {
    {
      name = 'old_session',
      container_id = 'container123456789012',
      last_accessed = 946684800, -- Year 2000
      is_valid = function()
        return true
      end,
    },
  }

  local formatted = display.format_session_list(old_sessions)
  assert_equal(#formatted, 1, 'Should format old session')
  assert_contains(formatted[1].display, 'old_session', 'Should contain session name')

  -- Test with session that has exactly 12 character container ID
  local exact_sessions = {
    {
      name = 'exact_12',
      container_id = '123456789012', -- Exactly 12 chars
      last_accessed = os.time(),
      is_valid = function()
        return true
      end,
    },
  }

  formatted = display.format_session_list(exact_sessions)
  assert_contains(formatted[1].display, '123456789012', 'Should show full 12-char container ID')

  -- Test with session that has shorter than 12 character container ID
  local short_sessions = {
    {
      name = 'short_container',
      container_id = 'abc123', -- Less than 12 chars
      last_accessed = os.time(),
      is_valid = function()
        return true
      end,
    },
  }

  formatted = display.format_session_list(short_sessions)
  assert_contains(formatted[1].display, 'abc123', 'Should show full short container ID')

  print('✓ Format session list edge cases tests passed')
end

-- Test float terminal with various size configurations
local function test_float_terminal_size_configurations()
  print('=== Testing Float Terminal Size Configurations ===')

  reset_state()
  local display = require('container.terminal.display')

  -- Test with width exactly 1 (should be treated as fractional)
  local session = create_mock_session('test_float_size')
  session.config.float = { width = 1, height = 1 }

  local buf_id, win_id = display._create_float_terminal(session, {})
  assert_not_nil(buf_id, 'Should create buffer with width=1')
  assert_not_nil(win_id, 'Should create window with width=1')

  -- Test with width > 1 (should be treated as absolute)
  reset_state()
  session.config.float = { width = 100, height = 50 }
  buf_id, win_id = display._create_float_terminal(session, {})
  assert_not_nil(buf_id, 'Should create buffer with absolute size')

  -- Test with mixed fractional and absolute
  reset_state()
  session.config.float = { width = 0.9, height = 35 }
  buf_id, win_id = display._create_float_terminal(session, {})
  assert_not_nil(buf_id, 'Should create buffer with mixed size types')

  print('✓ Float terminal size configurations tests passed')
end

-- Test autocmd callback edge cases
local function test_autocmd_callback_edge_cases()
  print('=== Testing Autocmd Callback Edge Cases ===')

  reset_state()
  local display = require('container.terminal.display')

  -- Test with session that has buffer_id initially set
  local session = create_mock_session('test_autocmd_edge')
  session.buffer_id = 42

  display._configure_terminal_buffer(1, session)

  -- Execute BufDelete callback to clear buffer_id
  for _, autocmd in ipairs(_G.autocmds or {}) do
    if autocmd.event == 'BufDelete' and autocmd.opts.callback then
      autocmd.opts.callback()
      break
    end
  end

  assert_nil(session.buffer_id, 'Buffer ID should be cleared by BufDelete callback')

  -- Test multiple BufEnter executions
  reset_state()
  session = create_mock_session('test_multi_bufenter')
  display._configure_terminal_buffer(1, session)

  local enter_count = 0
  for _, autocmd in ipairs(_G.autocmds or {}) do
    if autocmd.event == 'BufEnter' and autocmd.opts.callback then
      autocmd.opts.callback()
      enter_count = enter_count + 1
      autocmd.opts.callback() -- Execute again
      enter_count = enter_count + 1
    end
  end

  assert_true(enter_count >= 2, 'BufEnter should be executable multiple times')

  print('✓ Autocmd callback edge cases tests passed')
end

-- Test all paths in create_terminal_buffer including defaults
local function test_create_terminal_buffer_all_paths()
  print('=== Testing Create Terminal Buffer All Paths ===')

  reset_state()
  local display = require('container.terminal.display')

  -- Test with session config that has no default_position and no position passed
  local session = create_mock_session('test_defaults')
  session.config.default_position = nil -- This should fallback to 'split'

  local buf_id, win_id, err = display.create_terminal_buffer(session, nil, nil)
  assert_not_nil(buf_id, 'Should create buffer with fallback to split')
  assert_not_nil(win_id, 'Should create window with fallback to split')
  assert_nil(err, 'Should not error with fallback to split')

  -- Test with completely missing opts parameter
  reset_state()
  buf_id, win_id, err = display.create_terminal_buffer(session)
  assert_not_nil(buf_id, 'Should create buffer with missing opts')

  -- Test with all possible position values again to ensure coverage
  for _, position in ipairs({ 'split', 'tab', 'float' }) do
    reset_state()
    buf_id, win_id, err = display.create_terminal_buffer(session, position, {})
    assert_not_nil(buf_id, 'Should create buffer for position: ' .. position)
    assert_not_nil(win_id, 'Should create window for position: ' .. position)
    assert_nil(err, 'Should not error for position: ' .. position)
  end

  print('✓ Create terminal buffer all paths tests passed')
end

-- Test more edge cases for split terminal creation
local function test_split_terminal_comprehensive()
  print('=== Testing Split Terminal Comprehensive ===')

  reset_state()
  local display = require('container.terminal.display')

  -- Test with empty split_command
  local session = create_mock_session('test_split_comprehensive')
  session.config.split_command = ''

  local buf_id, win_id = display._create_split_terminal(session, {})
  assert_not_nil(buf_id, 'Should create buffer with empty split command')
  assert_not_nil(win_id, 'Should create window with empty split command')

  -- Test with split_command that contains multiple spaces
  reset_state()
  session.config.split_command = 'belowright   15  '
  buf_id, win_id = display._create_split_terminal(session, {})
  assert_not_nil(buf_id, 'Should handle split command with extra spaces')

  print('✓ Split terminal comprehensive tests passed')
end

-- Test additional scenarios for configuration and buffer setup
local function test_buffer_configuration_comprehensive()
  print('=== Testing Buffer Configuration Comprehensive ===')

  reset_state()
  local display = require('container.terminal.display')

  -- Test with session that has empty config (not nil to avoid errors)
  local session = {
    name = 'no_config_session',
    container_id = 'container123',
    config = {}, -- Empty config instead of nil to avoid index errors
  }

  display._configure_terminal_buffer(1, session)

  -- Should handle empty config gracefully
  assert_not_nil(_G.buffer_names[1], 'Buffer name should be set even with empty config')

  -- Test with session config that has auto_insert = false explicitly
  reset_state()
  session = create_mock_session('test_explicit_false')
  session.config.auto_insert = false

  display._configure_terminal_buffer(1, session)

  -- Should work without auto_insert autocmd
  assert_not_nil(_G.autocmds, 'Basic autocmds should still be created')

  print('✓ Buffer configuration comprehensive tests passed')
end

-- Test specific scenarios for switch_to_session function
local function test_switch_session_comprehensive()
  print('=== Testing Switch Session Comprehensive ===')

  reset_state()
  local display = require('container.terminal.display')

  -- Test with session that has auto_insert false but still valid
  local session = create_mock_session('test_no_auto_insert')
  session.buffer_id = 10
  session.config.auto_insert = false
  session.is_valid = function()
    return true
  end

  -- No existing window
  _G.win_buf_map = {}

  local success, err = display.switch_to_session(session)
  assert_true(success, 'Should succeed without auto_insert')
  assert_nil(err, 'Should not error without auto_insert')

  -- Check that startinsert was NOT executed
  local startinsert_executed = false
  for _, cmd in ipairs(_G.executed_commands or {}) do
    if cmd == 'startinsert' then
      startinsert_executed = true
      break
    end
  end
  assert_false(startinsert_executed, 'startinsert should not be executed when auto_insert is false')

  -- Test with session that has nil split_command for switch
  reset_state()
  session.config.split_command = nil
  session.buffer_id = 11
  _G.win_buf_map = {}

  success, err = display.switch_to_session(session)
  assert_true(success, 'Should succeed with nil split_command')

  print('✓ Switch session comprehensive tests passed')
end

-- Test all scenarios in format_session_list
local function test_format_session_list_comprehensive()
  print('=== Testing Format Session List Comprehensive ===')

  local display = require('container.terminal.display')

  -- Test with session that has nil container_id
  local sessions = {
    {
      name = 'nil_container',
      container_id = nil, -- Explicitly nil
      last_accessed = os.time(),
      is_valid = function()
        return true
      end,
    },
  }

  local formatted = display.format_session_list(sessions)
  assert_equal(#formatted, 1, 'Should format session with nil container_id')
  assert_contains(formatted[1].display, 'unknown', 'Should show unknown for nil container_id')

  -- Test with session that has false container_id
  sessions = {
    {
      name = 'false_container',
      container_id = false, -- Falsy but not nil
      last_accessed = os.time(),
      is_valid = function()
        return true
      end,
    },
  }

  formatted = display.format_session_list(sessions)
  assert_contains(formatted[1].display, 'unknown', 'Should show unknown for falsy container_id')

  -- Test with mixed valid/invalid sessions
  sessions = {
    {
      name = 'valid1',
      container_id = 'container123',
      last_accessed = os.time() - 100,
      is_valid = function()
        return true
      end,
    },
    {
      name = 'invalid1',
      container_id = 'container456',
      last_accessed = os.time() - 200,
      is_valid = function()
        return false
      end,
    },
    {
      name = 'valid2',
      container_id = 'container789',
      last_accessed = os.time() - 300,
      is_valid = function()
        return true
      end,
    },
  }

  formatted = display.format_session_list(sessions)
  assert_equal(#formatted, 3, 'Should format all mixed sessions')

  -- Check that valid sessions have filled circle and invalid have empty circle
  assert_contains(formatted[1].display, '●', 'First session should be valid (filled circle)')
  assert_contains(formatted[2].display, '○', 'Second session should be invalid (empty circle)')
  assert_contains(formatted[3].display, '●', 'Third session should be valid (filled circle)')

  print('✓ Format session list comprehensive tests passed')
end

-- Test environment variable edge cases in build_terminal_command
local function test_build_terminal_command_environment_edge_cases()
  print('=== Testing Build Terminal Command Environment Edge Cases ===')

  local display = require('container.terminal.display')

  -- Test with environment containing empty string
  local env = { '', 'VALID=value' }
  local cmd = display.build_terminal_command('container123', '/bin/bash', env)

  -- Should still include empty environment variable
  local has_empty = false
  local has_valid = false
  for i, arg in ipairs(cmd) do
    if arg == '-e' and i + 1 <= #cmd then
      if cmd[i + 1] == '' then
        has_empty = true
      elseif cmd[i + 1] == 'VALID=value' then
        has_valid = true
      end
    end
  end
  assert_true(has_empty, 'Empty environment variable should be included')
  assert_true(has_valid, 'Valid environment variable should be included')

  -- Test with multiple environment variables without nil (nil would cause ipairs to stop)
  env = { 'VAR1=value1', 'VAR2=value2' }
  cmd = display.build_terminal_command('container456', '/bin/zsh', env)

  -- Should include all variables
  local var1_found = false
  local var2_found = false
  for i, arg in ipairs(cmd) do
    if arg == '-e' and i + 1 <= #cmd then
      if cmd[i + 1] == 'VAR1=value1' then
        var1_found = true
      elseif cmd[i + 1] == 'VAR2=value2' then
        var2_found = true
      end
    end
  end
  assert_true(var1_found, 'VAR1 should be found')
  assert_true(var2_found, 'VAR2 should be found')

  print('✓ Build terminal command environment edge cases tests passed')
end

-- Test float window configuration variations
local function test_float_variations()
  print('=== Testing Float Configuration Variations ===')

  reset_state()
  local display = require('container.terminal.display')

  -- Test with minimal float config
  local session = create_mock_session('test_float_minimal')
  session.config.float = {}

  local buf_id, win_id = display._create_float_terminal(session, {})
  assert_not_nil(buf_id, 'Buffer should be created with minimal config')
  assert_not_nil(win_id, 'Window should be created with minimal config')

  -- Test with custom border
  reset_state()
  session.config.float.border = 'single'
  buf_id, win_id = display._create_float_terminal(session, {})
  assert_not_nil(buf_id, 'Buffer should be created with custom border')

  -- Test with custom title
  reset_state()
  session.config.float.title = 'Custom Title'
  session.config.float.title_pos = 'left'
  buf_id, win_id = display._create_float_terminal(session, {})
  assert_not_nil(buf_id, 'Buffer should be created with custom title')

  -- Test with no title
  reset_state()
  session.config.float.title = nil
  buf_id, win_id = display._create_float_terminal(session, {})
  assert_not_nil(buf_id, 'Buffer should be created without title')

  print('✓ Float configuration variations tests passed')
end

-- Test autocmd callback execution
local function test_autocmd_callbacks()
  print('=== Testing Autocmd Callbacks ===')

  reset_state()
  local display = require('container.terminal.display')

  local session = create_mock_session('test_autocmd')
  display._configure_terminal_buffer(1, session)

  -- Find and execute BufEnter callback
  local buf_enter_executed = false
  local buf_delete_executed = false

  for _, autocmd in ipairs(_G.autocmds or {}) do
    if autocmd.event == 'BufEnter' then
      if autocmd.opts.callback then
        autocmd.opts.callback()
        buf_enter_executed = true
      end
    elseif autocmd.event == 'BufDelete' then
      if autocmd.opts.callback then
        autocmd.opts.callback()
        buf_delete_executed = true
      end
    end
  end

  assert_true(buf_enter_executed, 'BufEnter callback should be executed')
  assert_true(buf_delete_executed, 'BufDelete callback should be executed')
  assert_equal(_G.active_session, session, 'Active session should be set')
  assert_nil(session.buffer_id, 'Buffer ID should be cleared on delete')

  print('✓ Autocmd callbacks tests passed')
end

-- Test terminal keymaps with different configurations
local function test_keymap_configurations()
  print('=== Testing Keymap Configurations ===')

  reset_state()
  local display = require('container.terminal.display')

  -- Test with partial keymaps
  local session = create_mock_session('test_partial_keymaps')
  session.config.keymaps = {
    close = '<C-q>',
    -- escape intentionally missing
    new_session = '<C-t>',
  }

  display._setup_terminal_keymaps(1, session)

  -- Should handle partial keymaps without error
  assert_not_nil(_G.keymaps, 'Keymaps should be set')

  -- Test with all keymaps set
  reset_state()
  session.config.keymaps = {
    close = '<C-d>',
    escape = '<C-\\><C-n>',
    new_session = '<C-n>',
    list_sessions = '<C-l>',
    next_session = '<C-j>',
    prev_session = '<C-k>',
  }

  display._setup_terminal_keymaps(1, session)

  assert_not_nil(_G.keymaps[1], 'All keymaps should be set')
  assert_true(#_G.keymaps[1] > 0, 'Multiple keymaps should be set')

  print('✓ Keymap configurations tests passed')
end

-- Test additional internal helper functions and edge cases
local function test_internal_function_coverage()
  print('=== Testing Internal Function Coverage ===')

  reset_state()
  local display = require('container.terminal.display')

  -- Test setup_session_keymap helper by calling _setup_terminal_keymaps with all keymap types
  local session = create_mock_session('test_all_keymaps')
  session.config.keymaps = {
    close = '<C-d>',
    escape = '<C-\\><C-n>',
    new_session = '<Leader>n',
    list_sessions = '<Leader>l',
    next_session = '<Tab>',
    prev_session = '<S-Tab>',
  }

  display._setup_terminal_keymaps(1, session)

  -- Verify all keymap types were processed
  local terminal_keymaps = 0
  local normal_keymaps = 0
  for _, keymap in ipairs(_G.keymaps[1] or {}) do
    if keymap.mode == 't' then
      terminal_keymaps = terminal_keymaps + 1
    elseif keymap.mode == 'n' then
      normal_keymaps = normal_keymaps + 1
    end
  end
  assert_true(terminal_keymaps >= 2, 'Terminal mode keymaps should be set (close, escape)')
  assert_true(normal_keymaps >= 4, 'Normal mode keymaps should be set (session navigation)')

  -- Test edge cases in string format for title
  reset_state()
  session.config.float = {
    title = 'Test Title',
    title_pos = 'right',
  }
  session.name = 'session_with_title'

  local buf_id, win_id = display._create_float_terminal(session, {})
  assert_not_nil(buf_id, 'Should create buffer with title formatting')
  assert_not_nil(win_id, 'Should create window with title formatting')

  print('✓ Internal function coverage tests passed')
end

-- Test more comprehensive error scenarios and edge paths
local function test_advanced_error_scenarios()
  print('=== Testing Advanced Error Scenarios ===')

  reset_state()
  local display = require('container.terminal.display')

  -- Test switch_to_session with session that has invalid split_command format
  local session = create_mock_session('test_invalid_split')
  session.buffer_id = 20
  session.config.split_command = 'invalid command format'
  session.is_valid = function()
    return true
  end
  _G.win_buf_map = {} -- No existing window

  -- Should still work even with unusual split command
  local success, err = display.switch_to_session(session)
  assert_true(success, 'Should succeed even with unusual split command')
  assert_nil(err, 'Should not error with unusual split command')

  -- Test format_session_list with sessions having various edge case timestamps
  local edge_time_sessions = {
    {
      name = 'future_session',
      container_id = 'container123',
      last_accessed = os.time() + 3600, -- Future time
      is_valid = function()
        return true
      end,
    },
    {
      name = 'zero_time_session',
      container_id = 'container456',
      last_accessed = 0, -- Unix epoch
      is_valid = function()
        return false
      end,
    },
  }

  local formatted = display.format_session_list(edge_time_sessions)
  assert_equal(#formatted, 2, 'Should format sessions with edge case timestamps')
  assert_not_nil(formatted[1].display, 'Should format future timestamp session')
  assert_not_nil(formatted[2].display, 'Should format zero timestamp session')

  print('✓ Advanced error scenarios tests passed')
end

-- Test more configuration variations
local function test_configuration_variations()
  print('=== Testing Configuration Variations ===')

  reset_state()
  local display = require('container.terminal.display')

  -- Test _create_float_terminal with various config combinations
  local session = create_mock_session('test_config_variations')

  -- Test with only width specified in opts
  session.config.float = {}
  local buf_id, win_id = display._create_float_terminal(session, { width = 80 })
  assert_not_nil(buf_id, 'Should create with only width in opts')

  -- Test with only height specified in opts
  reset_state()
  buf_id, win_id = display._create_float_terminal(session, { height = 24 })
  assert_not_nil(buf_id, 'Should create with only height in opts')

  -- Test with both width and height in opts overriding config
  reset_state()
  session.config.float = { width = 0.5, height = 0.5 }
  buf_id, win_id = display._create_float_terminal(session, { width = 100, height = 30 })
  assert_not_nil(buf_id, 'Should create with opts overriding config')

  -- Test _create_split_terminal with various split command formats
  reset_state()
  session.config.split_command = 'topleft 10'
  buf_id, win_id = display._create_split_terminal(session, {})
  assert_not_nil(buf_id, 'Should create with topleft split command')

  print('✓ Configuration variations tests passed')
end

-- Main test runner
local function run_all_tests()
  print('Running Comprehensive Terminal Display Tests...\n')

  local tests = {
    test_create_terminal_buffer,
    test_create_split_terminal,
    test_create_tab_terminal,
    test_create_float_terminal,
    test_configure_terminal_buffer,
    test_setup_terminal_keymaps,
    test_switch_to_session,
    test_build_terminal_command,
    test_format_session_list,
    test_edge_cases,
    test_error_conditions,
    test_auto_insert_terminal,
    test_comprehensive_scenarios,
    test_config_override_scenarios,
    test_split_terminal_edge_cases,
    test_switch_session_split_commands,
    test_terminal_keymaps_comprehensive,
    test_build_terminal_command_comprehensive,
    test_format_session_list_edge_cases,
    test_float_terminal_size_configurations,
    test_autocmd_callback_edge_cases,
    test_create_terminal_buffer_all_paths,
    test_split_terminal_comprehensive,
    test_buffer_configuration_comprehensive,
    test_switch_session_comprehensive,
    test_format_session_list_comprehensive,
    test_build_terminal_command_environment_edge_cases,
    test_float_variations,
    test_autocmd_callbacks,
    test_keymap_configurations,
    test_internal_function_coverage,
    test_advanced_error_scenarios,
    test_configuration_variations,
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
    print('Expected to significantly improve terminal/display.lua coverage')
    return 0
  else
    print('Some tests failed! ✗')
    return 1
  end
end

-- Run the tests
local exit_code = run_all_tests()
os.exit(exit_code)
