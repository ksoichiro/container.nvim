#!/usr/bin/env lua

-- Test for Enhanced Terminal Integration

-- Mock vim globals for testing
_G.vim = {
  tbl_contains = function(t, value)
    for _, v in ipairs(t) do
      if v == value then
        return true
      end
    end
    return false
  end,
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
  split = function(str, sep)
    local result = {}
    for match in (str .. sep):gmatch('(.-)' .. sep) do
      table.insert(result, match)
    end
    return result
  end,
  fn = {
    getcwd = function()
      return '/test/workspace'
    end,
    sha256 = function(str)
      return 'abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234'
    end,
    stdpath = function(what)
      if what == 'data' then
        return '/test/data'
      end
      return '/test'
    end,
    filereadable = function(file)
      return 0
    end,
    readfile = function(file)
      return {}
    end,
    writefile = function(lines, file)
      return true
    end,
    isdirectory = function(dir)
      return 0
    end,
    globpath = function(path, pattern, nosuf, list)
      return list and {} or ''
    end,
    delete = function(file, flags)
      return 0
    end,
    jobwait = function(jobs, timeout)
      return { -1 } -- Job is still running
    end,
  },
  v = { shell_error = 0 },
  loop = {
    fs_stat = function(path)
      return {
        mtime = { sec = os.time() },
        size = 1024,
      }
    end,
  },
  api = {
    nvim_create_buf = function(listed, scratch)
      return 1
    end,
    nvim_buf_is_valid = function(buf_id)
      return true
    end,
    nvim_buf_set_option = function(buf_id, option, value) end,
    nvim_buf_set_name = function(buf_id, name) end,
    nvim_buf_set_lines = function(buf_id, start, end_line, strict_indexing, lines)
      return true
    end,
    nvim_buf_get_lines = function(buf_id, start, end_line, strict_indexing)
      return { 'line1', 'line2', 'line3' }
    end,
    nvim_create_augroup = function(name, opts)
      return 1
    end,
    nvim_create_autocmd = function(event, opts) end,
    nvim_buf_set_keymap = function(buf_id, mode, lhs, rhs, opts) end,
    nvim_list_wins = function()
      return { 1, 2 }
    end,
    nvim_win_get_buf = function(win_id)
      return 1
    end,
    nvim_get_current_win = function()
      return 1
    end,
    nvim_set_current_win = function(win_id) end,
    nvim_win_set_buf = function(win_id, buf_id) end,
    nvim_win_set_height = function(win_id, height) end,
    nvim_win_set_width = function(win_id, width) end,
    nvim_open_win = function(buf_id, enter, config)
      return 1
    end,
    nvim_win_get_cursor = function(win_id)
      return { 2, 0 }
    end,
    nvim_buf_delete = function(buf_id, opts) end,
  },
  cmd = function(command) end,
  schedule = function(callback)
    callback()
  end,
  defer_fn = function(callback, delay)
    callback()
  end,
  log = { levels = { INFO = 1, WARN = 2, ERROR = 3 } },
  notify = function(msg, level, opts)
    print('[NOTIFY]', msg)
  end,
  o = { lines = 50, columns = 120 },
  list_slice = function(list, start, finish)
    local result = {}
    for i = start, finish do
      if list[i] then
        table.insert(result, list[i])
      end
    end
    return result
  end,
  jobstart = function(cmd, opts)
    return 1
  end,
  termopen = function(cmd, opts)
    return 1
  end,
}

-- Mock file system utilities
package.loaded['devcontainer.utils.fs'] = {
  ensure_directory = function(dir)
    return true
  end,
}

-- Mock log utilities
package.loaded['devcontainer.utils.log'] = {
  debug = function(...)
    print('[DEBUG]', string.format(...))
  end,
  info = function(...)
    print('[INFO]', string.format(...))
  end,
  warn = function(...)
    print('[WARN]', string.format(...))
  end,
  error = function(...)
    print('[ERROR]', string.format(...))
  end,
}

-- Set up package path
package.path = './lua/?.lua;./lua/?/init.lua;' .. package.path

-- Test functions

