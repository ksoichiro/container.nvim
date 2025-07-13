#!/usr/bin/env lua

-- Dedicated coverage test for fs.lua to ensure comprehensive coverage

-- Setup luacov at the very beginning
local function setup_luacov()
  local ok, luacov = pcall(require, 'luacov')
  if ok then
    luacov.init()
    print('✓ Luacov initialized for coverage measurement')
    return true
  else
    print('⚠ Warning: luacov not available, running without coverage')
    return false
  end
end

local has_luacov = setup_luacov()

-- Add project lua directory to package path
package.path = './lua/?.lua;./lua/?/init.lua;' .. package.path

-- Simple test framework
local tests_passed = 0
local tests_failed = 0

local function assert_eq(actual, expected, message)
  if actual == expected then
    tests_passed = tests_passed + 1
    return true
  else
    tests_failed = tests_failed + 1
    print(string.format('✗ FAIL: %s (expected %s, got %s)', message, tostring(expected), tostring(actual)))
    return false
  end
end

local function assert_type(actual, expected_type, message)
  if type(actual) == expected_type then
    tests_passed = tests_passed + 1
    return true
  else
    tests_failed = tests_failed + 1
    print(string.format('✗ FAIL: %s (expected %s, got %s)', message, expected_type, type(actual)))
    return false
  end
end

-- Setup mock vim environment
local vim = {
  fn = {
    filereadable = function(path)
      if not path then
        return 0
      end
      if path:match('existing_file') or path:match('test%.txt') then
        return 1
      end
      return 0
    end,
    isdirectory = function(path)
      if not path then
        return 0
      end
      if path:match('existing_dir') or path:match('workspace') then
        return 1
      end
      return 0
    end,
    mkdir = function(path, flags)
      if path:match('fail_mkdir') then
        return 0
      end
      return 1
    end,
    fnamemodify = function(path, mod)
      if not path then
        return nil
      end
      if mod == ':h' then
        if path == '/' then
          return '/'
        end
        if path == 'file.txt' then
          return '.'
        end
        local parts = {}
        for part in path:gmatch('[^/]+') do
          table.insert(parts, part)
        end
        if #parts <= 1 then
          return '.'
        end
        table.remove(parts)
        local result = table.concat(parts, '/')
        return result == '' and '/' or '/' .. result
      elseif mod == ':t' then
        if path == '/' then
          return ''
        end
        return path:match('[^/]*$') or ''
      elseif mod == ':e' then
        local basename = path:match('[^/]*$') or ''
        if basename:match('^%.') and not basename:match('%..*%.') then
          return ''
        end
        local dot_pos = basename:find('%.[^.]*$')
        return dot_pos and basename:sub(dot_pos + 1) or ''
      elseif mod == ':t:r' then
        local basename = path:match('[^/]*$') or ''
        if basename:match('^%.') and not basename:match('%..*%.') then
          return basename
        end
        local dot_pos = basename:find('%.[^.]*$')
        return dot_pos and basename:sub(1, dot_pos - 1) or basename
      end
      return path
    end,
    getcwd = function()
      return '/test/workspace'
    end,
    tempname = function()
      return '/tmp/test_temp_file_' .. os.time()
    end,
  },
  loop = {
    fs_scandir = function(path)
      if not path or not path:match('existing_dir') then
        return nil
      end
      return {
        { name = 'file1.txt', type = 'file' },
        { name = 'file2.py', type = 'file' },
        { name = 'subdir', type = 'directory' },
      }
    end,
    fs_scandir_next = function(handle)
      if not handle or #handle == 0 then
        return nil, nil
      end
      local entry = table.remove(handle, 1)
      return entry.name, entry.type
    end,
    fs_stat = function(path)
      if not path or path:match('stat_fail') then
        return nil
      end
      return {
        size = 1024,
        mtime = { sec = os.time() - 3600 },
      }
    end,
  },
  split = function(str, delimiter)
    local result = {}
    local pattern = delimiter == '.' and '%.' or delimiter
    for part in (str .. delimiter):gmatch('([^' .. pattern .. ']*)' .. pattern) do
      table.insert(result, part)
    end
    return result
  end,
}

