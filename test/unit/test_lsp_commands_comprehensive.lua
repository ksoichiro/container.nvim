#!/usr/bin/env lua

-- Comprehensive unit tests for container.lsp.commands module
-- This test suite aims to achieve high test coverage for the LSP commands module

-- Add project lua directory to package path
package.path = './lua/?.lua;./lua/?/init.lua;../lua/?.lua;../lua/?/init.lua;' .. package.path

-- Test state for mocking various components
local test_state = {
  lsp_clients = {},
  notifications = {},
  commands = {},
  autocmds = {},
  keymaps = {},
  current_buf = 1,
  buffers = {
    [1] = {
      name = '/test/workspace/main.go',
      lines = { 'package main', 'func main() {}' },
      filetype = 'go',
      valid = true,
      loaded = true,
    },
  },
  lsp_requests = {},
  position = { line = 5, character = 10 },
}

-- Mock simple_transform module
local mock_simple_transform
mock_simple_transform = {
  config = {},
  setup = function(opts)
    mock_simple_transform.config = opts or {}
  end,
  get_buffer_container_uri = function(bufnr)
    bufnr = bufnr or test_state.current_buf
    if bufnr == 0 then
      bufnr = test_state.current_buf
    end
    local buffer = test_state.buffers[bufnr]
    if not buffer or buffer.name == '' then
      return nil
    end
    return 'file:///workspace' .. buffer.name:gsub('/test/workspace', '')
  end,
  transform_locations = function(locations, direction)
    if not locations then
      return locations
    end

    -- Mock deepcopy function for this context
    local function deepcopy(obj)
      if type(obj) ~= 'table' then
        return obj
      end
      local copy = {}
      for k, v in pairs(obj) do
        copy[k] = deepcopy(v)
      end
      return copy
    end

    -- Handle single location
    if locations.uri then
      local transformed = deepcopy(locations)
      if direction == 'to_host' then
        transformed.uri = locations.uri:gsub('file:///workspace', 'file:///test/workspace')
      else
        transformed.uri = locations.uri:gsub('file:///test/workspace', 'file:///workspace')
      end
      return transformed
    end

    -- Handle array of locations
    if type(locations) == 'table' and #locations > 0 then
      local transformed = {}
      for i, loc in ipairs(locations) do
        local new_loc = deepcopy(loc)
        if new_loc.uri then
          if direction == 'to_host' then
            new_loc.uri = new_loc.uri:gsub('file:///workspace', 'file:///test/workspace')
          else
            new_loc.uri = new_loc.uri:gsub('file:///test/workspace', 'file:///workspace')
          end
        end
        transformed[i] = new_loc
      end
      return transformed
    end

    return locations
  end,
  clear_cache = function() end,
  get_config = function()
    return mock_simple_transform.config or {}
  end,
}

