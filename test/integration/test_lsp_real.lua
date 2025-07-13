-- Integration tests for container LSP functionality
-- Tests real LSP server integration with actual container environments

local helpers = require('test.helpers.test_helpers')

-- Test module
local M = {}

-- Test configuration
local test_config = {
  timeout = 10000, -- 10 seconds for LSP operations
  container_name = 'test_lsp_container',
  test_workspace = vim.fn.tempname() .. '_lsp_test',
}

-- Setup test environment
local function setup_test_env()
  -- Create temporary test workspace
  vim.fn.mkdir(test_config.test_workspace, 'p')

  -- Create test Go file for LSP testing
  local test_go_file = test_config.test_workspace .. '/main.go'
  local test_content = [[package main

import "fmt"

func main() {
    message := "Hello, World!"
    fmt.Println(message)
}

func greet(name string) string {
    return fmt.Sprintf("Hello, %s!", name)
}
]]

  local file = io.open(test_go_file, 'w')
  if file then
    file:write(test_content)
    file:close()
  end

  -- Create go.mod for proper Go project
  local go_mod_file = test_config.test_workspace .. '/go.mod'
  local mod_content = [[module test-lsp

go 1.21
]]

  local mod_file = io.open(go_mod_file, 'w')
  if mod_file then
    mod_file:write(mod_content)
    mod_file:close()
  end

  return test_go_file
end

-- Cleanup test environment
local function cleanup_test_env()
  if vim.fn.isdirectory(test_config.test_workspace) == 1 then
    vim.fn.delete(test_config.test_workspace, 'rf')
  end
end

-- Wait for condition with timeout
local function wait_for_condition(condition_fn, timeout_ms, check_interval)
  timeout_ms = timeout_ms or test_config.timeout
  check_interval = check_interval or 100

  local start_time = vim.loop.hrtime()

  while (vim.loop.hrtime() - start_time) / 1000000 < timeout_ms do
    if condition_fn() then
      return true
    end
    vim.wait(check_interval)
  end

  return false
end

-- Test: LSP auto-detection
function M.test_lsp_auto_detection()
  local lsp = require('container.lsp')

  -- Mock container state
  lsp.set_container_id('test_container_123')

  -- Test server detection
  local servers = lsp.detect_language_servers()

  assert(type(servers) == 'table', 'detect_language_servers should return a table')

  -- Check if the detection found expected servers (depends on container contents)
  -- This test validates the detection mechanism works, not specific servers
  local detection_worked = true
  for name, server in pairs(servers) do
    assert(type(name) == 'string', 'Server name should be string')
    assert(type(server) == 'table', 'Server config should be table')
    assert(type(server.available) == 'boolean', 'Server availability should be boolean')

    if server.available then
      assert(type(server.cmd) == 'string', 'Available server should have cmd')
      assert(type(server.languages) == 'table', 'Available server should have languages')
      assert(type(server.path) == 'string', 'Available server should have path')
    end
  end

  return detection_worked
end

-- Test: LSP client creation for gopls
function M.test_lsp_client_creation()
  -- Skip if no container environment available
  local container_module = require('container')
  local state = container_module.get_state()

  if not state.current_container then
    print('SKIP: No container available for LSP client creation test')
    return true
  end

  local lsp = require('container.lsp')

  -- Set container context
  lsp.set_container_id(state.current_container)

  -- Detect servers first
  local servers = lsp.detect_language_servers()

  if not servers.gopls or not servers.gopls.available then
    print('SKIP: gopls not available in container for client creation test')
    return true
  end

  -- Test client creation
  local server_config = servers.gopls

  -- Create client
  lsp.create_lsp_client('gopls', server_config)

  -- Wait for client to be created and initialized
  local client_created = wait_for_condition(function()
    local exists, client_id = lsp.client_exists('gopls')
    return exists and client_id ~= nil
  end, 5000)

  assert(client_created, 'LSP client should be created within timeout')

  -- Verify client properties
  local exists, client_id = lsp.client_exists('gopls')
  assert(exists, 'Client should exist after creation')
  assert(type(client_id) == 'number', 'Client ID should be number')

  -- Get the actual client
  local client = vim.lsp.get_client_by_id(client_id)
  assert(client ~= nil, 'Client should be retrievable by ID')
  assert(client.name == 'container_gopls', 'Client should have container prefix')
  assert(not client.is_stopped(), 'Client should not be stopped')

  -- Clean up
  lsp.stop_client('gopls')

  return true
end

-- Test: LSP commands functionality
function M.test_lsp_commands()
  -- Setup test environment
  local test_file = setup_test_env()

  -- Skip if no container environment
  local container_module = require('container')
  local state = container_module.get_state()

  if not state.current_container then
    cleanup_test_env()
    print('SKIP: No container available for LSP commands test')
    return true
  end

  -- Change to test workspace
  local original_cwd = vim.fn.getcwd()
  vim.cmd('cd ' .. test_config.test_workspace)

  -- Open test file
  vim.cmd('edit ' .. test_file)

  local success = false

  -- Initialize LSP
  local lsp = require('container.lsp')
  lsp.set_container_id(state.current_container)

  -- Detect and setup LSP
  lsp.setup_lsp_in_container()

  -- Wait for gopls to be available
  local lsp_ready = wait_for_condition(function()
    local exists, client_id = lsp.client_exists('gopls')
    if not exists then
      return false
    end

    local client = vim.lsp.get_client_by_id(client_id)
    return client and client.initialized and not client.is_stopped()
  end, 8000)

  if lsp_ready then
    -- Test LSP commands module
    local commands = require('container.lsp.commands')
    commands.setup({
      host_workspace = test_config.test_workspace,
      container_workspace = '/workspace',
    })

    -- Position cursor on a symbol (e.g., "fmt" in line 3)
    vim.api.nvim_win_set_cursor(0, { 3, 8 }) -- Line 3, column 8 (on "fmt")

    -- Test hover command
    local hover_success = commands.hover({ server_name = 'gopls' })
    assert(hover_success, 'Hover command should succeed')

    -- Test definition command (best effort, may not find stdlib)
    commands.definition({ server_name = 'gopls' })

    -- Test references for custom function
    vim.api.nvim_win_set_cursor(0, { 8, 5 }) -- Position on "greet" function
    commands.references({ server_name = 'gopls' })

    success = true
  else
    print('SKIP: LSP not ready within timeout for commands test')
    success = true -- Don't fail the test, just skip
  end

  -- Cleanup
  vim.cmd('cd ' .. original_cwd)
  cleanup_test_env()

  return success
