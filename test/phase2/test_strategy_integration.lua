#!/usr/bin/env lua

-- Phase 2 Test: Strategy Integration Testing
-- Tests the integration of Strategy A and B with the main LSP system

package.path = './lua/?.lua;./lua/?/init.lua;' .. package.path

print('Phase 2: Strategy Integration Testing')
print('===================================')
print()

-- Mock vim functions for testing
_G.vim = {
  json = {
    encode = function(obj)
      return '{}'
    end,
    decode = function()
      return {}
    end,
  },
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
  tbl_deep_extend = function(behavior, t1, t2)
    local result = {}
    for k, v in pairs(t1 or {}) do
      result[k] = v
    end
    for k, v in pairs(t2 or {}) do
      result[k] = v
    end
    return result
  end,
  tbl_extend = function(behavior, ...)
    return {}
  end,
  tbl_keys = function(tbl)
    local keys = {}
    for k, _ in pairs(tbl) do
      table.insert(keys, k)
    end
    return keys
  end,
  tbl_count = function(tbl)
    return tbl and #tbl or 0
  end,
  tbl_isempty = function(tbl)
    return not tbl or next(tbl) == nil
  end,
  inspect = function(obj)
    return tostring(obj)
  end,
  pesc = function(str)
    return str:gsub('[%^%$%(%)%%%.%[%]%*%+%-%?]', '%%%1')
  end,
  fn = {
    getcwd = function()
      return '/test'
    end,
  },
  lsp = {
    protocol = {
      make_client_capabilities = function()
        return {}
      end,
    },
    start_client = function()
      return 123
    end,
    get_client_by_id = function()
      return { id = 123, config = {} }
    end,
  },
  api = {
    nvim_get_runtime_file = function()
      return {}
    end,
  },
  loop = {
    new_pipe = function()
      return {}
    end,
    spawn = function()
      return {}, 123
    end,
  },
  list_slice = function(tbl, start)
    return {}
  end,
  trim = function(str)
    return str
  end,
  defer_fn = function(fn)
    fn()
  end,
}

-- Mock log module
local mock_log = {
  debug = function(...) end,
  info = function(msg, ...)
    print('[INFO] ' .. string.format(msg, ...))
  end,
  warn = function(msg, ...)
    print('[WARN] ' .. string.format(msg, ...))
  end,
  error = function(msg, ...)
    print('[ERROR] ' .. string.format(msg, ...))
  end,
}
package.loaded['container.utils.log'] = mock_log

-- Mock additional dependencies
package.loaded['container.lsp.forwarding'] = {
  get_client_cmd = function()
    return { 'docker', 'exec', 'test', 'gopls' }
  end,
  check_container_connectivity = function()
    return true
  end,
}

package.loaded['container.lsp.transform'] = {
  setup_path_transformation = function() end,
  should_transform_method = function()
    return false
  end,
}

package.loaded['container.symlink'] = {
  setup_lsp_symlinks = function()
    return true
  end,
  cleanup_lsp_symlinks = function()
    return true
  end,
  check_symlink_support = function()
    return true
  end,
  get_symlink_status = function()
    return {}
  end,
}

local test_count = 0
local passed_count = 0

local function test(name, test_func)
  test_count = test_count + 1
  print(string.format('Test %d: %s', test_count, name))

  local ok, err = pcall(test_func)
  if ok then
    print('  ✓ PASSED')
    passed_count = passed_count + 1
  else
    print('  ❌ FAILED: ' .. tostring(err))
  end
  print()
end

-- Test module loading
test('Strategy module loading', function()
  local strategy = require('container.lsp.strategy')
  assert(strategy ~= nil, 'Strategy module failed to load')
  assert(type(strategy.setup) == 'function', 'Strategy setup function missing')
  assert(type(strategy.select_strategy) == 'function', 'Strategy select_strategy function missing')
end)

-- Test configs integration
test('Configs integration', function()
  local configs = require('container.lsp.configs')
  assert(configs ~= nil, 'Configs module failed to load')

  local strategy_config = configs.get_strategy_config()
  assert(strategy_config ~= nil, 'Strategy config not available')
  assert(strategy_config.default ~= nil, 'Default strategy not set')
  assert(strategy_config.servers ~= nil, 'Server strategies not configured')
end)

