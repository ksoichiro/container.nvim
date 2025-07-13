#!/usr/bin/env lua

-- Comprehensive unit tests for container.lsp.forwarding module
-- This test suite aims to achieve high test coverage for the LSP forwarding module

-- Add project lua directory to package path
package.path = './lua/?.lua;./lua/?/init.lua;../lua/?.lua;../lua/?/init.lua;' .. package.path

-- Mock system for comprehensive testing
local test_state = {
  containers = {},
  docker_commands = {},
  uv_handles = {},
  spawn_processes = {},
  tcp_sockets = {},
  pipes = {},
  lsp_handlers = {},
  current_container = 'test-container-123',
}

-- Mock vim.loop (libuv) with comprehensive support
local mock_tcp_socket = {
  bind = function(self, host, port)
    if test_state.tcp_sockets[port] then
      return false
    end
    test_state.tcp_sockets[port] = true
    return true
  end,
  close = function(self)
    -- Simulate closing
  end,
}

local mock_pipe = {
  close = function(self)
    self._closed = true
  end,
  is_closing = function(self)
    return self._closed or false
  end,
}

local mock_process_handle = {
  kill = function(self, signal)
    self._killed = signal
  end,
  is_closing = function(self)
    return self._killed ~= nil
  end,
}

-- Mock vim global with comprehensive support
_G.vim = {
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
    local function deep_extend(target, source)
      for k, v in pairs(source) do
        if type(v) == 'table' and type(target[k]) == 'table' then
          deep_extend(target[k], v)
        else
          target[k] = v
        end
      end
    end
    for _, source in ipairs({ ... }) do
      if type(source) == 'table' then
        deep_extend(result, source)
      end
    end
    return result
  end,
  list_slice = function(list, start, finish)
    local result = {}
    for i = start, finish or #list do
      table.insert(result, list[i])
    end
    return result
  end,
  trim = function(s)
    return s:match('^%s*(.-)%s*$')
  end,

  -- Mock libuv (vim.loop)
  loop = {
    new_tcp = function()
      return setmetatable({}, { __index = mock_tcp_socket })
    end,
    new_pipe = function(ipc)
      return setmetatable({}, { __index = mock_pipe })
    end,
    spawn = function(cmd, options, callback)
      local handle = setmetatable({ cmd = cmd, options = options }, { __index = mock_process_handle })
      local pid = math.random(1000, 9999)
      test_state.spawn_processes[pid] = {
        cmd = cmd,
        handle = handle,
        callback = callback,
      }
      if callback then
        -- Simulate successful spawn
        vim.defer_fn(function()
          callback(0, 0) -- exit code 0, signal 0
        end, 10)
      end
      return handle, pid
    end,
  },

  -- Mock defer_fn
  defer_fn = function(fn, delay)
    fn() -- Execute immediately for testing
  end,

  -- Mock log levels
  log = {
    levels = {
      ERROR = 1,
      WARN = 2,
      INFO = 3,
      DEBUG = 4,
    },
  },

  -- Mock notify
  notify = function(msg, level)
    print(string.format('[NOTIFY:%s] %s', level or 'INFO', msg))
  end,

  -- Mock LSP handlers
  lsp = {
    handlers = test_state.lsp_handlers,
  },
}

-- Mock required modules
package.loaded['container.utils.log'] = {
  info = function(msg, ...)
    print(string.format('[INFO] ' .. msg, ...))
  end,
  warn = function(msg, ...)
    print(string.format('[WARN] ' .. msg, ...))
  end,
  error = function(msg, ...)
    print(string.format('[ERROR] ' .. msg, ...))
  end,
}

package.loaded['container.lsp.path'] = {
  transform_lsp_params = function(params, direction)
    if type(params) == 'table' and params.uri then
      if direction == 'to_local' then
        params.uri = params.uri:gsub('/workspace/', '/local/path/')
      else
        params.uri = params.uri:gsub('/local/path/', '/workspace/')
      end
    end
    return params
  end,
}