local function test_session_manager()
  print('=== Testing Session Manager ===')

  local session_manager = require('devcontainer.terminal.session')

  -- Test setup
  local config = {
    persistent_history = true,
    history_dir = '/test/history',
    max_history_lines = 1000,
  }

  session_manager.setup(config)
  print('✓ Session manager setup completed')

  -- Test session creation
  local session, err = session_manager.create_session('test_session', 'container123', config)
  if session then
    print('✓ Session created successfully: ' .. session.name)
  else
    print('✗ Session creation failed: ' .. (err or 'unknown'))
    return false
  end

  -- Set up session for testing (simulate terminal creation)
  session.buffer_id = 1
  session.job_id = 1

  -- Test session retrieval
  local retrieved_session = session_manager.get_session('test_session')
  if retrieved_session and retrieved_session.name == 'test_session' then
    print('✓ Session retrieval successful')
  else
    print('✗ Session retrieval failed')
    return false
  end

  -- Test session listing
  local sessions = session_manager.list_sessions()
  if #sessions == 1 and sessions[1].name == 'test_session' then
    print('✓ Session listing successful')
  else
    print('✗ Session listing failed')
    return false
  end

  -- Test unique name generation
  local unique_name = session_manager.generate_unique_name('test_session')
  if unique_name == 'test_session_1' then
    print('✓ Unique name generation successful')
  else
    print('✗ Unique name generation failed: ' .. unique_name)
    return false
  end

  -- Test session stats
  local stats = session_manager.get_session_stats()
  if stats.total == 1 then
    print('✓ Session stats successful')
  else
    print('✗ Session stats failed')
    return false
  end

  return true
end

local function test_display_module()
  print('\n=== Testing Display Module ===')

  local display = require('devcontainer.terminal.display')

  -- Test terminal command building
  local cmd = display.build_terminal_command('container123', '/bin/bash', { 'TERM=xterm-256color' })
  local expected_cmd = { 'docker', 'exec', '-it', '-e', 'TERM=xterm-256color', 'container123', '/bin/bash' }

  local cmd_str = table.concat(cmd, ' ')
  local expected_str = table.concat(expected_cmd, ' ')

  if cmd_str == expected_str then
    print('✓ Terminal command building successful')
  else
    print('✗ Terminal command building failed')
    print('  Expected: ' .. expected_str)
    print('  Got: ' .. cmd_str)
    return false
  end

  -- Test session list formatting
  local mock_session = {
    name = 'test_session',
    container_id = 'container123456789',
    last_accessed = os.time(),
    is_valid = function()
      return true
    end,
  }

  local formatted = display.format_session_list({ mock_session })
  if #formatted == 1 and formatted[1].session == mock_session then
    print('✓ Session list formatting successful')
  else
    print('✗ Session list formatting failed')
    return false
  end

  return true
end

local function test_history_module()
  print('\n=== Testing History Module ===')

  local history = require('devcontainer.terminal.history')

  -- Mock session
  local mock_session = {
    name = 'test_session',
    config = {
      persistent_history = true,
      history_dir = '/test/history',
      max_history_lines = 1000,
    },
  }

  -- Test history file path generation
  local history_file = history.get_history_file_path(mock_session, '/test/workspace')
  if history_file and history_file:match('%.history$') then
    print('✓ History file path generation successful')
  else
    print('✗ History file path generation failed: ' .. tostring(history_file))
    return false
  end

  -- Test buffer content extraction
  local content = history.get_buffer_content(1)
  if content and #content == 3 then
    print('✓ Buffer content extraction successful')
  else
    print('✗ Buffer content extraction failed')
    return false
  end

  -- Test history stats
  local stats = history.get_history_stats(mock_session.config)
  if stats.enabled then
    print('✓ History stats successful')
  else
    print('✗ History stats failed')
    return false
  end

  return true
end

local function test_main_terminal_module()
  print('\n=== Testing Main Terminal Module ===')

  -- Mock config module
  package.loaded['devcontainer.config'] = {
    get = function()
      return {
        terminal = {
          default_shell = '/bin/bash',
          auto_insert = true,
          close_on_exit = false,
          persistent_history = true,
          history_dir = '/test/history',
          max_history_lines = 1000,
          default_position = 'split',
          environment = { 'TERM=xterm-256color' },
        },
      }
    end,
  }

  -- Mock devcontainer module
  package.loaded['devcontainer'] = {
    get_container_id = function()
      return 'container123'
    end,
  }

  local terminal = require('devcontainer.terminal')

  -- Test setup
  local config = {
    terminal = {
      default_shell = '/bin/bash',
      persistent_history = true,
      history_dir = '/test/history',
    },
  }

  terminal.setup(config)
  print('✓ Terminal module setup completed')

  -- Test status retrieval
  local status = terminal.get_status()
  if status and type(status.total_sessions) == 'number' then
    print('✓ Terminal status retrieval successful')
  else
    print('✗ Terminal status retrieval failed')
    print('  Status: ' .. tostring(status and status.total_sessions))
    return false
  end

  return true
end

-- Run tests
local function run_tests()
  print('Running Enhanced Terminal Integration tests...\n')

  local tests = {
    test_session_manager,
    test_display_module,
    test_history_module,
    test_main_terminal_module,
  }

  local passed = 0
  local total = #tests

  for _, test in ipairs(tests) do
    local success = test()
    if success then
      passed = passed + 1
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

local exit_code = run_tests()
os.exit(exit_code)
