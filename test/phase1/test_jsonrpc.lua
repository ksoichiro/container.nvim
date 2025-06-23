#!/usr/bin/env lua

-- Phase 1 Test: JSON-RPC Module Testing
-- Tests the core JSON-RPC message processing functionality

package.path = './lua/?.lua;./lua/?/init.lua;' .. package.path

print('Phase 1: JSON-RPC Module Testing')
print('=================================')
print()

-- Mock vim functions for testing
_G.vim = {
  json = {
    encode = function(obj)
      -- Simple JSON encoding for testing
      if type(obj) == 'table' then
        local parts = {}
        for k, v in pairs(obj) do
          local key = '"' .. tostring(k) .. '"'
          local value
          if type(v) == 'string' then
            value = '"' .. v .. '"'
          elseif type(v) == 'number' then
            value = tostring(v)
          elseif type(v) == 'boolean' then
            value = tostring(v)
          elseif v == nil then
            value = 'null'
          elseif type(v) == 'table' then
            value = vim.json.encode(v)
          else
            value = '"' .. tostring(v) .. '"'
          end
          table.insert(parts, key .. ':' .. value)
        end
        return '{' .. table.concat(parts, ',') .. '}'
      else
        return '"' .. tostring(obj) .. '"'
      end
    end,
    decode = function(str)
      -- Simple JSON decoding for testing - very basic implementation
      if str == '{"jsonrpc":"2.0","method":"initialize","id":1}' then
        return { jsonrpc = '2.0', method = 'initialize', id = 1 }
      elseif str == '{"jsonrpc":"2.0","id":1,"result":{"capabilities":{}}}' then
        return { jsonrpc = '2.0', id = 1, result = { capabilities = {} } }
      elseif str:match('"jsonrpc":"2.0"') then
        -- Basic pattern matching for test cases
        local obj = { jsonrpc = '2.0' }
        if str:match('"method":"([^"]+)"') then
          obj.method = str:match('"method":"([^"]+)"')
        end
        if str:match('"id":(%d+)') then
          obj.id = tonumber(str:match('"id":(%d+)'))
        end
        if str:match('"result":{') then
          obj.result = {}
        end
        return obj
      else
        error('JSON decode failed: ' .. str)
      end
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

-- Load the JSON-RPC module
local jsonrpc = require('container.lsp.proxy.jsonrpc')

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

-- Test Content-Length parsing
test('Content-Length parsing', function()
  local length = jsonrpc.parse_content_length('Content-Length: 123')
  assert(length == 123, 'Expected 123, got ' .. tostring(length))

  local invalid = jsonrpc.parse_content_length('Invalid header')
  assert(invalid == nil, 'Expected nil for invalid header')

  local zero = jsonrpc.parse_content_length('Content-Length: 0')
  assert(zero == 0, 'Expected 0 for zero length, got ' .. tostring(zero))
end)

-- Test message serialization
test('Message serialization', function()
  local message = {
    jsonrpc = '2.0',
    method = 'initialize',
    id = 1,
    params = {},
  }

  local serialized, err = jsonrpc.serialize_message(message)
  assert(serialized ~= nil, 'Serialization failed: ' .. tostring(err))
  assert(serialized:match('Content%-Length:'), 'Missing Content-Length header')
  assert(serialized:match('"jsonrpc":"2.0"'), 'Missing JSON content')
end)

-- Test message parsing
test('Message parsing', function()
  local json_body = '{"jsonrpc":"2.0","method":"initialize","id":1}'
  local content_length = #json_body
  local raw_message = 'Content-Length: ' .. content_length .. '\r\n\r\n' .. json_body
  local parsed, err = jsonrpc.parse_message(raw_message)

  assert(parsed ~= nil, 'Parsing failed: ' .. tostring(err))
  assert(parsed.jsonrpc == '2.0', 'Wrong JSON-RPC version')
  assert(parsed.method == 'initialize', 'Wrong method')
  assert(parsed.id == 1, 'Wrong ID')
end)

-- Test message type detection
test('Message type detection', function()
  local request = { jsonrpc = '2.0', method = 'test', id = 1 }
  assert(jsonrpc.get_message_type(request) == 'request', 'Wrong type for request')

  local notification = { jsonrpc = '2.0', method = 'test' }
  assert(jsonrpc.get_message_type(notification) == 'notification', 'Wrong type for notification')

  local response = { jsonrpc = '2.0', id = 1, result = {} }
  assert(jsonrpc.get_message_type(response) == 'response', 'Wrong type for response')

  local error_response = { jsonrpc = '2.0', id = 1, error = { code = -1, message = 'test' } }
  assert(jsonrpc.get_message_type(error_response) == 'error', 'Wrong type for error')
end)

-- Test message creation
test('Message creation', function()
  local request = jsonrpc.create_request(1, 'test', { param = 'value' })
  assert(request.jsonrpc == '2.0', 'Wrong JSON-RPC version in request')
  assert(request.method == 'test', 'Wrong method in request')
  assert(request.id == 1, 'Wrong ID in request')

  local notification = jsonrpc.create_notification('test', { param = 'value' })
  assert(notification.jsonrpc == '2.0', 'Wrong JSON-RPC version in notification')
  assert(notification.method == 'test', 'Wrong method in notification')
  assert(notification.id == nil, 'Notification should not have ID')

  local response = jsonrpc.create_response(1, { result = 'test' })
  assert(response.jsonrpc == '2.0', 'Wrong JSON-RPC version in response')
  assert(response.id == 1, 'Wrong ID in response')
  assert(response.result ~= nil, 'Missing result in response')
end)

-- Test message validation
test('Message validation', function()
  local valid_request = { jsonrpc = '2.0', method = 'test', id = 1 }
  local is_valid, err = jsonrpc.validate_message(valid_request)
  assert(is_valid, 'Valid request failed validation: ' .. tostring(err))

  local invalid_no_version = { method = 'test', id = 1 }
  local is_invalid, _ = jsonrpc.validate_message(invalid_no_version)
  assert(not is_invalid, 'Invalid message passed validation')

  local invalid_no_method = { jsonrpc = '2.0', id = 1 }
  local is_invalid2, _ = jsonrpc.validate_message(invalid_no_method)
  assert(not is_invalid2, 'Request without method passed validation')
end)

-- Test stream parsing
test('Stream parsing', function()
  local json_body = '{"jsonrpc":"2.0","method":"test","id":1}'
  local content_length = #json_body
  local stream = 'Content-Length: ' .. content_length .. '\r\n\r\n' .. json_body
  local messages, remaining = jsonrpc.parse_message_stream(stream)

  assert(#messages == 1, 'Expected 1 message, got ' .. #messages)
  assert(remaining == '', 'Expected empty remaining buffer, got: ' .. remaining)
  assert(messages[1].method == 'test', 'Wrong method in parsed message')
end)

-- Test batch serialization
test('Batch serialization', function()
  local messages = {
    { jsonrpc = '2.0', method = 'test1', id = 1 },
    { jsonrpc = '2.0', method = 'test2', id = 2 },
  }

  local batch, err = jsonrpc.serialize_batch(messages)
  assert(batch ~= nil, 'Batch serialization failed: ' .. tostring(err))
  assert(batch:match('test1'), 'Missing first message in batch')
  assert(batch:match('test2'), 'Missing second message in batch')
end)

-- Test error handling
test('Error handling', function()
  local invalid_message = 'not json'
  local parsed, err = jsonrpc.parse_message(invalid_message)
  assert(parsed == nil, 'Should fail to parse invalid message')
  assert(err ~= nil, 'Should return error for invalid message')

  local invalid_batch = nil
  local batch, batch_err = jsonrpc.serialize_batch(invalid_batch)
  assert(batch == nil, 'Should fail to serialize invalid batch')
  assert(batch_err ~= nil, 'Should return error for invalid batch')
end)

-- Performance test
test('Performance test', function()
  local start_time = os.clock()
  local iterations = 1000

  for i = 1, iterations do
    local message = jsonrpc.create_request(i, 'test', { data = 'test_data_' .. i })
    local serialized, _ = jsonrpc.serialize_message(message)
    local parsed, _ = jsonrpc.parse_message(serialized)
    assert(parsed.id == i, 'Performance test failed at iteration ' .. i)
  end

  local elapsed = (os.clock() - start_time) * 1000
  local avg_time = elapsed / iterations

  print(string.format('  Performance: %d iterations in %.2fms (%.4fms per operation)', iterations, elapsed, avg_time))

  assert(avg_time < 1, 'Performance too slow: ' .. avg_time .. 'ms per operation')
end)

-- Summary
print('=== Test Results ===')
print(string.format('Passed: %d/%d tests', passed_count, test_count))

if passed_count == test_count then
  print('✅ All JSON-RPC tests passed!')
  print('JSON-RPC module is ready for integration')
else
  print('❌ Some tests failed')
  print('JSON-RPC module needs fixes before integration')
  os.exit(1)
end

print()
print('Next: Test transport layer with test_transport.lua')
os.exit(0)
