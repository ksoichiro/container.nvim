#!/usr/bin/env lua

-- Phase 1 Test: Path Transform Module Testing
-- Tests the path transformation engine for LSP proxy

package.path = './lua/?.lua;./lua/?/init.lua;' .. package.path

print('Phase 1: Path Transform Module Testing')
print('======================================')
print()

-- Mock vim functions for testing
_G.vim = {
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
  tbl_keys = function(tbl)
    local keys = {}
    for k, _ in pairs(tbl) do
      table.insert(keys, k)
    end
    return keys
  end,
  pesc = function(str)
    -- Escape special characters for pattern matching
    return str:gsub('[%^%$%(%)%%%.%[%]%*%+%-%?]', '%%%1')
  end,
  inspect = function(obj)
    return tostring(obj)
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

-- Load the transform module
local transform = require('container.lsp.proxy.transform')

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

-- Initialize transform module
transform.setup('/Users/testuser/project', '/workspace')

-- Test basic path transformation
test('Basic path transformation', function()
  -- Host to container
  local host_path = '/Users/testuser/project/main.go'
  local container_path = transform.host_to_container_path(host_path)
  assert(container_path == '/workspace/main.go', 'Expected /workspace/main.go, got ' .. container_path)

  -- Container to host
  local back_to_host = transform.container_to_host_path(container_path)
  assert(back_to_host == host_path, 'Expected ' .. host_path .. ', got ' .. back_to_host)
end)

-- Test URI transformation
test('URI transformation', function()
  -- Host URI to container URI
  local host_uri = 'file:///Users/testuser/project/src/lib.go'
  local container_uri = transform.host_to_container_path(host_uri)
  assert(
    container_uri == 'file:///workspace/src/lib.go',
    'Expected file:///workspace/src/lib.go, got ' .. container_uri
  )

  -- Container URI to host URI
  local back_to_host_uri = transform.container_to_host_path(container_uri)
  assert(back_to_host_uri == host_uri, 'Expected ' .. host_uri .. ', got ' .. back_to_host_uri)
end)

-- Test paths outside workspace
test('Paths outside workspace', function()
  -- Path not in workspace should remain unchanged
  local external_path = '/usr/local/bin/gopls'
  local transformed = transform.host_to_container_path(external_path)
  assert(transformed == external_path, 'External path should remain unchanged: ' .. transformed)

  -- Container path not in workspace
  local external_container_path = '/usr/local/go/src/fmt'
  local transformed_back = transform.container_to_host_path(external_container_path)
  assert(
    transformed_back == external_container_path,
    'External container path should remain unchanged: ' .. transformed_back
  )
end)

-- Test edge cases
test('Edge cases', function()
  -- Nil input
  local nil_result = transform.host_to_container_path(nil)
  assert(nil_result == nil, 'Nil input should return nil')

  -- Empty string
  local empty_result = transform.host_to_container_path('')
  assert(empty_result == '', 'Empty string should return empty string')

  -- Non-string input
  local number_result = transform.host_to_container_path(123)
  assert(number_result == 123, 'Non-string input should be returned as-is')
end)

-- Test request transformation
test('Request transformation (host → container)', function()
  local request_message = {
    jsonrpc = '2.0',
    method = 'textDocument/didOpen',
    params = {
      textDocument = {
        uri = 'file:///Users/testuser/project/main.go',
        languageId = 'go',
        version = 1,
        text = 'package main',
      },
    },
  }

  local transformed = transform.transform_request_to_container(request_message)

  assert(
    transformed.params.textDocument.uri == 'file:///workspace/main.go',
    'URI not transformed in request: ' .. transformed.params.textDocument.uri
  )
  assert(transformed.params.textDocument.languageId == 'go', 'Other fields should remain unchanged')
end)

-- Test response transformation
test('Response transformation (container → host)', function()
  local response_message = {
    jsonrpc = '2.0',
    id = 1,
    result = {
      {
        uri = 'file:///workspace/lib.go',
        range = {
          start = { line = 10, character = 5 },
          ['end'] = { line = 10, character = 15 },
        },
      },
    },
  }

  local transformed = transform.transform_response_to_host(response_message, 'textDocument/definition')

  assert(
    transformed.result[1].uri == 'file:///Users/testuser/project/lib.go',
    'URI not transformed in response: ' .. transformed.result[1].uri
  )
  assert(transformed.result[1].range.start.line == 10, 'Other fields should remain unchanged')
end)

-- Test initialize request transformation
test('Initialize request transformation', function()
  local initialize_request = {
    jsonrpc = '2.0',
    method = 'initialize',
    id = 1,
    params = {
      rootUri = 'file:///Users/testuser/project',
      workspaceFolders = {
        {
          uri = 'file:///Users/testuser/project',
          name = 'project',
        },
      },
      capabilities = {},
    },
  }

  local transformed = transform.transform_request_to_container(initialize_request)

  assert(transformed.params.rootUri == 'file:///workspace', 'rootUri not transformed: ' .. transformed.params.rootUri)
  assert(
    transformed.params.workspaceFolders[1].uri == 'file:///workspace',
    'workspaceFolders URI not transformed: ' .. transformed.params.workspaceFolders[1].uri
  )
end)

-- Test publishDiagnostics notification transformation
test('PublishDiagnostics notification transformation', function()
  local notification = {
    jsonrpc = '2.0',
    method = 'textDocument/publishDiagnostics',
    params = {
      uri = 'file:///workspace/main.go',
      diagnostics = {
        {
          range = {
            start = { line = 5, character = 10 },
            ['end'] = { line = 5, character = 20 },
          },
          message = 'undefined variable',
          severity = 1,
        },
      },
    },
  }

  local transformed = transform.transform_response_to_host(notification, 'textDocument/publishDiagnostics')

  assert(
    transformed.params.uri == 'file:///Users/testuser/project/main.go',
    'Diagnostic URI not transformed: ' .. transformed.params.uri
  )
  assert(
    transformed.params.diagnostics[1].message == 'undefined variable',
    'Diagnostic content should remain unchanged'
  )
end)

-- Test caching
test('Path transformation caching', function()
  -- Clear cache first
  transform.clear_cache()

  local initial_stats = transform.get_cache_stats()
  assert(initial_stats.hits == 0, 'Cache should start empty')
  assert(initial_stats.misses == 0, 'Cache should start empty')

  -- Transform same path multiple times
  local test_path = '/Users/testuser/project/test.go'

  transform.host_to_container_path(test_path) -- Miss
  transform.host_to_container_path(test_path) -- Hit
  transform.host_to_container_path(test_path) -- Hit

  local final_stats = transform.get_cache_stats()
  assert(final_stats.hits == 2, 'Expected 2 cache hits, got ' .. final_stats.hits)
  assert(final_stats.misses == 1, 'Expected 1 cache miss, got ' .. final_stats.misses)
  assert(final_stats.hit_rate == 2 / 3, 'Expected hit rate 0.67, got ' .. final_stats.hit_rate)
end)

-- Test configuration validation
test('Configuration validation', function()
  -- Valid configuration
  local is_valid, err = transform.validate_config()
  assert(is_valid, 'Valid configuration failed validation: ' .. tostring(err))

  -- Clear configuration to test invalid state
  local old_config = transform.config
  transform.config = nil

  local is_invalid, _ = transform.validate_config()
  assert(not is_invalid, 'Invalid configuration passed validation')

  -- Restore configuration
  transform.config = old_config
end)

-- Test transformation rules
test('Transformation rules', function()
  -- Get all rules
  local rules = transform.get_transformation_rules()
  assert(rules['textDocument/definition'] ~= nil, 'Missing definition transformation rule')
  assert(rules['initialize'] ~= nil, 'Missing initialize transformation rule')

  -- Add custom rule
  transform.add_transformation_rule('custom/method', {
    request = { 'customUri' },
    response = { 'customResult.uri' },
  })

  local updated_rules = transform.get_transformation_rules()
  assert(updated_rules['custom/method'] ~= nil, 'Custom rule not added')

  -- Remove custom rule
  transform.remove_transformation_rule('custom/method')

  local final_rules = transform.get_transformation_rules()
  assert(final_rules['custom/method'] == nil, 'Custom rule not removed')
end)

-- Performance test
test('Performance test', function()
  local start_time = os.clock()
  local iterations = 1000

  for i = 1, iterations do
    local test_path = '/Users/testuser/project/file' .. i .. '.go'
    local container_path = transform.host_to_container_path(test_path)
    local back_to_host = transform.container_to_host_path(container_path)
    assert(back_to_host == test_path, 'Performance test failed at iteration ' .. i)
  end

  local elapsed = (os.clock() - start_time) * 1000
  local avg_time = elapsed / iterations

  print(
    string.format(
      '  Performance: %d transformations in %.2fms (%.4fms per operation)',
      iterations * 2,
      elapsed,
      avg_time
    )
  )

  assert(avg_time < 1, 'Performance too slow: ' .. avg_time .. 'ms per operation')
end)

-- Test run transformation tests
test('Transformation test runner', function()
  local test_cases = {
    {
      input = '/Users/testuser/project/main.go',
      expected = '/workspace/main.go',
      direction = 'host_to_container',
    },
    {
      input = 'file:///workspace/lib.go',
      expected = 'file:///Users/testuser/project/lib.go',
      direction = 'container_to_host',
    },
    {
      input = '/usr/local/bin/gopls',
      expected = '/usr/local/bin/gopls',
      direction = 'host_to_container',
    },
  }

  local results = transform.run_transformation_tests(test_cases)

  assert(#results == 3, 'Expected 3 test results, got ' .. #results)
  assert(results[1].passed, 'First test case should pass')
  assert(results[2].passed, 'Second test case should pass')
  assert(results[3].passed, 'Third test case should pass')
end)

-- Summary
print('=== Test Results ===')
print(string.format('Passed: %d/%d tests', passed_count, test_count))

if passed_count == test_count then
  print('✅ All path transformation tests passed!')
  print('Transform module is ready for integration')
else
  print('❌ Some tests failed')
  print('Transform module needs fixes before integration')
  os.exit(1)
end

print()
print('Cache statistics:')
local stats = transform.get_cache_stats()
print(string.format('  Hits: %d, Misses: %d, Hit rate: %.2f%%', stats.hits, stats.misses, stats.hit_rate * 100))

print()
print('Next: Test transport layer and proxy server integration')
os.exit(0)