-- Mock log module
local mock_log = {
  debug = function(...)
    -- Capture log calls for verification
  end,
  info = function(...)
    test_state.notifications[#test_state.notifications + 1] = { level = 'info', args = { ... } }
  end,
  warn = function(...)
    test_state.notifications[#test_state.notifications + 1] = { level = 'warn', args = { ... } }
  end,
  error = function(...)
    test_state.notifications[#test_state.notifications + 1] = { level = 'error', args = { ... } }
  end,
}

-- Mock vim global with comprehensive LSP support
_G.vim = {
  -- Basic utilities
  tbl_contains = function(t, value)
    for _, v in ipairs(t) do
      if v == value then
        return true
      end
    end
    return false
  end,
  tbl_deep_extend = function(behavior, ...)
    local result = {}
    local function deep_extend(target, source)
      if type(source) ~= 'table' then
        return source
      end
      for k, v in pairs(source) do
        if type(v) == 'table' and type(target[k]) == 'table' and behavior == 'force' then
          target[k] = deep_extend(target[k], v)
        else
          target[k] = v
        end
      end
      return target
    end

    for _, source in ipairs({ ... }) do
      if type(source) == 'table' then
        result = deep_extend(result, source)
      end
    end
    return result
  end,
  tbl_extend = function(behavior, ...)
    local result = {}
    for _, source in ipairs({ ... }) do
      if type(source) == 'table' then
        for k, v in pairs(source) do
          result[k] = v
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
  deepcopy = function(obj)
    if type(obj) ~= 'table' then
      return obj
    end
    local copy = {}
    for k, v in pairs(obj) do
      copy[k] = vim.deepcopy(v)
    end
    return copy
  end,
  startswith = function(str, prefix)
    return str:sub(1, #prefix) == prefix
  end,
  inspect = function(obj)
    if type(obj) == 'table' then
      local parts = {}
      for k, v in pairs(obj) do
        table.insert(parts, tostring(k) .. '=' .. tostring(v))
      end
      return '{' .. table.concat(parts, ', ') .. '}'
    else
      return tostring(obj)
    end
  end,
  pesc = function(str)
    -- Pattern escape function for lua patterns
    return str:gsub('[%^%$%(%)%%%.%[%]%*%+%-%?]', '%%%1')
  end,
  defer_fn = function(fn, timeout)
    -- Mock defer_fn - just call the function immediately in test
    if type(fn) == 'function' then
      fn()
    end
  end,

  -- File system functions
  fn = {
    getcwd = function()
      return '/test/workspace'
    end,
    fnamemodify = function(path, mod)
      if mod == ':p' then
        if not path:match('^/') then
          return '/test/workspace/' .. path
        end
        return path
      end
      return path
    end,
    setqflist = function(list, action, what)
      test_state.quickfix = {
        list = list,
        action = action,
        what = what,
      }
    end,
  },

  -- LSP module
  lsp = {
    get_clients = function()
      return test_state.lsp_clients
    end,
    get_active_clients = function()
      return test_state.lsp_clients
    end,
    handlers = {
      hover = function(err, result, ctx)
        test_state.lsp_requests[#test_state.lsp_requests + 1] = {
          type = 'hover_handler',
          err = err,
          result = result,
          ctx = ctx,
        }
      end,
    },
    util = {
      make_position_params = function(bufnr, encoding)
        return {
          position = test_state.position,
          textDocument = {
            uri = mock_simple_transform.get_buffer_container_uri(bufnr),
          },
        }
      end,
      jump_to_location = function(location, encoding)
        test_state.lsp_requests[#test_state.lsp_requests + 1] = {
          type = 'jump_to_location',
          location = location,
          encoding = encoding,
        }
      end,
      locations_to_items = function(locations, encoding)
        local items = {}
        for i, loc in ipairs(locations) do
          items[i] = {
            filename = loc.uri:gsub('file://', ''),
            lnum = (loc.range and loc.range.start.line or 0) + 1,
            col = (loc.range and loc.range.start.character or 0) + 1,
            text = 'Mock reference ' .. i,
          }
        end
        return items
      end,
    },
  },

  -- API functions
  api = {
    nvim_get_current_buf = function()
      return test_state.current_buf
    end,
    nvim_buf_is_valid = function(bufnr)
      if bufnr == 0 then
        bufnr = test_state.current_buf
      end
      local buffer = test_state.buffers[bufnr]
      return buffer and buffer.valid or false
    end,
    nvim_buf_is_loaded = function(bufnr)
      if bufnr == 0 then
        bufnr = test_state.current_buf
      end
      local buffer = test_state.buffers[bufnr]
      return buffer and buffer.loaded or false
    end,
    nvim_buf_get_name = function(bufnr)
      if bufnr == 0 then
        bufnr = test_state.current_buf
      end
      local buffer = test_state.buffers[bufnr]
      return buffer and buffer.name or ''
    end,
    nvim_buf_get_lines = function(bufnr, start, end_line, strict)
      if bufnr == 0 then
        bufnr = test_state.current_buf
      end
      local buffer = test_state.buffers[bufnr]
      return buffer and buffer.lines or {}
    end,
    nvim_create_user_command = function(name, callback, opts)
      test_state.commands[name] = { callback = callback, opts = opts }
    end,
    nvim_create_augroup = function(name, opts)
      return name .. '_group_id'
    end,
    nvim_create_autocmd = function(event, opts)
      test_state.autocmds[#test_state.autocmds + 1] = {
        event = event,
        opts = opts,
      }
      return #test_state.autocmds
    end,
    nvim_del_augroup_by_name = function(name)
      -- Mock deletion
    end,
    nvim_buf_get_keymap = function(bufnr, mode)
      return test_state.keymaps[bufnr] or {}
    end,
  },

  -- Buffer options
  bo = setmetatable({
    [1] = { filetype = 'go' },
  }, {
    __index = function(t, bufnr)
      if bufnr == 0 then
        bufnr = test_state.current_buf
      end
      return t[bufnr] or { filetype = 'go' }
    end,
  }),

  -- Buffer variables
  b = setmetatable({
    [1] = { changedtick = 1 },
  }, {
    __index = function(t, bufnr)
      if bufnr == 0 then
        bufnr = test_state.current_buf
      end
      return t[bufnr] or { changedtick = 1 }
    end,
  }),

  -- Notification and logging
  notify = function(msg, level)
    test_state.notifications[#test_state.notifications + 1] = {
      level = 'notify',
      message = msg,
      log_level = level,
    }
  end,
  log = {
    levels = {
      ERROR = 1,
      WARN = 2,
      INFO = 3,
      DEBUG = 4,
    },
  },

  -- Quickfix and command execution
  cmd = function(command)
    test_state.commands[#test_state.commands + 1] = command
  end,

  -- Keymap
  keymap = {
    set = function(mode, lhs, rhs, opts)
      local bufnr = opts and opts.buffer or 0
      if not test_state.keymaps[bufnr] then
        test_state.keymaps[bufnr] = {}
      end
      test_state.keymaps[bufnr][lhs] = {
        mode = mode,
        rhs = rhs,
        opts = opts,
      }
    end,
    del = function(mode, lhs, opts)
      local bufnr = opts and opts.buffer or 0
      if test_state.keymaps[bufnr] then
        test_state.keymaps[bufnr][lhs] = nil
      end
    end,
  },
}

-- Setup module mocks
package.loaded['container.utils.log'] = mock_log
package.loaded['container.lsp.simple_transform'] = mock_simple_transform

-- Helper functions for testing
local function reset_test_state()
  test_state.lsp_clients = {}
  test_state.notifications = {}
  test_state.commands = {}
  test_state.autocmds = {}
  test_state.keymaps = {}
  test_state.lsp_requests = {}
  test_state.quickfix = nil
  test_state.current_buf = 1

  -- Reset buffer state
  vim.bo[1] = { filetype = 'go' }
  vim.b[1] = { changedtick = 1 }

  -- Clear module cache for fresh load
  package.loaded['container.lsp.commands'] = nil
end

local function create_mock_lsp_client(server_name, opts)
  opts = opts or {}
  local client = {
    name = 'container_' .. server_name,
    is_stopped = function()
      return opts.stopped or false
    end,
    initialized = opts.initialized ~= false,
    offset_encoding = 'utf-16',
    notify = function(method, params)
      test_state.lsp_requests[#test_state.lsp_requests + 1] = {
        type = 'notify',
        method = method,
        params = params,
      }
    end,
    request = function(method, params, callback, bufnr)
      test_state.lsp_requests[#test_state.lsp_requests + 1] = {
        type = 'request',
        method = method,
        params = params,
        callback = callback,
        bufnr = bufnr,
      }

      -- Simulate async response for some methods
      if callback then
        local function simulate_response()
          local result = nil
          local err = nil

          if method == 'textDocument/hover' then
            if opts.hover_error then
              err = opts.hover_error
            else
              result = {
                contents = {
                  kind = 'markdown',
                  value = 'Mock hover content',
                },
              }
            end
          elseif method == 'textDocument/definition' then
            if opts.definition_error then
              err = opts.definition_error
            else
              result = opts.definition_result
                or {
                  uri = 'file:///workspace/main.go',
                  range = {
                    start = { line = 10, character = 5 },
                    ['end'] = { line = 10, character = 15 },
                  },
                }
            end
          elseif method == 'textDocument/references' then
            if opts.references_error then
              err = opts.references_error
            else
              result = opts.references_result
                or {
                  {
                    uri = 'file:///workspace/main.go',
                    range = {
                      start = { line = 10, character = 5 },
                      ['end'] = { line = 10, character = 15 },
                    },
                  },
                  {
                    uri = 'file:///workspace/utils.go',
                    range = {
                      start = { line = 5, character = 0 },
                      ['end'] = { line = 5, character = 10 },
                    },
                  },
                }
            end
          end

          callback(err, result, { method = method })
        end

        -- Simulate async behavior
        vim.defer_fn(simulate_response, 1)
      end
    end,
  }

  return client
end

local function assert_equals(actual, expected, message)
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

local function assert_contains(haystack, needle, message)
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
    local found = false
    for _, v in ipairs(haystack) do
      if v == needle then
        found = true
        break
      end
    end
    if not found then
      error(
        string.format(
          'Assertion failed: %s\nTable does not contain value "%s"',
          message or 'table should contain value',
          tostring(needle)
        )
      )
    end
  end
end

local function assert_not_nil(value, message)
  if value == nil then
    error(string.format('Assertion failed: %s', message or 'value should not be nil'))
  end
end

local function assert_type(value, expected_type, message)
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

-- Test suite
local tests = {}

function tests.test_module_loading()
  local commands = require('container.lsp.commands')
  assert_not_nil(commands, 'Commands module should load successfully')
  assert_type(commands, 'table', 'Commands module should be a table')
end

function tests.test_setup()
  reset_test_state()
  local commands = require('container.lsp.commands')

  -- Test setup with default options
  commands.setup()

  -- Test setup with custom options
  commands.setup({
    host_workspace = '/custom/host',
    container_workspace = '/custom/container',
  })

  -- Verify transform module was configured
  local config = mock_simple_transform.get_config()
  assert_equals(config.host_workspace, '/custom/host', 'Host workspace should be set')
  assert_equals(config.container_workspace, '/custom/container', 'Container workspace should be set')
end

function tests.test_get_container_client_found()
  reset_test_state()
  local commands = require('container.lsp.commands')

  -- Setup mock client
  local mock_client = create_mock_lsp_client('gopls')
  test_state.lsp_clients = { mock_client }

  local client = commands.get_container_client('gopls')
  assert_not_nil(client, 'Should find container client')
  assert_equals(client.name, 'container_gopls', 'Should return correct client')
end

function tests.test_get_container_client_not_found()
  reset_test_state()
  local commands = require('container.lsp.commands')

  test_state.lsp_clients = {}

  local client = commands.get_container_client('gopls')
  assert_equals(client, nil, 'Should return nil when client not found')
end

function tests.test_validate_lsp_prerequisites_invalid_buffer()
  reset_test_state()
  local commands = require('container.lsp.commands')
  commands.setup()

  -- Setup invalid buffer
  test_state.buffers[1].valid = false

  local valid, error_msg = commands._validate_lsp_prerequisites('gopls')
  assert_equals(valid, false, 'Should fail validation for invalid buffer')
  assert_contains(error_msg, 'Invalid', 'Error message should mention invalid buffer')
end

function tests.test_validate_lsp_prerequisites_no_filetype()
  reset_test_state()
  local commands = require('container.lsp.commands')
  commands.setup()

  -- Setup buffer with no filetype - must be done after reset
  vim.bo[test_state.current_buf] = { filetype = '' }

  local valid, error_msg = commands._validate_lsp_prerequisites('gopls')
  assert_equals(valid, false, 'Should fail validation for no filetype')
  assert_contains(error_msg, 'filetype', 'Error message should mention filetype')
end

function tests.test_validate_lsp_prerequisites_not_initialized()
  reset_test_state()
  local commands = require('container.lsp.commands')
  -- Don't call setup() - should fail prerequisites

  -- Make sure buffer is valid and has filetype to reach initialization check
  vim.bo[test_state.current_buf] = { filetype = 'go' }

  local valid, error_msg = commands._validate_lsp_prerequisites('gopls')
  assert_equals(valid, false, 'Should fail validation when not initialized')
  assert_contains(error_msg, 'not initialized', 'Error message should mention initialization')
end

function tests.test_validate_lsp_prerequisites_success()
  reset_test_state()
  local commands = require('container.lsp.commands')
  commands.setup()

  local valid, error_msg = commands._validate_lsp_prerequisites('gopls')
  assert_equals(valid, true, 'Should pass validation')
  assert_equals(error_msg, nil, 'Error message should be nil on success')
end

function tests.test_get_validated_client_not_found()
  reset_test_state()
  local commands = require('container.lsp.commands')

  test_state.lsp_clients = {}

  local client, error_msg = commands._get_validated_client('gopls')
  assert_equals(client, nil, 'Should return nil when client not found')
  assert_contains(error_msg, 'No gopls client found', 'Error message should mention client not found')
end

function tests.test_get_validated_client_stopped()
  reset_test_state()
  local commands = require('container.lsp.commands')

  local mock_client = create_mock_lsp_client('gopls', { stopped = true })
  test_state.lsp_clients = { mock_client }

  local client, error_msg = commands._get_validated_client('gopls')
  assert_equals(client, nil, 'Should return nil when client is stopped')
  assert_contains(error_msg, 'stopped', 'Error message should mention stopped client')
end

function tests.test_get_validated_client_not_initialized()
  reset_test_state()
  local commands = require('container.lsp.commands')

  local mock_client = create_mock_lsp_client('gopls', { initialized = false })
  test_state.lsp_clients = { mock_client }

  local client, error_msg = commands._get_validated_client('gopls')
  assert_equals(client, nil, 'Should return nil when client not initialized')
  assert_contains(error_msg, 'not yet initialized', 'Error message should mention initialization')
end

function tests.test_get_validated_client_success()
  reset_test_state()
  local commands = require('container.lsp.commands')

  local mock_client = create_mock_lsp_client('gopls')
  test_state.lsp_clients = { mock_client }

  local client, error_msg = commands._get_validated_client('gopls')
  assert_not_nil(client, 'Should return client when valid')
  assert_equals(error_msg, nil, 'Error message should be nil on success')
end

function tests.test_register_file_no_client()
  reset_test_state()
  local commands = require('container.lsp.commands')

  local success = commands.register_file(0, nil)
  assert_equals(success, false, 'Should return false when no client provided')
end

function tests.test_register_file_empty_path()
  reset_test_state()
  local commands = require('container.lsp.commands')

  test_state.buffers[1].name = ''
  local mock_client = create_mock_lsp_client('gopls')

  local success = commands.register_file(0, mock_client)
  assert_equals(success, false, 'Should return false for empty file path')
end

function tests.test_register_file_success()
  reset_test_state()
  local commands = require('container.lsp.commands')
  commands.setup()

  local mock_client = create_mock_lsp_client('gopls')

  local success = commands.register_file(0, mock_client)
  assert_equals(success, true, 'Should successfully register file')

  -- Check that didOpen was sent
  local found_did_open = false
  for _, req in ipairs(test_state.lsp_requests) do
    if req.type == 'notify' and req.method == 'textDocument/didOpen' then
      found_did_open = true
      assert_not_nil(req.params.textDocument, 'didOpen should have textDocument')
      assert_contains(req.params.textDocument.uri, 'workspace', 'URI should contain workspace')
      break
    end
  end
  assert_equals(found_did_open, true, 'Should send didOpen notification')
end

function tests.test_register_file_already_registered()
  reset_test_state()
  local commands = require('container.lsp.commands')
  commands.setup()

  local mock_client = create_mock_lsp_client('gopls')

  -- Register file first time
  local success1 = commands.register_file(0, mock_client)
  assert_equals(success1, true, 'First registration should succeed')

  -- Register same file again
  local success2 = commands.register_file(0, mock_client)
  assert_equals(success2, true, 'Second registration should also succeed (cached)')

  -- Check that only one didOpen was sent
  local did_open_count = 0
  for _, req in ipairs(test_state.lsp_requests) do
    if req.type == 'notify' and req.method == 'textDocument/didOpen' then
      did_open_count = did_open_count + 1
    end
  end
  assert_equals(did_open_count, 1, 'Should send didOpen only once')
end

function tests.test_hover_prerequisites_fail()
  reset_test_state()
  local commands = require('container.lsp.commands')
  -- Don't call setup() - should fail prerequisites

  local success = commands.hover()
  assert_equals(success, false, 'Should return false when prerequisites fail')

  -- Check notification was sent
  local found_error = false
  for _, notif in ipairs(test_state.notifications) do
    if notif.level == 'notify' and notif.message:match('not initialized') then
      found_error = true
      break
    end
  end
  assert_equals(found_error, true, 'Should notify about error')
end

function tests.test_hover_no_client()
  reset_test_state()
  local commands = require('container.lsp.commands')
  commands.setup()

  test_state.lsp_clients = {}

  local success = commands.hover()
  assert_equals(success, false, 'Should return false when no client found')
end

function tests.test_hover_success()
  reset_test_state()
  local commands = require('container.lsp.commands')
  commands.setup()

  local mock_client = create_mock_lsp_client('gopls')
  test_state.lsp_clients = { mock_client }

  local success = commands.hover()
  assert_equals(success, true, 'Should return true on successful hover request')

  -- Check that hover request was sent
  local found_hover = false
  for _, req in ipairs(test_state.lsp_requests) do
    if req.type == 'request' and req.method == 'textDocument/hover' then
      found_hover = true
      assert_not_nil(req.params.textDocument, 'Hover should have textDocument')
      assert_not_nil(req.params.position, 'Hover should have position')
      break
    end
  end
  assert_equals(found_hover, true, 'Should send hover request')
end

function tests.test_hover_request_error()
  reset_test_state()
  local commands = require('container.lsp.commands')
  commands.setup()

  -- Mock pcall to simulate request error
  local original_pcall = pcall
  _G.pcall = function(func, ...)
    if type(func) == 'function' then
      local args = { ... }
      if args[1] and type(args[1]) == 'table' and args[1].request then
        return false, 'Simulated request error'
      end
    end
    return original_pcall(func, ...)
  end

  local mock_client = create_mock_lsp_client('gopls')
  test_state.lsp_clients = { mock_client }

  local success = commands.hover()
  assert_equals(success, false, 'Should return false when request fails')

  -- Restore original pcall
  _G.pcall = original_pcall
end

function tests.test_definition_no_client()
  reset_test_state()
  local commands = require('container.lsp.commands')

  test_state.lsp_clients = {}

  commands.definition()

  -- Check that error notification was sent
  local found_error = false
  for _, notif in ipairs(test_state.notifications) do
    if notif.level == 'notify' and notif.message:match('No gopls client found') then
      found_error = true
      break
    end
  end
  assert_equals(found_error, true, 'Should notify about missing client')
end

function tests.test_definition_success()
  reset_test_state()
  local commands = require('container.lsp.commands')
  commands.setup()

  local mock_client = create_mock_lsp_client('gopls')
  test_state.lsp_clients = { mock_client }

  commands.definition()

  -- Check that definition request was sent
  local found_definition = false
  for _, req in ipairs(test_state.lsp_requests) do
    if req.type == 'request' and req.method == 'textDocument/definition' then
      found_definition = true
      assert_not_nil(req.params.textDocument, 'Definition should have textDocument')
      assert_not_nil(req.params.position, 'Definition should have position')
      break
    end
  end
  assert_equals(found_definition, true, 'Should send definition request')
end

function tests.test_references_no_client()
  reset_test_state()
  local commands = require('container.lsp.commands')

  test_state.lsp_clients = {}

  commands.references()

  -- Check that error notification was sent
  local found_error = false
  for _, notif in ipairs(test_state.notifications) do
    if notif.level == 'notify' and notif.message:match('No gopls client found') then
      found_error = true
      break
    end
  end
  assert_equals(found_error, true, 'Should notify about missing client')
end

function tests.test_references_success()
  reset_test_state()
  local commands = require('container.lsp.commands')
  commands.setup()

  local mock_client = create_mock_lsp_client('gopls')
  test_state.lsp_clients = { mock_client }

  commands.references()

  -- Check that references request was sent
  local found_references = false
  for _, req in ipairs(test_state.lsp_requests) do
    if req.type == 'request' and req.method == 'textDocument/references' then
      found_references = true
      assert_not_nil(req.params.textDocument, 'References should have textDocument')
      assert_not_nil(req.params.position, 'References should have position')
      assert_not_nil(req.params.context, 'References should have context')
      break
    end
  end
  assert_equals(found_references, true, 'Should send references request')
end

function tests.test_setup_commands()
  reset_test_state()
  local commands = require('container.lsp.commands')

  commands.setup_commands()

  -- Check that user commands were created
  local expected_commands = {
    'ContainerLspHover',
    'ContainerLspDefinition',
    'ContainerLspReferences',
    'ContainerLspSetupKeys',
    'ContainerLspDebugDiagnostics',
  }

  for _, cmd_name in ipairs(expected_commands) do
    assert_not_nil(test_state.commands[cmd_name], 'Command should be created: ' .. cmd_name)
  end
end

function tests.test_setup_keybindings_invalid_buffer()
  reset_test_state()
  local commands = require('container.lsp.commands')

  test_state.buffers[999] = nil -- Non-existent buffer

  local success = commands.setup_keybindings({ buffer = 999 })
  assert_equals(success, false, 'Should return false for invalid buffer')
end

function tests.test_setup_keybindings_success()
  reset_test_state()
  local commands = require('container.lsp.commands')

  local success = commands.setup_keybindings()
  assert_equals(success, true, 'Should successfully setup keybindings')

  -- Check that keybindings were set
  local keymaps = test_state.keymaps[0] or test_state.keymaps[1]
  assert_not_nil(keymaps, 'Keymaps should be set')
  assert_not_nil(keymaps['K'], 'Hover keybinding should be set')
  assert_not_nil(keymaps['gd'], 'Definition keybinding should be set')
  assert_not_nil(keymaps['gr'], 'References keybinding should be set')
end

function tests.test_setup_keybindings_custom()
  reset_test_state()
  local commands = require('container.lsp.commands')

  local success = commands.setup_keybindings({
    keybindings = {
      hover = '<leader>h',
      definition = '<leader>d',
      references = '<leader>r',
    },
  })
  assert_equals(success, true, 'Should successfully setup custom keybindings')

  -- Check custom keybindings
  local keymaps = test_state.keymaps[0] or test_state.keymaps[1]
  assert_not_nil(keymaps['<leader>h'], 'Custom hover keybinding should be set')
  assert_not_nil(keymaps['<leader>d'], 'Custom definition keybinding should be set')
  assert_not_nil(keymaps['<leader>r'], 'Custom references keybinding should be set')
end

function tests.test_get_state()
  reset_test_state()
  local commands = require('container.lsp.commands')
  commands.setup()

  local state = commands.get_state()
  assert_not_nil(state, 'Should return state')
  assert_type(state.initialized, 'boolean', 'State should have initialized flag')
  assert_type(state.registered_files, 'table', 'State should have registered files')
  assert_type(state.transform_config, 'table', 'State should have transform config')
end

function tests.test_clear_registered_files()
  reset_test_state()
  local commands = require('container.lsp.commands')
  commands.setup()

  -- Register a file first
  local mock_client = create_mock_lsp_client('gopls')
  commands.register_file(0, mock_client)

  -- Clear registered files
  commands.clear_registered_files()

  local state = commands.get_state()
  assert_equals(#state.registered_files, 0, 'Registered files should be cleared')
end

function tests.test_buffer_tracking_setup()
  reset_test_state()
  local commands = require('container.lsp.commands')
  commands.setup()

  local mock_client = create_mock_lsp_client('gopls')
  commands.register_file(0, mock_client)

  -- Check that autocmds were created for tracking
  local text_changed_found = false
  local buf_write_found = false
  local buf_delete_found = false

  for _, autocmd in ipairs(test_state.autocmds) do
    if autocmd.event == 'TextChanged' then
      text_changed_found = true
    elseif autocmd.event == 'BufWritePost' then
      buf_write_found = true
    elseif autocmd.event == 'BufDelete' then
      buf_delete_found = true
    end
  end

  assert_equals(text_changed_found, true, 'TextChanged autocmd should be created')
  assert_equals(buf_write_found, true, 'BufWritePost autocmd should be created')
  assert_equals(buf_delete_found, true, 'BufDelete autocmd should be created')
end

-- Test runner
local function run_tests()
  print('Starting container.lsp.commands comprehensive tests...\n')

  local passed = 0
  local total = 0

  for test_name, test_func in pairs(tests) do
    if type(test_func) == 'function' then
      total = total + 1
      local success, err = pcall(test_func)
      if success then
        print('✓ ' .. test_name)
        passed = passed + 1
      else
        print('✗ ' .. test_name .. ': ' .. err)
      end
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

-- Run tests
local exit_code = run_tests()
os.exit(exit_code)
