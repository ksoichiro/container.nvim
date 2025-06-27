-- Test Script for Strategy C (Host-side Interception)
-- This script tests the new interception-based LSP strategy

local function setup_logging()
  -- Enable debug logging
  vim.env.CONTAINER_LOG_LEVEL = 'DEBUG'

  -- Clear previous log
  vim.fn.system('rm -f /tmp/container_debug.log')

  print("Strategy C Test: Debug logging enabled")
  print("Log file: /tmp/container_debug.log")
end

local function get_container_info()
  local container = require('container')
  local state = container.get_state()

  print("=== Container State ===")
  print("Current container:", state.current_container or "none")
  print("Container status:", state.container_status or "unknown")

  return state.current_container
end

local function test_strategy_selection()
  print("\n=== Strategy Selection Test ===")

  local strategy = require('container.lsp.strategy')
  strategy.setup()

  local container_id = get_container_info()
  if not container_id then
    print("ERROR: No container available for testing")
    return nil
  end

  local chosen_strategy, strategy_config = strategy.select_strategy('gopls', container_id, {})

  print("Selected strategy:", chosen_strategy)
  print("Strategy config:", vim.inspect(strategy_config))

  return chosen_strategy == 'intercept', container_id
end

local function test_interceptor_module()
  print("\n=== Interceptor Module Test ===")

  local interceptor = require('container.lsp.interceptor')

  -- Test path configuration
  interceptor.setup_path_config('test_container', '/Users/test/project')
  local config = interceptor.get_path_config()

  print("Path config:", vim.inspect(config))

  -- Test path transformation
  local test_params = {
    textDocument = {
      uri = 'file:///Users/test/project/main.go'
    }
  }

  local transformed = interceptor.transform_request_params('textDocument/didOpen', test_params, 'to_container')
  print("Original params:", vim.inspect(test_params))
  print("Transformed params:", vim.inspect(transformed))

  return transformed.textDocument.uri == 'file:///workspace/main.go'
end

local function test_intercept_strategy()
  print("\n=== Intercept Strategy Test ===")

  local intercept_strategy = require('container.lsp.strategies.intercept')
  local container_id = get_container_info()

  if not container_id then
    print("ERROR: No container available")
    return false
  end

  -- Test availability check
  local available, error_msg = intercept_strategy.is_available('gopls', container_id)
  print("Strategy available:", available)
  if not available then
    print("Error:", error_msg)
    return false
  end

  -- Test client creation
  local client_config, err = intercept_strategy.create_client('gopls', container_id, {
    root_dir = vim.fn.getcwd()
  }, {})

  if not client_config then
    print("ERROR: Failed to create client config:", err)
    return false
  end

  print("Client config created successfully")
  print("Client name:", client_config.name)
  print("Client cmd:", table.concat(client_config.cmd, ' '))
  print("Root dir:", client_config.root_dir)

  return true
end

local function test_full_integration()
  print("\n=== Full Integration Test ===")

  local container_id = get_container_info()
  if not container_id then
    print("ERROR: No container available")
    return false
  end

  -- Get current LSP clients
  local function get_lsp_clients()
    if vim.lsp.get_clients then
      return vim.lsp.get_clients()
    else
      return vim.lsp.get_active_clients()
    end
  end

  local initial_clients = get_lsp_clients()
  print("Initial LSP clients:", #initial_clients)

  -- Trigger LSP setup
  local lsp = require('container.lsp')
  print("Setting up container LSP...")

  -- Force setup for current buffer if it's a Go file
  local filetype = vim.bo.filetype
  if filetype == 'go' then
    print("Current buffer is Go file, triggering setup...")
    lsp.setup_container_lsp(container_id, { 'gopls' })
  else
    print("Current buffer is not Go file (", filetype, "), manual setup...")
    lsp.setup_container_lsp(container_id, { 'gopls' })
  end

  -- Wait a moment for client to initialize
  vim.defer_fn(function()
    local new_clients = get_lsp_clients()
    print("LSP clients after setup:", #new_clients)

    -- Find container_gopls client
    local container_client = nil
    for _, client in ipairs(new_clients) do
      if client.name == 'container_gopls' then
        container_client = client
        break
      end
    end

    if container_client then
      print("✅ container_gopls client found!")
      print("Client ID:", container_client.id)
      print("Client cmd:", vim.inspect(container_client.config.cmd))
      print("Client initialized:", container_client.initialized)

      -- Test if interception is set up
      if container_client.request ~= vim.lsp.start_client().request then
        print("✅ Request method appears to be intercepted")
      else
        print("❌ Request method does not appear to be intercepted")
      end
    else
      print("❌ container_gopls client not found")

      -- List all clients for debugging
      for i, client in ipairs(new_clients) do
        print(string.format("Client %d: %s (ID: %d)", i, client.name, client.id))
      end
    end
  end, 2000)

  return true
end

local function run_all_tests()
  setup_logging()

  print("=== Strategy C (Host-side Interception) Test Suite ===")
  print("Test file:", vim.fn.expand('%:p'))
  print("Working directory:", vim.fn.getcwd())
  print()

  local tests = {
    { "Container Info",     get_container_info },
    { "Strategy Selection", test_strategy_selection },
    { "Interceptor Module", test_interceptor_module },
    { "Intercept Strategy", test_intercept_strategy },
    { "Full Integration",   test_full_integration },
  }

  local results = {}

  for _, test in ipairs(tests) do
    local name, func = test[1], test[2]
    print(string.format("\n--- Running Test: %s ---", name))

    local success, result = pcall(func)
    if success then
      results[name] = result
      if result then
        print("✅ PASS:", name)
      else
        print("❌ FAIL:", name)
      end
    else
      results[name] = false
      print("❌ ERROR:", name, "-", result)
    end
  end

  print("\n=== Test Results Summary ===")
  for _, test in ipairs(tests) do
    local name = test[1]
    local status = results[name] and "✅ PASS" or "❌ FAIL"
    print(string.format("%-20s %s", name, status))
  end

  print("\nTo check detailed logs, run:")
  print("tail -f /tmp/container_debug.log")

  print("\nTo manually test LSP functionality:")
  print("1. Open a Go file")
  print("2. Try hover (K), definition jump (gd), completion")
  print("3. Check :LspInfo for client status")
end

-- Export functions for manual testing
_G.strategy_c_test = {
  run_all = run_all_tests,
  test_interceptor = test_interceptor_module,
  test_strategy = test_intercept_strategy,
  test_integration = test_full_integration,
  get_container = get_container_info,
}

-- Auto-run if script is executed directly
if debug.getinfo(2, "S") == nil then
  run_all_tests()
end

print("\n=== Manual Test Commands ===")
print(":lua strategy_c_test.run_all()")
print(":lua strategy_c_test.test_interceptor()")
print(":lua strategy_c_test.test_integration()")
print(":lua strategy_c_test.get_container()")
print(":ContainerDebug")