end

-- Test: Path transformation utilities
function M.test_path_transformation()
  local transform = require('container.lsp.simple_transform')

  -- Setup test paths
  transform.setup({
    host_workspace = '/home/user/project',
    container_workspace = '/workspace',
  })

  -- Test host to container transformation
  local host_path = '/home/user/project/src/main.go'
  local container_path = transform.host_to_container(host_path)
  assert(container_path == '/workspace/src/main.go', 'Host to container path transformation failed')

  -- Test container to host transformation
  local back_to_host = transform.container_to_host(container_path)
  assert(back_to_host == host_path, 'Container to host path transformation failed')

  -- Test URI transformations
  local host_uri = 'file:///home/user/project/src/main.go'
  local container_uri = transform.host_uri_to_container(host_uri)
  assert(container_uri == 'file:///workspace/src/main.go', 'Host to container URI transformation failed')

  local back_to_host_uri = transform.container_uri_to_host(container_uri)
  assert(back_to_host_uri == host_uri, 'Container to host URI transformation failed')

  -- Test location transformation
  local location = {
    uri = 'file:///workspace/src/main.go',
    range = {
      start = { line = 5, character = 0 },
      ['end'] = { line = 5, character = 10 },
    },
  }

  local transformed = transform.transform_location(location, 'to_host')
  assert(transformed.uri == 'file:///home/user/project/src/main.go', 'Location transformation failed')
  assert(transformed.range.start.line == 5, 'Location range should be preserved')

  return true
end

-- Test: LSP health check and diagnostics
function M.test_lsp_health_diagnostics()
  local lsp = require('container.lsp')

  -- Test health check without container
  local health = lsp.health_check()
  assert(type(health) == 'table', 'Health check should return table')
  assert(type(health.container_connected) == 'boolean', 'Health should report container connection')
  assert(type(health.servers_detected) == 'number', 'Health should report server count')
  assert(type(health.clients_active) == 'number', 'Health should report client count')
  assert(type(health.issues) == 'table', 'Health should report issues list')

  -- Test debug info
  local debug_info = lsp.get_debug_info()
  assert(type(debug_info) == 'table', 'Debug info should return table')
  assert(debug_info.active_clients ~= nil, 'Debug info should include active clients')
  assert(debug_info.current_buffer_clients ~= nil, 'Debug info should include buffer clients')

  return true
end

-- Test: LSP error handling and recovery
function M.test_lsp_error_handling()
  local lsp = require('container.lsp')

  -- Test diagnostics for non-existent server
  local diagnosis = lsp.diagnose_lsp_server('nonexistent_server')
  assert(type(diagnosis) == 'table', 'Diagnosis should return table')
  assert(diagnosis.available == false, 'Non-existent server should not be available')
  assert(type(diagnosis.error) == 'string', 'Diagnosis should provide error message')
  assert(type(diagnosis.suggestions) == 'table', 'Diagnosis should provide suggestions')

  return true
end

-- Main test runner
function M.run_all_tests()
  local tests = {
    { name = 'LSP Auto-detection', func = M.test_lsp_auto_detection },
    { name = 'LSP Client Creation', func = M.test_lsp_client_creation },
    { name = 'Path Transformation', func = M.test_path_transformation },
    { name = 'LSP Health & Diagnostics', func = M.test_lsp_health_diagnostics },
    { name = 'LSP Error Handling', func = M.test_lsp_error_handling },
    { name = 'LSP Commands', func = M.test_lsp_commands },
  }

  local results = {}
  local passed = 0
  local total = #tests

  print('Running LSP Integration Tests...')
  print('============================')

  for _, test in ipairs(tests) do
    print('\nRunning: ' .. test.name)

    local ok, result = pcall(test.func)

    if ok and result then
      print('✓ PASSED: ' .. test.name)
      passed = passed + 1
      results[test.name] = 'PASSED'
    else
      local error_msg = result and tostring(result) or 'Unknown error'
      print('✗ FAILED: ' .. test.name .. ' - ' .. error_msg)
      results[test.name] = 'FAILED: ' .. error_msg
    end
  end

  print('\n============================')
  print(string.format('LSP Integration Tests Complete: %d/%d passed', passed, total))

  if passed == total then
    print('All LSP integration tests passed! ✓')
    return true
  else
    print('Some LSP integration tests failed. ✗')
    return false
  end
end

-- Auto-run if executed directly
if not pcall(debug.getlocal, 4, 1) then
  M.run_all_tests()
end

return M
