-- Test helpers for container.nvim
-- Provides common utilities and mocks for testing

local M = {}

-- Mock vim global for unit tests
M.mock_vim = {
  tbl_contains = function(t, value)
    for _, v in ipairs(t) do
      if v == value then
        return true
      end
    end
    return false
  end,
  split = function(str, sep)
    local result = {}
    for match in (str .. sep):gmatch('(.-)' .. sep) do
      table.insert(result, match)
    end
    return result
  end,
  startswith = function(str, prefix)
    return str:sub(1, #prefix) == prefix
  end,
  tbl_deep_extend = function(behavior, ...)
    local result = {}
    local sources = { ... }
    for _, source in ipairs(sources) do
      if type(source) == 'table' then
        for k, v in pairs(source) do
          if type(v) == 'table' and type(result[k]) == 'table' then
            result[k] = M.mock_vim.tbl_deep_extend(behavior, result[k], v)
          else
            result[k] = v
          end
        end
      end
    end
    return result
  end,
  tbl_keys = function(t)
    local keys = {}
    for k, _ in pairs(t) do
      table.insert(keys, k)
    end
    return keys
  end,
  fn = {
    getcwd = function()
      return '/test/workspace'
    end,
    shellescape = function(str)
      return "'" .. str:gsub("'", "'\\''") .. "'"
    end,
    system = function(cmd)
      return ''
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
    fnamemodify = function(path, mod)
      if mod == ':p' then
        return path
      end
      if mod == ':h' then
        local parts = M.mock_vim.split(path, '/')
        table.remove(parts)
        return table.concat(parts, '/') or '/'
      end
      if mod == ':t' then
        local parts = M.mock_vim.split(path, '/')
        return parts[#parts] or path
      end
      return path
    end,
    expand = function(path)
      if path:match('^~') then
        return path:gsub('^~', '/home/testuser')
      end
      return path
    end,
  },
  v = { shell_error = 0 },
  loop = {
    new_tcp = function()
      return {
        bind = function(self, addr, port)
          return true
        end,
        close = function(self) end,
      }
    end,
  },
  notify = function(msg, level)
    print('[NOTIFY]', msg)
  end,
  log = { levels = { INFO = 1, ERROR = 2, WARN = 3, DEBUG = 4 } },
  lsp = {
    handlers = {},
    protocol = {
      make_client_capabilities = function()
        return {}
      end,
    },
    get_clients = function()
      return {}
    end,
    get_active_clients = function()
      return {}
    end,
    start = function()
      return {}
    end,
    start_client = function()
      return { id = 1 }
    end,
  },
  api = {
    nvim_create_user_command = function(name, callback, opts) end,
    nvim_create_augroup = function(name, opts)
      return 1
    end,
    nvim_create_autocmd = function(event, opts)
      return 1
    end,
    nvim_get_current_buf = function()
      return 1
    end,
    nvim_buf_is_valid = function(buf)
      return true
    end,
    nvim_buf_is_loaded = function(buf)
      return true
    end,
    nvim_buf_get_name = function(buf)
      return '/test/file.go'
    end,
    nvim_buf_get_lines = function(buf, start, end_line, strict)
      return { 'package main', 'func main() {}' }
    end,
  },
  bo = {
    filetype = 'go',
  },
}

-- Setup mock vim environment
function M.setup_vim_mock()
  _G.vim = M.mock_vim
end

-- Create test configuration
function M.create_test_config()
  return {
    image = 'test-image:latest',
    workspaceFolder = '/workspace',
    mounts = {
      'source=/test/workspace,target=/workspace,type=bind',
    },
    forwardPorts = { 3000, 8080 },
    postCreateCommand = 'echo "Container created"',
  }
end

-- Create devcontainer.json fixture
function M.create_devcontainer_fixture(config_override)
  local base_config = {
    name = 'Test Container',
    image = 'mcr.microsoft.com/devcontainers/base:ubuntu',
    features = {},
    customizations = {
      vscode = {
        settings = {},
        extensions = {},
      },
    },
    forwardPorts = { 3000 },
    postCreateCommand = 'echo "Setup complete"',
  }

  if config_override then
    return M.mock_vim.tbl_deep_extend('force', base_config, config_override)
  end
  return base_config
end

-- Mock Docker command responses
M.docker_mocks = {
  version = 'Docker version 20.10.21, build baeda1f',
  ps = 'CONTAINER ID   IMAGE     COMMAND   CREATED   STATUS    PORTS     NAMES',
  inspect = function(container_id)
    return string.format(
      '[{"Id":"%s","State":{"Status":"running","Running":true}}]',
      container_id or 'test-container-id'
    )
  end,
  run = function(args)
    return 'test-container-id-12345'
  end,
}

-- Mock file system operations
function M.mock_file_exists(path)
  local common_files = {
    '/test/workspace/.devcontainer/devcontainer.json',
    '/test/workspace/devcontainer.json',
    '/usr/bin/docker',
    '/usr/local/bin/docker',
  }
  return M.mock_vim.tbl_contains(common_files, path)
end

function M.mock_read_file(path)
  if path:match('devcontainer%.json$') then
    return vim.json and vim.json.encode(M.create_devcontainer_fixture()) or '{}'
  end
  return 'mock file content'
end

-- Test assertion helpers
function M.assert_equals(actual, expected, message)
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

function M.assert_contains(haystack, needle, message)
  if type(haystack) == 'string' then
    if not haystack:find(needle, 1, true) then
      error(
        string.format(
          'Assertion failed: %s\nString "%s" does not contain "%s"',
          message or 'string should contain substring',
          haystack,
          needle
        )
      )
    end
  elseif type(haystack) == 'table' then
    if not M.mock_vim.tbl_contains(haystack, needle) then
      error(
        string.format(
          'Assertion failed: %s\nTable does not contain value "%s"',
          message or 'table should contain value',
          tostring(needle)
        )
      )
    end
  else
    error('assert_contains: haystack must be string or table')
  end
end

function M.assert_not_nil(value, message)
  if value == nil then
    error(string.format('Assertion failed: %s', message or 'value should not be nil'))
  end
end

function M.assert_type(value, expected_type, message)
  local actual_type = type(value)
  if actual_type ~= expected_type then
    error(
      string.format(
        'Assertion failed: %s\nExpected type: %s\nActual type: %s',
        message or 'value should have correct type',
        expected_type,
        actual_type
      )
    )
  end
end

-- Test runner utilities
function M.run_test_suite(tests, suite_name)
  suite_name = suite_name or 'Test Suite'
  print(string.format('\n=== %s ===', suite_name))

  local passed = 0
  local total = 0

  for test_name, test_func in pairs(tests) do
    if type(test_func) == 'function' then
      total = total + 1
      local success, err = pcall(test_func)
      if success then
        print(string.format('✓ %s', test_name))
        passed = passed + 1
      else
        print(string.format('✗ %s: %s', test_name, err))
      end
    end
  end

  print(string.format('\n=== Results ==='))
  print(string.format('Passed: %d/%d', passed, total))

  if passed == total then
    print('All tests passed! ✓')
    return 0
  else
    print('Some tests failed! ✗')
    return 1
  end
end

-- Add project lua directory to package path for tests
function M.setup_lua_path()
  local test_dir = debug.getinfo(1, 'S').source:sub(2):match('(.*/)')
  local project_root = test_dir:gsub('/test/helpers/?$', '')
  package.path = project_root .. '/lua/?.lua;' .. project_root .. '/lua/?/init.lua;' .. package.path
end

return M