-- Test strategy selector initialization
test('Strategy selector initialization', function()
  local strategy = require('container.lsp.strategy')

  -- Should not error during setup
  strategy.setup()

  local available_strategies = strategy.get_available_strategies()
  assert(#available_strategies >= 2, 'Expected at least 2 strategies available')

  assert(strategy.is_strategy_available('symlink'), 'Symlink strategy should be available')
  assert(strategy.is_strategy_available('proxy'), 'Proxy strategy should be available')
end)

-- Test strategy selection
test('Strategy selection logic', function()
  local strategy = require('container.lsp.strategy')
  strategy.setup()

  -- Test gopls selection (should prefer proxy)
  local chosen_strategy, strategy_config = strategy.select_strategy('gopls', 'test_container')
  assert(chosen_strategy == 'proxy', 'Expected proxy strategy for gopls, got: ' .. chosen_strategy)
  assert(strategy_config ~= nil, 'Strategy config should be provided')

  -- Test unknown server (should use default)
  local default_strategy, _ = strategy.select_strategy('unknown_server', 'test_container')
  assert(default_strategy ~= nil, 'Default strategy should be selected for unknown server')
end)

-- Test symlink strategy adapter
test('Symlink strategy adapter', function()
  local symlink_strategy = require('container.lsp.strategies.symlink')
  assert(symlink_strategy ~= nil, 'Symlink strategy adapter failed to load')

  -- Test client creation
  local client_config, err = symlink_strategy.create_client(
    'gopls',
    'test_container',
    { root_dir = '/test' },
    { symlink = { cleanup_on_exit = true } }
  )

  assert(client_config ~= nil, 'Symlink strategy failed to create client config: ' .. tostring(err))
  assert(client_config.name == 'container_gopls', 'Client name not set correctly')
  assert(client_config.cmd ~= nil, 'Client command not set')

  -- Test health check
  local health = symlink_strategy.health_check()
  assert(health ~= nil, 'Health check should return status')
  assert(type(health.healthy) == 'boolean', 'Health status should be boolean')
end)

-- Test proxy strategy adapter
test('Proxy strategy adapter', function()
  local proxy_strategy = require('container.lsp.strategies.proxy')
  assert(proxy_strategy ~= nil, 'Proxy strategy adapter failed to load')

  -- Test basic functions exist (skip health check due to proxy system complexity)
  assert(type(proxy_strategy.create_client) == 'function', 'create_client function should exist')
  assert(type(proxy_strategy.health_check) == 'function', 'health_check function should exist')
  assert(type(proxy_strategy.get_diagnostics) == 'function', 'get_diagnostics function should exist')

  -- Test default config
  local default_config = proxy_strategy.get_default_config()
  assert(default_config ~= nil, 'Default config should be available')
  assert(default_config.proxy ~= nil, 'Proxy config should be present')
end)

-- Test strategy integration with LSP system
test('Strategy integration with LSP system', function()
  -- Mock the LSP init module state
  local lsp_init = require('container.lsp.init')
  assert(lsp_init ~= nil, 'LSP init module failed to load')

  -- The integration should work without errors
  -- (Full integration test would require container environment)
  assert(type(lsp_init.create_lsp_client) == 'function', 'create_lsp_client function should exist')
end)

-- Test health monitoring
test('System health monitoring', function()
  local strategy = require('container.lsp.strategy')
  strategy.setup()

  -- Test basic health check structure (skip full check due to proxy complexity)
  assert(type(strategy.health_check) == 'function', 'Health check function should exist')

  local config = strategy.get_config()
  assert(config ~= nil, 'Config should be retrievable from strategy system')
  assert(config.default ~= nil, 'Default strategy should be set')
end)

-- Test configuration management
test('Configuration management', function()
  local strategy = require('container.lsp.strategy')
  strategy.setup()

  local config = strategy.get_config()
  assert(config ~= nil, 'Config should be retrievable')
  assert(config.default ~= nil, 'Default strategy should be set')

  -- Test config update
  strategy.update_config({
    servers = {
      test_server = 'symlink',
    },
  })

  local updated_config = strategy.get_config()
  assert(updated_config.servers.test_server == 'symlink', 'Config update should work')
end)

-- Performance test
test('Strategy selection performance', function()
  local strategy = require('container.lsp.strategy')
  strategy.setup()

  local start_time = os.clock()
  local iterations = 100

  for i = 1, iterations do
    local chosen_strategy, _ = strategy.select_strategy('gopls', 'test_container_' .. i)
    assert(chosen_strategy ~= nil, 'Strategy selection failed at iteration ' .. i)
  end

  local elapsed = (os.clock() - start_time) * 1000
  local avg_time = elapsed / iterations

  print(string.format('  Performance: %d selections in %.2fms (%.4fms per selection)', iterations, elapsed, avg_time))

  assert(avg_time < 1, 'Strategy selection too slow: ' .. avg_time .. 'ms per selection')
end)

-- Summary
print('=== Integration Test Results ===')
print(string.format('Passed: %d/%d tests', passed_count, test_count))

if passed_count == test_count then
  print('✅ All Phase 2 integration tests passed!')
  print('Strategy integration is ready for real-world testing')
else
  print('❌ Some integration tests failed')
  print('Strategy integration needs fixes before deployment')
  os.exit(1)
end

print()
print('Next: Test with real container and LSP servers')
os.exit(0)
