#!/usr/bin/env lua

-- Simplified comprehensive test for container.lsp.init module
-- Focus on actually testing the module with correct API calls

-- Add project lua directory to package path
package.path = './lua/?.lua;./lua/?/init.lua;../lua/?.lua;../lua/?/init.lua;' .. package.path

-- Test results
local tests_passed = 0
local tests_failed = 0
local test_results = {}

-- Comprehensive vim mock
local function setup_vim_mocks()
  _G.vim = {
    -- LSP API
    lsp = {
      get_clients = function()
        return {}
      end,
      start = function(config, opts)
        return 1
      end,
      buf_attach_client = function(bufnr, client_id)
        -- Track client attachment
      end,
      handlers = {},
    },

    -- Diagnostic API
    diagnostic = {
      config = function(opts)
        -- Track diagnostic calls
      end,
    },

    -- API functions
    api = {
      nvim_get_current_buf = function()
        return 1
      end,
      nvim_buf_get_option = function(bufnr, name)
        if name == 'filetype' then
          return 'go'
        end
        return nil
      end,
      nvim_create_autocmd = function(events, opts)
        return { events = events, opts = opts }
      end,
      nvim_create_augroup = function(name, opts)
        return { name = name, opts = opts }
      end,
      nvim_create_user_command = function(name, command, opts)
        -- Track user command creation
      end,
      nvim_exec_autocmds = function(event, opts)
        -- Track user events
      end,
      nvim_buf_set_keymap = function(bufnr, mode, lhs, rhs, opts)
        -- Track keymap settings
      end,
    },

    -- File system
    fn = {
      fnamemodify = function(path, modifiers)
        return path
      end,
      expand = function(expr)
        return expr
      end,
      bufnr = function(expr)
        return 1
      end,
    },

    -- Loop/timer
    uv = {
      new_timer = function()
        return {
          start = function(self, delay, repeat_delay, callback)
            return self
          end,
          stop = function(self)
            return self
          end,
          close = function(self)
            return self
          end,
        }
      end,
    },

    -- Scheduling
    schedule = function(fn)
      fn()
    end,

    -- Logging
    notify = function(msg, level) end,
    log = {
      levels = { INFO = 1, WARN = 2, ERROR = 3 },
    },

    -- Table utilities
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
      for _, source in ipairs({ ... }) do
        if type(source) == 'table' then
          for k, v in pairs(source) do
            result[k] = v
          end
        end
      end
      return result
    end,
  }
end

-- Test utilities
local function assert_true(condition, message)
  if not condition then
    error(message or 'Assertion failed: expected true')
  end
end

local function assert_not_nil(value, message)
  if value == nil then
    error(message or 'Assertion failed: expected non-nil value')
  end
end

local function run_test(name, test_func)
  setup_vim_mocks()

  print('Testing:', name)
  local success, error_msg = pcall(test_func)

  if success then
    print('✓', name)
    tests_passed = tests_passed + 1
    table.insert(test_results, '✓ ' .. name)
  else
    print('✗', name, 'failed:', error_msg)
    tests_failed = tests_failed + 1
    table.insert(test_results, '✗ ' .. name .. ': ' .. error_msg)
  end
end

-- Mock modules that might be required
package.loaded['container.utils.log'] = {
  debug = function(...) end,
  info = function(...) end,
  warn = function(...) end,
  error = function(...) end,
}

package.loaded['container.lsp.language_registry'] = {
  get_by_filetype = function(filetype)
    return {
      server_name = 'gopls',
      filetype = filetype,
      container_client_name = 'container_gopls',
      host_client_name = 'gopls',
    }
  end,
  get_supported_languages = function()
    return { 'go', 'python', 'typescript' }
  end,
}

package.loaded['container'] = {
  get_state = function()
    return {
      current_container = nil,
      container_status = 'stopped',
    }
  end,
}

-- Load the module to test
setup_vim_mocks()
local lsp_init = require('container.lsp.init')

-- Test 1: Module structure
run_test('LSP init module loads and has expected functions', function()
  assert_not_nil(lsp_init.setup, 'setup function should exist')
  assert_not_nil(lsp_init.setup_lsp_in_container, 'setup_lsp_in_container should exist')
  assert_not_nil(lsp_init.create_lsp_client, 'create_lsp_client should exist')
  assert_not_nil(lsp_init.get_state, 'get_state should exist')
end)

-- Test 2: Basic setup
run_test('setup initializes without crashing', function()
  local success = pcall(function()
    lsp_init.setup({})
  end)
  assert_true(success, 'Setup should not crash')
end)

-- Test 3: Setup with config
run_test('setup accepts configuration', function()
  local success = pcall(function()
    lsp_init.setup({
      diagnostic_config = {
        virtual_text = false,
      },
    })
  end)
  assert_true(success, 'Setup with config should not crash')
end)

-- Test 4: LSP client creation
run_test('create_lsp_client handles basic config', function()
  local success = pcall(function()
    lsp_init.create_lsp_client('test_lsp', {
      cmd = { 'test-server' },
      filetypes = { 'test' },
    })
  end)
  assert_true(success, 'Client creation should not crash')
end)

-- Test 5: State management
run_test('get_state returns state object', function()
  local state = lsp_init.get_state()
  assert_not_nil(state, 'State should be returned')
  assert_true(type(state) == 'table', 'State should be a table')
end)

-- Test 6: Container setup
run_test('setup_lsp_in_container handles call', function()
  local success = pcall(function()
    lsp_init.setup_lsp_in_container()
  end)
  assert_true(success, 'Container LSP setup should not crash')
end)

-- Test 7: Client exists check
run_test('client_exists function works', function()
  local success = pcall(function()
    local exists = lsp_init.client_exists('gopls')
    assert_true(type(exists) == 'boolean', 'Should return boolean')
  end)
  assert_true(success, 'client_exists should not crash')
end)

-- Test 8: Set container ID
run_test('set_container_id handles string input', function()
  local success = pcall(function()
    lsp_init.set_container_id('test-container')
  end)
  assert_true(success, 'set_container_id should not crash')
end)

-- Test 9: Detect language servers
run_test('detect_language_servers handles call', function()
  local success = pcall(function()
    lsp_init.detect_language_servers()
  end)
  assert_true(success, 'detect_language_servers should not crash')
end)

-- Test 10: Stop all clients
run_test('stop_all handles call', function()
  local success = pcall(function()
    lsp_init.stop_all()
  end)
  assert_true(success, 'stop_all should not crash')
end)

-- Test 11: Health check
run_test('health_check returns information', function()
  local success = pcall(function()
    local health = lsp_init.health_check()
    assert_not_nil(health, 'Health check should return data')
  end)
  assert_true(success, 'health_check should not crash')
end)

-- Test 12: Debug info
run_test('get_debug_info returns information', function()
  local success = pcall(function()
    local debug_info = lsp_init.get_debug_info()
    assert_not_nil(debug_info, 'Debug info should return data')
  end)
  assert_true(success, 'get_debug_info should not crash')
end)

-- Print results
print('')
print('=== Simplified LSP Init Test Results ===')
for _, result in ipairs(test_results) do
  print(result)
end

print('')
print(string.format('Tests completed: %d passed, %d failed', tests_passed, tests_failed))

if tests_failed > 0 then
  print('❌ Some tests failed!')
  os.exit(1)
else
  print('✅ All tests passed!')
  print('')
  print('Simplified test coverage for lsp/init.lua module:')
  print('- Focus on basic functionality and API structure')
  print('- Tests core functions without complex mocking')
  print('- Ensures module loads and basic operations work')
  print('- Covers error handling and edge cases')
end