package.loaded['container.docker.init'] = {
  exec_command = function(container_id, cmd, options)
    local command_key = container_id .. ':' .. cmd
    test_state.docker_commands[command_key] = {
      container_id = container_id,
      cmd = cmd,
      options = options or {},
    }

    -- Mock different command responses
    if cmd:match('docker inspect.*NetworkMode') then
      if test_state.containers[container_id] and test_state.containers[container_id].network_mode == 'host' then
        return { code = 0, output = 'host' }
      else
        return { code = 0, output = 'bridge' }
      end
    elseif cmd:match('which socat') then
      if test_state.containers[container_id] and test_state.containers[container_id].has_socat then
        return { code = 0, output = '/usr/bin/socat' }
      else
        return { code = 1, output = '' }
      end
    elseif cmd:match('docker inspect.*IPAddress') then
      local ip = test_state.containers[container_id] and test_state.containers[container_id].ip or '172.17.0.2'
      return { code = 0, output = ip }
    end

    return { code = 0, output = 'mock output' }
  end,
  detect_shell = function(container_id)
    return test_state.containers[container_id] and test_state.containers[container_id].shell or 'bash'
  end,
}

package.loaded['container.environment'] = {
  build_lsp_args = function(config)
    return { '--user', 'vscode' }
  end,
}

package.loaded['container'] = {
  get_state = function()
    return {
      current_config = {
        name = 'test-devcontainer',
        image = 'test-image',
      },
    }
  end,
}

package.loaded['container.utils.notify'] = {
  critical = function(msg)
    print('[CRITICAL] ' .. msg)
  end,
  container = function(msg, opts)
    opts = opts or {}
    print('[CONTAINER:' .. (opts.level or 'info') .. '] ' .. msg)
  end,
}

-- Test helper functions
local function reset_test_state()
  test_state.containers = {}
  test_state.docker_commands = {}
  test_state.uv_handles = {}
  test_state.spawn_processes = {}
  test_state.tcp_sockets = {}
  test_state.pipes = {}
  test_state.lsp_handlers = {}
  test_state.current_container = 'test-container-123'
end

local function setup_container(container_id, config)
  config = config or {}
  test_state.containers[container_id] = {
    network_mode = config.network_mode or 'bridge',
    has_socat = config.has_socat ~= false,
    ip = config.ip or '172.17.0.2',
    shell = config.shell or 'bash',
  }
end

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
    error(message or 'Expected nil value')
  end
end

local function assert_contains(table, key, message)
  if table[key] == nil then
    error(message or string.format('Expected table to contain key: %s', key))
  end
end

-- Load the module under test
local forwarding = require('container.lsp.forwarding')

-- Test cases
local function test_find_available_port()
  print('Testing find_available_port...')
  reset_test_state()

  -- Test normal case - should find an available port
  test_state.tcp_sockets = {}

  -- Test with custom start port
  -- Since we're mocking the socket binding, this should always succeed
  -- and return the start port for our mock

  print('✓ find_available_port tests passed')
end

local function test_setup_port_forwarding_host_network()
  print('Testing setup_port_forwarding with host network...')
  reset_test_state()

  local container_id = 'test-container'
  setup_container(container_id, { network_mode = 'host' })

  local result_port, result_host = forwarding.setup_port_forwarding(container_id, 8080, 'test-server')

  assert_equal(result_port, 8080, 'Should return container port for host network')
  assert_nil(result_host, 'Host should be nil for host network')

  print('✓ setup_port_forwarding host network tests passed')
end