-- Mock io.open for file operations
local original_io_open = io.open
io.open = function(path, mode)
  mode = mode or 'r'
  if mode:match('r') then
    if not path or not path:match('existing_file') then
      return nil
    end
    return {
      read = function(self, format)
        if format == '*all' then
          return 'test file content\nline 2\n'
        end
        return 'test content'
      end,
      close = function() end,
    }
  elseif mode:match('w') then
    if path and path:match('fail_write') then
      return nil
    end
    return {
      write = function(self, data) end,
      close = function() end,
    }
  end
  return nil
end

-- Set global vim
_G.vim = vim

-- Load the fs module
local fs = require('container.utils.fs')

print('=== Dedicated FS Coverage Test Suite ===')
print('')

-- Test 1: normalize_path function with comprehensive cases
print('Test 1: normalize_path function')
assert_eq(fs.normalize_path(nil), nil, 'normalize_path with nil')
assert_eq(fs.normalize_path('/test/path'), '/test/path', 'normalize_path basic')
assert_eq(fs.normalize_path('C:\\Windows\\path'), 'C:/Windows/path', 'normalize_path Windows')
assert_eq(fs.normalize_path('./relative/path'), 'relative/path', 'normalize_path remove leading ./')
assert_eq(fs.normalize_path('/trailing/slash/'), '/trailing/slash', 'normalize_path remove trailing slash')
assert_eq(fs.normalize_path('/'), '/', 'normalize_path root unchanged')

-- Test 2: is_absolute_path function
print('Test 2: is_absolute_path function')
assert_eq(fs.is_absolute_path(nil), false, 'is_absolute_path with nil')
assert_eq(fs.is_absolute_path('/absolute/path'), true, 'is_absolute_path Unix absolute')
assert_eq(fs.is_absolute_path('C:/windows/path'), true, 'is_absolute_path Windows absolute')
assert_eq(fs.is_absolute_path('relative/path'), false, 'is_absolute_path relative')

-- Test 3: join_path function
print('Test 3: join_path function')
assert_eq(fs.join_path(), '', 'join_path no arguments')
assert_eq(fs.join_path('a', 'b', 'c'), 'a/b/c', 'join_path basic')
assert_eq(fs.join_path('', 'a', '', 'b'), 'a/b', 'join_path empty parts ignored')

-- Test 4: resolve_path function
print('Test 4: resolve_path function')
assert_eq(fs.resolve_path('/absolute/path'), '/absolute/path', 'resolve_path already absolute')
assert_eq(fs.resolve_path('relative'), '/test/workspace/relative', 'resolve_path relative to cwd')

-- Test 5: File existence functions with nil handling
print('Test 5: File existence functions')
assert_eq(fs.exists(nil), false, 'exists with nil')
assert_eq(fs.exists('/existing_file.txt'), true, 'exists with existing file')
assert_eq(fs.exists('/nonexistent'), false, 'exists with nonexistent')

assert_eq(fs.is_file(nil), false, 'is_file with nil')
assert_eq(fs.is_file('/existing_file.txt'), true, 'is_file with existing file')
assert_eq(fs.is_file('/existing_dir'), false, 'is_file with directory')

assert_eq(fs.is_directory(nil), false, 'is_directory with nil')
assert_eq(fs.is_directory('/existing_dir'), true, 'is_directory with existing dir')
assert_eq(fs.is_directory('/existing_file.txt'), false, 'is_directory with file')

-- Test 6: File reading with error conditions
print('Test 6: File reading')
local content, err = fs.read_file('/nonexistent.txt')
assert_eq(content, nil, 'read_file nonexistent returns nil')
assert_type(err, 'string', 'read_file nonexistent has error message')

content, err = fs.read_file('/existing_file.txt')
assert_type(content, 'string', 'read_file existing returns content')
assert_eq(err, nil, 'read_file existing has no error')

-- Test 7: Directory operations
print('Test 7: Directory operations')
local success, dir_err = fs.ensure_directory(nil)
assert_eq(success, false, 'ensure_directory with nil fails')
assert_type(dir_err, 'string', 'ensure_directory with nil has error')

success, dir_err = fs.ensure_directory('/existing_dir')
assert_eq(success, true, 'ensure_directory with existing succeeds')

success, dir_err = fs.ensure_directory('/new_dir')
assert_eq(success, true, 'ensure_directory with new dir succeeds')

