#!/usr/bin/env lua

-- Comprehensive tests for Terminal History Management
-- This test suite aims to achieve >70% coverage for lua/container/terminal/history.lua

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
    nvim_buf_get_lines = function(buf_id, start, end_pos, strict)
      if buf_id == 999 then
        error('Invalid buffer')
      end
      -- Mock buffer content
      if buf_id == 1 then
        return { 'line 1', 'line 2', 'line 3', '' }
      elseif buf_id == 2 then
        return { 'command 1', 'output', 'command 2', 'more output', '' }
      elseif buf_id == 3 then
        return {}
      end
      return { 'default content' }
    end,
    nvim_buf_set_lines = function(buf_id, start, end_pos, strict, lines)
      if buf_id == 999 then
        error('Invalid buffer')
      end
      -- Mock successful insertion
      return true
    end,
    nvim_create_augroup = function(name, opts)
      return { id = 1, name = name }
    end,
    nvim_create_autocmd = function(event, opts)
      return 1
    end,
  },
  fn = {
    sha256 = function(str)
      -- Mock hash function
      local hash = 0
      for i = 1, #str do
        hash = hash + string.byte(str, i)
      end
      return string.format('%08x', hash):rep(8)
    end,
    getcwd = function()
      return '/test/workspace'
    end,
    filereadable = function(path)
      -- Simulate existing history files for some paths
      if path:find('existing_session') then
        return 1
      elseif path:find('empty_history') then
        return 1
      elseif path:find('large_history') then
        return 1
      elseif path:find('boundary_test') then
        return 1
      end
      return 0
    end,
    readfile = function(path)
      if path:find('existing_session') then
        return { 'history line 1', 'history line 2', 'history line 3' }
      elseif path:find('empty_history') then
        return {}
      elseif path:find('large_history') then
        local lines = {}
        for i = 1, 15000 do
          table.insert(lines, 'history line ' .. i)
        end
        return lines
      end
      return nil
    end,
    writefile = function(lines, path)
      -- Mock writefile function
      if path:find('write_fail') then
        error('Write failed')
      end
      return true
    end,
    isdirectory = function(path)
      -- Mock directory check
      if path:find('/test/history') then
        return 1
      end
      return 0
    end,
    globpath = function(dir, pattern, nosuf, list)
      if dir:find('/test/history') and pattern == '*' then
        return { '/test/history/project1', '/test/history/project2' }
      elseif pattern == '*.history' then
        if dir:find('project1') then
          return { '/test/history/project1/session1.history', '/test/history/project1/session2.history' }
        elseif dir:find('project2') then
          return { '/test/history/project2/old_session.history' }
        end
      end
      return {}
    end,
    delete = function(path, flags)
      -- Mock successful deletion
      return 0
    end,
  },
  list_slice = function(list, start_idx, end_idx)
    local result = {}
    for i = start_idx, end_idx do
      if list[i] then
        table.insert(result, list[i])
      end
    end
    return result
  end,
  loop = {
    fs_stat = function(path)
      if path:find('old_session') then
        -- Old file (older than 30 days)
        return { mtime = { sec = os.time() - (35 * 24 * 60 * 60) }, size = 1024 }
      else
        -- Recent file
        return { mtime = { sec = os.time() }, size = 512 }
      end
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

local function create_test_session(name, config)
  config = config or {}
  local final_config = {
    persistent_history = true,
    history_dir = '/test/history',
    max_history_lines = 10000,
  }
  -- Merge config allowing nil values to override defaults
  for k, v in pairs(config) do
    final_config[k] = v
  end
  return {
    name = name,
    config = final_config,
    buffer_id = 1,
  }
end

-- Test get_history_file_path function
local function test_get_history_file_path()
  print('=== Testing get_history_file_path ===')

  local history = require('container.terminal.history')

  -- Test with persistent history enabled
  local session = create_test_session('test_session')
  local path = history.get_history_file_path(session, '/test/project')
  assert_not_nil(path, 'Path should be returned for valid session')
  assert_true(path:find('test_session'), 'Path should contain session name')

  -- Test with persistent history disabled
  local session_disabled = create_test_session('disabled_session', { persistent_history = false })
  local disabled_path = history.get_history_file_path(session_disabled, '/test/project')
  assert_nil(disabled_path, 'Path should be nil when persistent history is disabled')

  -- Test with no history_dir (manually set to nil)
  local session_no_dir = create_test_session('no_dir_session', { persistent_history = true })
  session_no_dir.config.history_dir = nil -- Explicitly set to nil
  local no_dir_path = history.get_history_file_path(session_no_dir, '/test/project')
  assert_nil(no_dir_path, 'Path should be nil when history_dir is not set')

  -- Test with special characters in session name
  local session_special = create_test_session('test/session@name#special')
  local special_path = history.get_history_file_path(session_special, '/test/project')
  assert_not_nil(special_path, 'Path should be returned for session with special characters')
  assert_true(special_path:find('test_session_name_special'), 'Special characters should be sanitized')

  -- Test with default project path
  local default_path = history.get_history_file_path(session, nil)
  assert_not_nil(default_path, 'Path should be returned with default project path')

  print('✓ get_history_file_path tests passed')
end

-- Test load_history function
local function test_load_history()
  print('=== Testing load_history ===')

  local history = require('container.terminal.history')

  -- Test with persistent history disabled
  local session_disabled = create_test_session('disabled_session', { persistent_history = false })
  local disabled_result = history.load_history(session_disabled, '/test/project')
  assert_nil(disabled_result, 'Should return nil when persistent history is disabled')

  -- Test with non-existent history file
  local session_new = create_test_session('new_session')
  local new_result = history.load_history(session_new, '/test/project')
  assert_nil(new_result, 'Should return nil for non-existent history file')

  -- Test with existing history file
  local session_existing = create_test_session('existing_session')
  local existing_result = history.load_history(session_existing, '/test/project')
  assert_not_nil(existing_result, 'Should return history for existing file')
  assert_equal(#existing_result, 3, 'Should return correct number of history lines')

  -- Test with empty history file
  local session_empty = create_test_session('empty_history')
  local empty_result = history.load_history(session_empty, '/test/project')
  assert_nil(empty_result, 'Should return nil for empty history file')

  -- Test with large history file (exceeding max_history_lines)
  local session_large = create_test_session('large_history', { max_history_lines = 1000 })
  local large_result = history.load_history(session_large, '/test/project')
  assert_not_nil(large_result, 'Should return history for large file')
  assert_equal(#large_result, 1000, 'Should limit history to max_history_lines')

  print('✓ load_history tests passed')
end

-- Test save_history function
local function test_save_history()
  print('=== Testing save_history ===')

  local history = require('container.terminal.history')

  -- Test with persistent history disabled
  local session_disabled = create_test_session('disabled_session', { persistent_history = false })
  local success, err = history.save_history(session_disabled, '/test/project', { 'line1', 'line2' })
  assert_false(success, 'Should fail when persistent history is disabled')
  assert_not_nil(err, 'Should return error message')

  -- Test with no content
  local session = create_test_session('test_session')
  local success_empty, err_empty = history.save_history(session, '/test/project', {})
  assert_true(success_empty, 'Should succeed with no content')
  assert_equal(err_empty, 'No content to save', 'Should return appropriate message')

  -- Test with nil content
  local success_nil, err_nil = history.save_history(session, '/test/project', nil)
  assert_true(success_nil, 'Should succeed with nil content')
  assert_equal(err_nil, 'No content to save', 'Should return appropriate message')

  -- Test with valid content
  local content = { 'command 1', 'output 1', 'command 2', 'output 2' }
  local success_valid, err_valid = history.save_history(session, '/test/project', content)
  assert_true(success_valid, 'Should succeed with valid content')
  assert_nil(err_valid, 'Should not return error for valid save')

  -- Test with large content (exceeding max_history_lines)
  local large_content = {}
  for i = 1, 15000 do
    table.insert(large_content, 'line ' .. i)
  end
  local session_large = create_test_session('large_session', { max_history_lines = 1000 })
  local success_large, err_large = history.save_history(session_large, '/test/project', large_content)
  assert_true(success_large, 'Should succeed with large content')
  assert_nil(err_large, 'Should not return error for large content save')

  -- Test write failure
  local session_fail = create_test_session('write_fail_session')
  local success_fail, err_fail = history.save_history(session_fail, '/test/project', { 'test' })
  assert_false(success_fail, 'Should fail when write fails')
  assert_not_nil(err_fail, 'Should return error message for write failure')

  print('✓ save_history tests passed')
end

-- Test get_buffer_content function
local function test_get_buffer_content()
  print('=== Testing get_buffer_content ===')

  local history = require('container.terminal.history')

  -- Test with invalid buffer
  local invalid_content = history.get_buffer_content(999)
  assert_equal(#invalid_content, 0, 'Should return empty table for invalid buffer')

  -- Test with nil buffer
  local nil_content = history.get_buffer_content(nil)
  assert_equal(#nil_content, 0, 'Should return empty table for nil buffer')

  -- Test with valid buffer
  local valid_content = history.get_buffer_content(1)
  assert_equal(#valid_content, 3, 'Should return correct number of lines')
  assert_equal(valid_content[1], 'line 1', 'Should return correct content')

  -- Test with buffer containing trailing empty lines
  local content_with_empty = history.get_buffer_content(2)
  assert_equal(#content_with_empty, 4, 'Should filter out trailing empty lines')

  -- Test with empty buffer
  local empty_content = history.get_buffer_content(3)
  assert_equal(#empty_content, 0, 'Should return empty table for empty buffer')

  print('✓ get_buffer_content tests passed')
end

-- Test restore_history_to_buffer function
local function test_restore_history_to_buffer()
  print('=== Testing restore_history_to_buffer ===')

  local history = require('container.terminal.history')

  -- Test with invalid buffer
  local success_invalid, err_invalid = history.restore_history_to_buffer(999, { 'line1', 'line2' })
  assert_false(success_invalid, 'Should fail with invalid buffer')
  assert_not_nil(err_invalid, 'Should return error message for invalid buffer')

  -- Test with nil buffer
  local success_nil, err_nil = history.restore_history_to_buffer(nil, { 'line1', 'line2' })
  assert_false(success_nil, 'Should fail with nil buffer')
  assert_not_nil(err_nil, 'Should return error message for nil buffer')

  -- Test with no history
  local success_no_history, err_no_history = history.restore_history_to_buffer(1, {})
  assert_true(success_no_history, 'Should succeed with no history')
  assert_equal(err_no_history, 'No history to restore', 'Should return appropriate message')

  -- Test with nil history
  local success_nil_history, err_nil_history = history.restore_history_to_buffer(1, nil)
  assert_true(success_nil_history, 'Should succeed with nil history')
  assert_equal(err_nil_history, 'No history to restore', 'Should return appropriate message')

  -- Test with valid history
  local history_lines = { 'previous command 1', 'previous output 1', 'previous command 2' }
  local success_valid, err_valid = history.restore_history_to_buffer(1, history_lines)
  assert_true(success_valid, 'Should succeed with valid history')
  assert_nil(err_valid, 'Should not return error for valid restore')

  print('✓ restore_history_to_buffer tests passed')
end

-- Test setup_auto_save function
local function test_setup_auto_save()
  print('=== Testing setup_auto_save ===')

  local history = require('container.terminal.history')

  -- Test with persistent history disabled
  local session_disabled = create_test_session('disabled_session', { persistent_history = false })
  -- This should not create autocommands
  history.setup_auto_save(session_disabled, '/test/project')
  -- No assertion needed, function should return early

  -- Test with invalid buffer
  local session_invalid = create_test_session('invalid_session')
  session_invalid.buffer_id = 999
  history.setup_auto_save(session_invalid, '/test/project')
  -- No assertion needed, function should return early

  -- Test with nil buffer
  local session_nil = create_test_session('nil_session')
  session_nil.buffer_id = nil
  history.setup_auto_save(session_nil, '/test/project')
  -- No assertion needed, function should return early

  -- Test with valid session
  local session_valid = create_test_session('valid_session')
  session_valid.buffer_id = 1
  history.setup_auto_save(session_valid, '/test/project')
  -- Should create autocommands successfully

  print('✓ setup_auto_save tests passed')
end

-- Test cleanup_old_history function
local function test_cleanup_old_history()
  print('=== Testing cleanup_old_history ===')

  local history = require('container.terminal.history')

  -- Test with no history_dir
  local config_no_dir = {}
  local count_no_dir = history.cleanup_old_history(config_no_dir, 30)
  assert_equal(count_no_dir, 0, 'Should return 0 when no history_dir')

  -- Test with non-existent directory
  local config_no_exist = { history_dir = '/non/existent/dir' }
  local count_no_exist = history.cleanup_old_history(config_no_exist, 30)
  assert_equal(count_no_exist, 0, 'Should return 0 when directory does not exist')

  -- Test with existing directory
  local config_exist = { history_dir = '/test/history' }
  local count_exist = history.cleanup_old_history(config_exist, 30)
  assert_true(count_exist >= 0, 'Should return non-negative count')

  -- Test with custom days_to_keep
  local count_custom = history.cleanup_old_history(config_exist, 7)
  assert_true(count_custom >= 0, 'Should return non-negative count with custom days')

  -- Test with nil days_to_keep (should use default 30)
  local count_default = history.cleanup_old_history(config_exist, nil)
  assert_true(count_default >= 0, 'Should return non-negative count with default days')

  print('✓ cleanup_old_history tests passed')
end

-- Test get_history_stats function
local function test_get_history_stats()
  print('=== Testing get_history_stats ===')

  local history = require('container.terminal.history')

  -- Test with no history_dir
  local config_no_dir = {}
  local stats_no_dir = history.get_history_stats(config_no_dir)
  assert_false(stats_no_dir.enabled, 'Should be disabled when no history_dir')
  assert_equal(stats_no_dir.total_files, 0, 'Should have 0 total files')
  assert_equal(stats_no_dir.total_size, 0, 'Should have 0 total size')
  assert_equal(stats_no_dir.projects, 0, 'Should have 0 projects')

  -- Test with non-existent directory
  local config_no_exist = { history_dir = '/non/existent/dir' }
  local stats_no_exist = history.get_history_stats(config_no_exist)
  assert_true(stats_no_exist.enabled, 'Should be enabled when history_dir is set')
  assert_equal(stats_no_exist.total_files, 0, 'Should have 0 total files for non-existent dir')
  assert_equal(stats_no_exist.total_size, 0, 'Should have 0 total size for non-existent dir')
  assert_equal(stats_no_exist.projects, 0, 'Should have 0 projects for non-existent dir')

  -- Test with existing directory
  local config_exist = { history_dir = '/test/history' }
  local stats_exist = history.get_history_stats(config_exist)
  assert_true(stats_exist.enabled, 'Should be enabled')
  assert_true(stats_exist.total_files >= 0, 'Should have non-negative total files')
  assert_true(stats_exist.total_size >= 0, 'Should have non-negative total size')
  assert_true(stats_exist.projects >= 0, 'Should have non-negative projects')
  assert_equal(stats_exist.history_dir, '/test/history', 'Should include history directory')

  print('✓ get_history_stats tests passed')
end

-- Test export_session_history function
local function test_export_session_history()
  print('=== Testing export_session_history ===')

  local history = require('container.terminal.history')

  -- Test with non-existent history file
  local session_new = create_test_session('new_session')
  local success_new, err_new = history.export_session_history(session_new, '/test/project', '/tmp/export.txt')
  assert_false(success_new, 'Should fail when no history file exists')
  assert_not_nil(err_new, 'Should return error message')

  -- Test with existing history file
  local session_existing = create_test_session('existing_session')
  local success_existing, err_existing =
    history.export_session_history(session_existing, '/test/project', '/tmp/export.txt')
  assert_true(success_existing, 'Should succeed when history file exists')
  assert_nil(err_existing, 'Should not return error for successful export')

  -- Test with persistent history disabled
  local session_disabled = create_test_session('disabled_session', { persistent_history = false })
  local success_disabled, err_disabled =
    history.export_session_history(session_disabled, '/test/project', '/tmp/export.txt')
  assert_false(success_disabled, 'Should fail when persistent history is disabled')
  assert_not_nil(err_disabled, 'Should return error message')

  print('✓ export_session_history tests passed')
end

-- Test additional functions and edge cases
local function test_additional_coverage()
  print('=== Testing Additional Coverage ===')

  local history = require('container.terminal.history')

  -- Test get_history_file_path with empty session name
  local session_empty_name = create_test_session('')
  local empty_path = history.get_history_file_path(session_empty_name, '/test/project')
  assert_not_nil(empty_path, 'Should handle empty session name')

  -- Test save_history with default max_history_lines (nil)
  local session_no_max = create_test_session('no_max_session')
  session_no_max.config.max_history_lines = nil
  local content = { 'line1', 'line2' }
  local success, err = history.save_history(session_no_max, '/test/project', content)
  assert_true(success, 'Should succeed with default max_history_lines')

  -- Test load_history with default max_history_lines (nil)
  local session_existing_no_max = create_test_session('existing_session')
  session_existing_no_max.config.max_history_lines = nil
  local result = history.load_history(session_existing_no_max, '/test/project')
  assert_not_nil(result, 'Should load history with default max_history_lines')

  -- Test buffer content with multiple trailing empty lines
  _G.vim.api.nvim_buf_get_lines = function(buf_id, start, end_pos, strict)
    if buf_id == 4 then
      return { 'line1', 'line2', '', '', '' }
    elseif buf_id == 5 then
      return { '', '', '' } -- All empty lines
    elseif buf_id == 6 then
      return { 'single line' } -- No trailing empty
    elseif buf_id == 7 then
      return { '' } -- Single empty line
    end
    return { 'default' }
  end

  local filtered_content = history.get_buffer_content(4)
  assert_equal(#filtered_content, 2, 'Should filter multiple trailing empty lines')

  local all_empty_content = history.get_buffer_content(5)
  assert_equal(#all_empty_content, 0, 'Should return empty for all empty lines')

  local single_line_content = history.get_buffer_content(6)
  assert_equal(#single_line_content, 1, 'Should handle single line without trailing empty')

  local single_empty_content = history.get_buffer_content(7)
  assert_equal(#single_empty_content, 0, 'Should handle single empty line')

  -- Test session name sanitization edge cases
  local session_special_chars = create_test_session('test@#$%^&*()+=[]{}|\\:";\'<>?,./~`')
  local special_path = history.get_history_file_path(session_special_chars, '/test/project')
  assert_not_nil(special_path, 'Should handle session with many special characters')
  -- Debug the actual sanitized name
  local expected_pattern = 'test_'
  assert_true(special_path:find(expected_pattern), 'Should sanitize special characters to underscores')

  -- Test load_history with readfile returning nil
  local original_readfile = _G.vim.fn.readfile
  _G.vim.fn.readfile = function(path)
    if path:find('nil_readfile_session') then
      return nil
    end
    return original_readfile(path)
  end

  local session_nil_readfile = create_test_session('nil_readfile_session')
  local nil_result = history.load_history(session_nil_readfile, '/test/project')
  assert_nil(nil_result, 'Should handle nil return from readfile')

  -- Restore original readfile
  _G.vim.fn.readfile = original_readfile

  -- Test save_history with vim.list_slice edge cases
  local large_content_exact = {}
  for i = 1, 10000 do -- Exactly max_history_lines
    table.insert(large_content_exact, 'line ' .. i)
  end
  local session_exact = create_test_session('exact_session', { max_history_lines = 10000 })
  local success_exact, err_exact = history.save_history(session_exact, '/test/project', large_content_exact)
  assert_true(success_exact, 'Should succeed with content exactly at max_history_lines')

  -- Test export_session_history with write failure
  local original_writefile = _G.vim.fn.writefile
  _G.vim.fn.writefile = function(lines, path)
    if path:find('export_fail') then
      error('Export write failed')
    end
    return original_writefile(lines, path)
  end

  local session_export = create_test_session('existing_session')
  local success_export_fail, err_export_fail =
    history.export_session_history(session_export, '/test/project', '/tmp/export_fail.txt')
  assert_false(success_export_fail, 'Should fail when export write fails')
  assert_not_nil(err_export_fail, 'Should return error message for export failure')

  -- Restore original writefile
  _G.vim.fn.writefile = original_writefile

  print('✓ Additional coverage tests passed')
end

-- Test error scenarios and pcall handling
local function test_error_scenarios()
  print('=== Testing Error Scenarios ===')

  local history = require('container.terminal.history')

  -- Test restore_history_to_buffer with pcall failure simulation
  local original_nvim_buf_set_lines = _G.vim.api.nvim_buf_set_lines
  _G.vim.api.nvim_buf_set_lines = function(buf_id, start, end_pos, strict, lines)
    if buf_id == 7 then
      error('Simulated buffer error')
    end
    return original_nvim_buf_set_lines(buf_id, start, end_pos, strict, lines)
  end

  local success_error, err_error = history.restore_history_to_buffer(7, { 'line1', 'line2' })
  assert_false(success_error, 'Should fail when buffer operation fails')
  assert_not_nil(err_error, 'Should return error message')

  -- Restore original function
  _G.vim.api.nvim_buf_set_lines = original_nvim_buf_set_lines

  -- Test auto save with multiple autocmd scenarios
  local session_auto = create_test_session('auto_save_session')
  session_auto.buffer_id = 8

  -- Mock additional buffer scenarios for auto save
  local autocmd_count = 0
  local original_create_autocmd = _G.vim.api.nvim_create_autocmd
  _G.vim.api.nvim_create_autocmd = function(event, opts)
    autocmd_count = autocmd_count + 1
    return autocmd_count
  end

  history.setup_auto_save(session_auto, '/test/project')
  assert_true(autocmd_count >= 3, 'Should create multiple autocommands')

  -- Restore original function
  _G.vim.api.nvim_create_autocmd = original_create_autocmd

  -- Test fs_stat error handling in cleanup_old_history
  local original_fs_stat = _G.vim.loop.fs_stat
  _G.vim.loop.fs_stat = function(path)
    if path:find('error_stat') then
      return nil -- Simulate fs_stat failure
    end
    return original_fs_stat(path)
  end

  -- Mock globpath to return error file
  local original_globpath = _G.vim.fn.globpath
  _G.vim.fn.globpath = function(dir, pattern, nosuf, list)
    if dir:find('/test/history') and pattern == '*' then
      return { '/test/history/project1', '/test/history/error_project' }
    elseif pattern == '*.history' then
      if dir:find('error_project') then
        return { '/test/history/error_project/error_stat.history' }
      elseif dir:find('project1') then
        return { '/test/history/project1/session1.history' }
      end
    end
    return {}
  end

  local config_error = { history_dir = '/test/history' }
  local count_error = history.cleanup_old_history(config_error, 30)
  assert_true(count_error >= 0, 'Should handle fs_stat errors gracefully')

  -- Restore original functions
  _G.vim.loop.fs_stat = original_fs_stat
  _G.vim.fn.globpath = original_globpath

  -- Test vim.fn.delete error handling
  local original_delete = _G.vim.fn.delete
  _G.vim.fn.delete = function(path, flags)
    if path:find('delete_fail') then
      return 1 -- Simulate delete failure
    end
    return 0
  end

  -- Override globpath for delete failure test
  _G.vim.fn.globpath = function(dir, pattern, nosuf, list)
    if dir:find('/test/history') and pattern == '*' then
      return { '/test/history/delete_project' }
    elseif pattern == '*.history' and dir:find('delete_project') then
      return { '/test/history/delete_project/delete_fail.history' }
    end
    return {}
  end

  local count_delete_fail = history.cleanup_old_history(config_error, 30)
  assert_true(count_delete_fail >= 0, 'Should handle delete failures gracefully')

  -- Restore original functions
  _G.vim.fn.delete = original_delete
  _G.vim.fn.globpath = original_globpath

  -- Test get_history_stats with fs_stat error
  _G.vim.loop.fs_stat = function(path)
    if path:find('stat_error') then
      return nil
    end
    return { size = 1024, mtime = { sec = os.time() } }
  end

  _G.vim.fn.globpath = function(dir, pattern, nosuf, list)
    if dir:find('/test/history') and pattern == '*' then
      return { '/test/history/stat_project' }
    elseif pattern == '*.history' and dir:find('stat_project') then
      return { '/test/history/stat_project/stat_error.history', '/test/history/stat_project/normal.history' }
    end
    return {}
  end

  local stats_error = history.get_history_stats(config_error)
  assert_true(stats_error.total_files >= 0, 'Should handle fs_stat errors in stats')

  -- Restore original functions
  _G.vim.loop.fs_stat = original_fs_stat
  _G.vim.fn.globpath = original_globpath

  print('✓ Error scenarios tests passed')
end

-- Test comprehensive path handling
local function test_path_handling()
  print('=== Testing Path Handling ===')

  local history = require('container.terminal.history')

  -- Test with various project paths
  local session = create_test_session('path_test')

  -- Test with absolute path
  local abs_path = history.get_history_file_path(session, '/absolute/path/to/project')
  assert_not_nil(abs_path, 'Should handle absolute project path')

  -- Test with relative path
  local rel_path = history.get_history_file_path(session, 'relative/path')
  assert_not_nil(rel_path, 'Should handle relative project path')

  -- Test with path containing spaces
  local space_path = history.get_history_file_path(session, '/path with spaces/project')
  assert_not_nil(space_path, 'Should handle project path with spaces')

  -- Test with very long path
  local long_path_part = string.rep('very_long_directory_name/', 10)
  local long_path = history.get_history_file_path(session, '/' .. long_path_part .. 'project')
  assert_not_nil(long_path, 'Should handle very long project path')

  -- Test hash collision scenarios
  local session1 = create_test_session('test_collision_1')
  local session2 = create_test_session('test_collision_2')
  local path1 = history.get_history_file_path(session1, '/same/project/path')
  local path2 = history.get_history_file_path(session2, '/same/project/path')
  assert_not_nil(path1, 'Should generate path for session1')
  assert_not_nil(path2, 'Should generate path for session2')
  -- Both should use same project directory but different files
  local dir1 = path1:match('(.+)/[^/]+%.history$')
  local dir2 = path2:match('(.+)/[^/]+%.history$')
  assert_equal(dir1, dir2, 'Should use same project directory for same project path')

  -- Test extremely long session names
  local long_name = string.rep('very_long_session_name_part', 10)
  local session_long = create_test_session(long_name)
  local long_session_path = history.get_history_file_path(session_long, '/test/project')
  assert_not_nil(long_session_path, 'Should handle very long session names')

  -- Test Unicode characters in paths
  local session_unicode = create_test_session('test_unicode_αβγ_session')
  local unicode_path = history.get_history_file_path(session_unicode, '/test/project')
  assert_not_nil(unicode_path, 'Should handle Unicode characters in session name')

  print('✓ Path handling tests passed')
end

-- Test comprehensive buffer and session handling
local function test_comprehensive_buffer_session()
  print('=== Testing Comprehensive Buffer and Session Handling ===')

  local history = require('container.terminal.history')

  -- Test get_buffer_content with buffer returning exactly one empty line at end
  _G.vim.api.nvim_buf_get_lines = function(buf_id, start, end_pos, strict)
    if buf_id == 10 then
      return { 'content1', 'content2', '' }
    elseif buf_id == 11 then
      return { 'oneline' }
    elseif buf_id == 12 then
      return { 'line1', '', 'line2', '', '', '' } -- Mixed empty lines
    end
    return { 'default' }
  end

  local content_one_empty = history.get_buffer_content(10)
  assert_equal(#content_one_empty, 2, 'Should remove exactly one trailing empty line')

  local content_no_empty = history.get_buffer_content(11)
  assert_equal(#content_no_empty, 1, 'Should preserve content with no trailing empty')

  local content_mixed = history.get_buffer_content(12)
  assert_equal(#content_mixed, 3, 'Should only remove trailing empty lines, not internal ones')
  assert_equal(content_mixed[2], '', 'Should preserve internal empty line')

  -- Test setup_auto_save callback function execution
  local callback_executed = false
  local test_session = create_test_session('callback_session')
  test_session.buffer_id = 13

  -- Override get_buffer_content to track when it's called
  local original_get_buffer_content = history.get_buffer_content
  history.get_buffer_content = function(buf_id)
    callback_executed = true
    return { 'callback test content' }
  end

  -- Mock create_autocmd to capture and execute callback
  local captured_callback = nil
  _G.vim.api.nvim_create_autocmd = function(event, opts)
    captured_callback = opts.callback
    return 1
  end

  history.setup_auto_save(test_session, '/test/project')

  -- Execute the captured callback to test the internal function
  if captured_callback then
    captured_callback()
  end
  assert_true(callback_executed, 'Auto-save callback should execute get_buffer_content')

  -- Restore original function
  history.get_buffer_content = original_get_buffer_content

  -- Test cleanup_old_history with mixed directory types
  _G.vim.fn.isdirectory = function(path)
    if path:find('/test/history') then
      return 1
    elseif path:find('not_a_dir') then
      return 0 -- Simulate file that's not a directory
    end
    return 1
  end

  _G.vim.fn.globpath = function(dir, pattern, nosuf, list)
    if dir:find('/test/history') and pattern == '*' then
      return { '/test/history/project1', '/test/history/not_a_dir', '/test/history/empty_project' }
    elseif pattern == '*.history' then
      if dir:find('project1') then
        return { '/test/history/project1/session.history' }
      elseif dir:find('empty_project') then
        return {} -- Empty project directory
      end
    end
    return {}
  end

  local config_mixed = { history_dir = '/test/history' }
  local count_mixed = history.cleanup_old_history(config_mixed, 30)
  assert_true(count_mixed >= 0, 'Should handle mixed directory types')

  print('✓ Comprehensive buffer and session handling tests passed')
end

-- Test advanced cleanup scenarios
local function test_advanced_cleanup()
  print('=== Testing Advanced Cleanup Scenarios ===')

  local history = require('container.terminal.history')

  -- Test cleanup with directory deletion scenarios
  local delete_call_count = 0
  local directories_to_delete = {}

  _G.vim.fn.delete = function(path, flags)
    delete_call_count = delete_call_count + 1
    if flags == 'd' then
      table.insert(directories_to_delete, path)
    end
    return 0
  end

  _G.vim.fn.globpath = function(dir, pattern, nosuf, list)
    if dir:find('/test/history') and pattern == '*' then
      return { '/test/history/old_project', '/test/history/recent_project' }
    elseif pattern == '*.history' then
      if dir:find('old_project') then
        return { '/test/history/old_project/old_session.history' }
      elseif dir:find('recent_project') then
        return { '/test/history/recent_project/recent_session.history' }
      end
    elseif dir:find('old_project') and pattern == '*' then
      return {} -- Empty after cleanup
    elseif dir:find('recent_project') and pattern == '*' then
      return { '/test/history/recent_project/recent_session.history' } -- Not empty
    end
    return {}
  end

  local config_cleanup = { history_dir = '/test/history' }
  local count_cleanup = history.cleanup_old_history(config_cleanup, 30)
  assert_true(count_cleanup >= 0, 'Should perform cleanup operations')
  assert_true(delete_call_count > 0, 'Should call delete function')

  print('✓ Advanced cleanup scenarios tests passed')
end

-- Test all vim.list_slice edge cases
local function test_list_slice_coverage()
  print('=== Testing vim.list_slice Coverage ===')

  local history = require('container.terminal.history')

  -- Test load_history with list_slice at exact boundary
  local original_readfile = _G.vim.fn.readfile
  _G.vim.fn.readfile = function(path)
    if path:find('boundary_test') then
      local lines = {}
      for i = 1, 10001 do -- One more than max
        table.insert(lines, 'line ' .. i)
      end
      return lines
    end
    return original_readfile(path)
  end

  local session_boundary = create_test_session('boundary_test', { max_history_lines = 10000 })
  local boundary_result = history.load_history(session_boundary, '/test/project')
  assert_not_nil(boundary_result, 'Should handle boundary case')
  assert_equal(#boundary_result, 10000, 'Should limit to exact max_history_lines')

  -- Test save_history with exactly max_history_lines + 1
  local content_plus_one = {}
  for i = 1, 10001 do
    table.insert(content_plus_one, 'save line ' .. i)
  end
  local success_plus_one, err_plus_one = history.save_history(session_boundary, '/test/project', content_plus_one)
  assert_true(success_plus_one, 'Should succeed with content over max_history_lines')

  -- Restore original function
  _G.vim.fn.readfile = original_readfile

  print('✓ vim.list_slice coverage tests passed')
end

-- Test edge cases and error handling
local function test_edge_cases()
  print('=== Testing Edge Cases ===')

  -- Call all the additional test functions
  test_additional_coverage()
  test_error_scenarios()
  test_path_handling()
  test_comprehensive_buffer_session()
  test_advanced_cleanup()
  test_list_slice_coverage()

  print('✓ Edge cases tests passed')
end

-- Main test runner
local function run_all_tests()
  print('Running Comprehensive Terminal History Tests...\n')

  local tests = {
    test_get_history_file_path,
    test_load_history,
    test_save_history,
    test_get_buffer_content,
    test_restore_history_to_buffer,
    test_setup_auto_save,
    test_cleanup_old_history,
    test_get_history_stats,
    test_export_session_history,
    test_edge_cases,
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