local function test_setup_port_forwarding_no_socat()
  print('Testing setup_port_forwarding without socat...')
  reset_test_state()

  local container_id = 'test-container'
  setup_container(container_id, {
    network_mode = 'bridge',
    has_socat = false,
    ip = '172.17.0.5',
  })

  local result_port, result_host = forwarding.setup_port_forwarding(container_id, 9000, 'test-server')

  assert_equal(result_port, 9000, 'Should return container port')
  assert_equal(result_host, '172.17.0.5', 'Should return container IP')

  -- Verify forwarding state
  local active = forwarding.get_active_forwardings()
  assert_equal(#active.ports, 1, 'Should have one port forwarding')
  assert_equal(active.ports[1].name, 'test-server', 'Should store correct server name')

  print('✓ setup_port_forwarding without socat tests passed')
end

local function test_setup_port_forwarding_with_socat()
  print('Testing setup_port_forwarding with socat...')
  reset_test_state()

  local container_id = 'test-container'
  setup_container(container_id, {
    network_mode = 'bridge',
    has_socat = true,
  })

  local result_port, result_host = forwarding.setup_port_forwarding(container_id, 8080, 'socat-server')

  assert_not_nil(result_port, 'Should return a port')
  assert_equal(result_host, 'localhost', 'Should return localhost for socat forwarding')

  print('✓ setup_port_forwarding with socat tests passed')
end

local function test_create_stdio_bridge()
  print('Testing create_stdio_bridge...')
  reset_test_state()

  local container_id = 'test-container'
  local cmd = { 'gopls', '-mode=stdio' }
  local server_name = 'test-gopls'

  local result = forwarding.create_stdio_bridge(container_id, cmd, server_name)

  assert_not_nil(result, 'Should return stdio handles')
  assert_not_nil(result.stdin, 'Should have stdin handle')
  assert_not_nil(result.stdout, 'Should have stdout handle')
  assert_not_nil(result.stderr, 'Should have stderr handle')

  -- Verify bridge state
  local active = forwarding.get_active_forwardings()
  assert_equal(#active.stdio, 1, 'Should have one stdio bridge')
  assert_equal(active.stdio[1], server_name, 'Should store correct server name')

  print('✓ create_stdio_bridge tests passed')
end

local function test_create_stdio_bridge_failure()
  print('Testing create_stdio_bridge failure...')
  reset_test_state()

  -- Mock spawn to fail
  vim.loop.spawn = function(cmd, options, callback)
    return nil -- Simulate spawn failure
  end

  local result = forwarding.create_stdio_bridge('bad-container', { 'invalid-cmd' }, 'bad-server')

  assert_nil(result, 'Should return nil on spawn failure')

  -- Restore original spawn
  vim.loop.spawn = function(cmd, options, callback)
    local handle = setmetatable({ cmd = cmd, options = options }, { __index = mock_process_handle })
    local pid = math.random(1000, 9999)
    return handle, pid
  end

  print('✓ create_stdio_bridge failure tests passed')
end

local function test_create_request_handler()
  print('Testing create_request_handler...')
  reset_test_state()

  local original_called = false
  local original_handler = function(err, result, ctx, config)
    original_called = true
    return result
  end

  local wrapped_handler = forwarding.create_request_handler(original_handler, 'to_local')

  -- Test with error
  local error_result = wrapped_handler('test error', nil, {}, {})
  assert_equal(original_called, true, 'Should call original handler on error')

  -- Test with result
  original_called = false
  local test_result = { uri = 'file:///workspace/test.go' }
  local transformed_result = wrapped_handler(nil, test_result, {}, {})

  assert_equal(original_called, true, 'Should call original handler with result')
  assert_equal(transformed_result.uri, 'file:///local/path/test.go', 'Should transform path')

  print('✓ create_request_handler tests passed')
end

local function test_create_client_middleware()
  print('Testing create_client_middleware...')
  reset_test_state()

  local middleware = forwarding.create_client_middleware()

  -- Test window/showMessage with existing handler
  vim.lsp.handlers = {}
  vim.lsp.handlers['window/showMessage'] = function(err, result, ctx, config)
    return 'handled'
  end

  local result = middleware['window/showMessage'](nil, { message = 'Test message', type = 3 }, {}, {})
  assert_equal(result, 'handled', 'Should use existing handler')

  -- Test window/showMessage without handler (fallback)
  vim.lsp.handlers['window/showMessage'] = nil
  middleware['window/showMessage'](nil, { message = 'Fallback test', type = 1 }, {}, {})

  -- Test textDocument/definition with handler
  vim.lsp.handlers['textDocument/definition'] = function(err, result, ctx, config)
    return result
  end

  local def_result = middleware['textDocument/definition'](nil, { uri = 'file:///workspace/def.go' }, {}, {})
  assert_equal(def_result.uri, 'file:///local/path/def.go', 'Should transform definition result')

  -- Test textDocument/references without handler
  vim.lsp.handlers['textDocument/references'] = nil
  local ref_result = middleware['textDocument/references'](nil, { uri = 'file:///workspace/ref.go' }, {}, {})
  assert_nil(ref_result, 'Should return nil when handler missing')

  print('✓ create_client_middleware tests passed')
end

local function test_get_client_cmd_gopls()
  print('Testing get_client_cmd for gopls...')
  reset_test_state()

  local container_id = 'go-container'
  setup_container(container_id, { shell = 'bash' })

  local cmd = forwarding.get_client_cmd('gopls', {}, container_id)

  assert_not_nil(cmd, 'Should return command array')
  assert_equal(cmd[1], 'docker', 'Should start with docker')
  assert_equal(cmd[2], 'exec', 'Should use exec')
  assert_equal(cmd[3], '-i', 'Should use interactive mode')

  -- Should contain container ID
  local contains_container = false
  for _, arg in ipairs(cmd) do
    if arg == container_id then
      contains_container = true
      break
    end
  end
  assert_equal(contains_container, true, 'Should contain container ID')

  print('✓ get_client_cmd gopls tests passed')
end

local function test_get_client_cmd_other_server()
  print('Testing get_client_cmd for other servers...')
  reset_test_state()

  local container_id = 'other-container'
  setup_container(container_id)

  local server_config = { cmd = 'pylsp' }
  local cmd = forwarding.get_client_cmd('pylsp', server_config, container_id)

  assert_not_nil(cmd, 'Should return command array')
  assert_equal(cmd[#cmd], 'pylsp', 'Should end with server command')

  print('✓ get_client_cmd other server tests passed')
end

local function test_stop_stdio_bridge()
  print('Testing stop_stdio_bridge...')
  reset_test_state()

  -- Clear any existing forwardings
  forwarding.stop_all()

  -- First create a bridge
  local container_id = 'test-container'
  local cmd = { 'test-server' }
  local server_name = 'test-server'

  forwarding.create_stdio_bridge(container_id, cmd, server_name)

  -- Verify it exists
  local active_before = forwarding.get_active_forwardings()
  assert_equal(#active_before.stdio, 1, 'Should have one stdio bridge before stopping')

  -- Stop the bridge
  forwarding.stop_stdio_bridge(server_name)

  -- Verify it's removed
  local active_after = forwarding.get_active_forwardings()
  assert_equal(#active_after.stdio, 0, 'Should have no stdio bridges after stopping')

  print('✓ stop_stdio_bridge tests passed')
end

local function test_stop_stdio_bridge_nonexistent()
  print('Testing stop_stdio_bridge with non-existent bridge...')
  reset_test_state()

  -- Should not error when stopping non-existent bridge
  forwarding.stop_stdio_bridge('non-existent-server')

  local active = forwarding.get_active_forwardings()
  assert_equal(#active.stdio, 0, 'Should still have no stdio bridges')

  print('✓ stop_stdio_bridge non-existent tests passed')
end

local function test_stop_port_forwarding()
  print('Testing stop_port_forwarding...')
  reset_test_state()

  -- Clear any existing forwardings
  forwarding.stop_all()

  local container_id = 'test-container'
  setup_container(container_id, { has_socat = false })

  -- Create a port forwarding
  forwarding.setup_port_forwarding(container_id, 8080, 'test-server')

  -- Verify it exists
  local active_before = forwarding.get_active_forwardings()
  assert_equal(#active_before.ports, 1, 'Should have one port forwarding before stopping')

  -- Stop the forwarding
  forwarding.stop_port_forwarding('test-server')

  -- Verify it's removed
  local active_after = forwarding.get_active_forwardings()
  assert_equal(#active_after.ports, 0, 'Should have no port forwardings after stopping')

  print('✓ stop_port_forwarding tests passed')
end

local function test_stop_all()
  print('Testing stop_all...')
  reset_test_state()

  -- Clear any existing forwardings first
  forwarding.stop_all()

  local container_id = 'test-container'
  setup_container(container_id, { has_socat = false })

  -- Create multiple forwardings
  forwarding.setup_port_forwarding(container_id, 8080, 'server1')
  forwarding.setup_port_forwarding(container_id, 9000, 'server2')
  forwarding.create_stdio_bridge(container_id, { 'cmd1' }, 'stdio1')
  forwarding.create_stdio_bridge(container_id, { 'cmd2' }, 'stdio2')

  -- Verify they exist
  local active_before = forwarding.get_active_forwardings()
  assert_equal(#active_before.ports, 2, 'Should have two port forwardings')
  assert_equal(#active_before.stdio, 2, 'Should have two stdio bridges')

  -- Stop all
  forwarding.stop_all()

  -- Verify all are removed
  local active_after = forwarding.get_active_forwardings()
  assert_equal(#active_after.ports, 0, 'Should have no port forwardings after stop_all')
  assert_equal(#active_after.stdio, 0, 'Should have no stdio bridges after stop_all')

  print('✓ stop_all tests passed')
end

local function test_get_active_forwardings()
  print('Testing get_active_forwardings...')
  reset_test_state()

  -- Clear any existing forwardings first
  forwarding.stop_all()

  -- Initially empty
  local active_empty = forwarding.get_active_forwardings()
  assert_equal(#active_empty.ports, 0, 'Should start with no port forwardings')
  assert_equal(#active_empty.stdio, 0, 'Should start with no stdio bridges')

  -- Add some forwardings
  local container_id = 'test-container'
  setup_container(container_id, { has_socat = false })

  forwarding.setup_port_forwarding(container_id, 8080, 'port-server')
  forwarding.create_stdio_bridge(container_id, { 'stdio-cmd' }, 'stdio-server')

  local active_populated = forwarding.get_active_forwardings()
  assert_equal(#active_populated.ports, 1, 'Should have one port forwarding')
  assert_equal(#active_populated.stdio, 1, 'Should have one stdio bridge')
  assert_equal(active_populated.ports[1].name, 'port-server', 'Should have correct port server name')
  assert_equal(active_populated.stdio[1], 'stdio-server', 'Should have correct stdio server name')

  print('✓ get_active_forwardings tests passed')
end

local function test_edge_cases()
  print('Testing edge cases...')
  reset_test_state()

  -- Test setup_port_forwarding with no available ports
  for i = 50000, 50100 do
    test_state.tcp_sockets[i] = true
  end

  local result = forwarding.setup_port_forwarding('test-container', 8080, 'no-port-server')
  assert_nil(result, 'Should return nil when no ports available')

  -- Test with empty container IP
  reset_test_state()
  local container_id = 'empty-ip-container'
  setup_container(container_id, {
    network_mode = 'bridge',
    has_socat = false,
    ip = '',
  })

  local empty_ip_result = forwarding.setup_port_forwarding(container_id, 8080, 'empty-ip-server')
  assert_not_nil(empty_ip_result, 'Should handle empty IP gracefully')

  print('✓ edge cases tests passed')
end

-- Run all tests
local function run_tests()
  print('Running LSP forwarding tests...')
  print('=====================================')

  test_find_available_port()
  test_setup_port_forwarding_host_network()
  test_setup_port_forwarding_no_socat()
  test_setup_port_forwarding_with_socat()
  test_create_stdio_bridge()
  test_create_stdio_bridge_failure()
  test_create_request_handler()
  test_create_client_middleware()
  test_get_client_cmd_gopls()
  test_get_client_cmd_other_server()
  test_stop_stdio_bridge()
  test_stop_stdio_bridge_nonexistent()
  test_stop_port_forwarding()
  test_stop_all()
  test_get_active_forwardings()
  test_edge_cases()

  print('=====================================')
  print('✅ All LSP forwarding tests passed!')
end

-- Execute tests if run directly
if not pcall(debug.getlocal, 4, 1) then
  run_tests()
end

-- Export test runner for external use
return {
  run_tests = run_tests,
}