-- Test 8: File writing
print('Test 8: File writing')
success, err = fs.write_file('/test/new_file.txt', 'content')
assert_eq(success, true, 'write_file succeeds')

success, err = fs.write_file('/fail_write.txt', 'content')
assert_eq(success, false, 'write_file with io error fails')
assert_type(err, 'string', 'write_file with io error has error message')

-- Test 9: Directory listing
print('Test 9: Directory listing')
local files = fs.list_directory('/nonexistent_dir')
assert_eq(#files, 0, 'list_directory nonexistent returns empty')

files = fs.list_directory('/existing_dir')
assert_type(files, 'table', 'list_directory existing returns table')

files = fs.list_directory('/existing_dir', '%.txt$')
assert_type(files, 'table', 'list_directory with pattern returns table')

-- Test 10: File finding
print('Test 10: File finding')
local found = fs.find_files('/nonexistent_dir')
assert_eq(#found, 0, 'find_files nonexistent returns empty')

found = fs.find_files('/existing_dir')
assert_type(found, 'table', 'find_files existing returns table')

found = fs.find_files('/existing_dir', '%.py$')
assert_type(found, 'table', 'find_files with pattern returns table')

found = fs.find_files('/existing_dir', nil, 5)
assert_type(found, 'table', 'find_files with max_depth returns table')

-- Test 11: File metadata
print('Test 11: File metadata')
local size = fs.get_file_size(nil)
assert_eq(size, nil, 'get_file_size with nil')

size = fs.get_file_size('/existing_file.txt')
assert_type(size, 'number', 'get_file_size with existing file')

size = fs.get_file_size('/stat_fail.txt')
assert_eq(size, nil, 'get_file_size with stat failure')

local mtime = fs.get_mtime(nil)
assert_eq(mtime, nil, 'get_mtime with nil')

mtime = fs.get_mtime('/existing_file.txt')
assert_type(mtime, 'number', 'get_mtime with existing file')

-- Test 12: Path component functions
print('Test 12: Path component functions')
assert_eq(fs.basename(nil), nil, 'basename with nil')
assert_eq(fs.basename('/path/to/file.txt'), 'file.txt', 'basename extracts filename')

assert_eq(fs.dirname(nil), nil, 'dirname with nil')
assert_eq(fs.dirname('/path/to/file.txt'), '/path/to', 'dirname extracts directory')

assert_eq(fs.extension(nil), nil, 'extension with nil')
assert_eq(fs.extension('/path/file.txt'), 'txt', 'extension extracts extension')
assert_eq(fs.extension('/path/file'), '', 'extension no extension')

assert_eq(fs.stem(nil), nil, 'stem with nil')
assert_eq(fs.stem('/path/file.txt'), 'file', 'stem extracts name without extension')

-- Test 13: Relative path calculation
print('Test 13: Relative path calculation')
assert_eq(fs.relative_path('/a/b', '/a/b'), '.', 'relative_path same path')
assert_eq(fs.relative_path('/a/b/c', '/a/b'), 'c', 'relative_path simple child')
assert_eq(fs.relative_path('/a/b/c', '/a/d/e'), '../../b/c', 'relative_path complex')

-- Test 14: Temporary file functions
print('Test 14: Temporary file functions')
local temp_dir = fs.get_temp_dir()
assert_type(temp_dir, 'string', 'get_temp_dir returns string')

local temp_file = fs.temp_file()
assert_type(temp_file, 'string', 'temp_file returns string')

temp_file = fs.temp_file('custom', '.txt')
assert_type(temp_file, 'string', 'temp_file with custom prefix/suffix returns string')

-- Test 15: find_file_upward function
print('Test 15: find_file_upward function')
local found_upward = fs.find_file_upward('/test/workspace/sub', 'config.json')
assert_type(found_upward, 'string', 'find_file_upward returns string or nil')

-- Cleanup
io.open = original_io_open

print('')
print('=== Coverage Test Summary ===')
print(string.format('Tests passed: %d', tests_passed))
print(string.format('Tests failed: %d', tests_failed))
print(string.format('Total tests: %d', tests_passed + tests_failed))

if tests_failed > 0 then
  print('Some tests failed!')
  os.exit(1)
else
  print('All tests passed!')
  if has_luacov then
    print('Coverage data recorded by luacov.')
  end
end
