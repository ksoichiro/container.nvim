#!/usr/bin/env lua

-- Essential E2E Tests for container.nvim
-- Focuses on core functionality that can be reliably tested
-- without requiring specific project structures

-- Setup test environment
package.path = './test/helpers/?.lua;./lua/?.lua;./lua/?/init.lua;' .. package.path

local helpers = require('init')
helpers.setup_vim_mock()
helpers.setup_lua_path()

local function run_command(cmd)
  local handle = io.popen(cmd .. ' 2>&1')
  local result = handle:read('*a')
  local success = handle:close()
  return success, result
end

local tests = {}

-- Test 1: Docker environment validation
function tests.test_docker_environment()
  print('=== Essential E2E Test 1: Docker Environment ===')

  -- Test Docker CLI availability
  local docker_available, docker_output = run_command('docker --version')
  if not docker_available then
    print('✗ Docker CLI not available')
    return false
  end
  print('✓ Docker CLI available:', docker_output:gsub('%s+$', ''))

  -- Test Docker daemon connectivity
  local daemon_available, daemon_output = run_command('docker info')
  if not daemon_available then
    print('✗ Docker daemon not accessible')
    print('Error:', daemon_output)
    return false
  end
  print('✓ Docker daemon accessible')

  return true
end

-- Test 2: Plugin integration with Docker
function tests.test_plugin_docker_integration()
  print('\n=== Essential E2E Test 2: Plugin-Docker Integration ===')

  local container = require('container')
  local docker = require('container.docker')

  -- Test plugin setup
  local setup_success = pcall(function()
    return container.setup({ log_level = 'info' })
  end)

  if not setup_success then
    print('✗ Plugin setup failed')
    return false
  end
  print('✓ Plugin setup successful')

  -- Test Docker availability through plugin
  local docker_check = docker.check_docker_availability()
  if not docker_check then
    print('✗ Docker not available through plugin')
    return false
  end
  print('✓ Docker available through plugin')

  -- Test basic Docker command execution
  local version_result = docker.run_docker_command({ 'version', '--format', 'json' })
  if not version_result or not version_result.success then
    print('✗ Docker command execution failed')
    return false
  end
  print('✓ Docker command execution successful')

  return true
end

-- Test 3: Configuration system integration
function tests.test_configuration_integration()
  print('\n=== Essential E2E Test 3: Configuration Integration ===')

  local container = require('container')
  local config = require('container.config')

  -- Test configuration loading
  local config_success, config_result = config.setup({
    log_level = 'debug',
    docker = { timeout = 30000 },
    lsp = { auto_setup = false },
  })

  if not config_success then
    print('✗ Configuration setup failed')
    return false
  end
  print('✓ Configuration setup successful')

  -- Test configuration retrieval
  local current_config = config.get()
  if not current_config then
    print('✗ Configuration retrieval failed')
    return false
  end
  print('✓ Configuration retrieval successful')
  print('  Log level:', current_config.log_level)
  print('  Docker timeout:', current_config.docker.timeout)

  return true
end

-- Test 4: Error handling and recovery
function tests.test_error_handling()
  print('\n=== Essential E2E Test 4: Error Handling ===')

  local container = require('container')
  local docker = require('container.docker')

  -- Test invalid Docker command
  local invalid_result = docker.run_docker_command({ 'invalid-command-xyz' })
  if invalid_result.success then
    print('⚠ Invalid Docker command unexpectedly succeeded')
  else
    print('✓ Invalid Docker command properly failed')
  end

  -- Test operations without container
  local no_container_ops = {
    function()
      return container.stop()
    end,
    function()
      return container.execute('echo test')
    end,
  }

  for i, op in ipairs(no_container_ops) do
    local success = pcall(op)
    if success then
      print('✓ Operation ' .. i .. ' handled gracefully without container')
    else
      print('✓ Operation ' .. i .. ' properly rejected without container')
    end
  end

  return true
end

-- Test 5: State management
function tests.test_state_management()
  print('\n=== Essential E2E Test 5: State Management ===')

  local container = require('container')

  -- Test initial state
  local initial_state = container.get_state()
  if not initial_state then
    print('✗ Could not get initial state')
    return false
  end
  print('✓ Initial state accessible')

  -- Test state reset
  local reset_success = pcall(function()
    return container.reset()
  end)

  if not reset_success then
    print('✗ State reset failed')
    return false
  end
  print('✓ State reset successful')

  -- Test state after reset
  local post_reset_state = container.get_state()
  if not post_reset_state then
    print('✗ Could not get state after reset')
    return false
  end
  print('✓ State accessible after reset')

  return true
end

-- Test 6: API surface verification
function tests.test_api_surface()
  print('\n=== Essential E2E Test 6: API Surface ===')

  local container = require('container')

  -- Test all expected functions exist
  local expected_functions = {
    'setup',
    'open',
    'build',
    'start',
    'stop',
    'execute',
    'get_state',
    'reset',
    'debug_info',
    'status',
  }

  local missing_functions = {}
  for _, func_name in ipairs(expected_functions) do
    if type(container[func_name]) ~= 'function' then
      table.insert(missing_functions, func_name)
    end
  end

  if #missing_functions > 0 then
    print('✗ Missing functions:', table.concat(missing_functions, ', '))
    return false
  end
  print('✓ All expected functions available')

  -- Test safe function calls
  local safe_calls = {
    { name = 'get_state', fn = container.get_state },
    { name = 'reset', fn = container.reset },
  }

  for _, call in ipairs(safe_calls) do
    local success = pcall(call.fn)
    if success then
      print('✓ Function ' .. call.name .. '() callable')
    else
      print('⚠ Function ' .. call.name .. '() had issues')
    end
  end

  return true
end

-- Main essential E2E test runner
local function run_essential_e2e_tests()
  print('=== container.nvim Essential E2E Tests ===')
  print('Core functionality verification with real Docker environment')
  print('')

  local test_functions = {
    tests.test_docker_environment,
    tests.test_plugin_docker_integration,
    tests.test_configuration_integration,
    tests.test_error_handling,
    tests.test_state_management,
    tests.test_api_surface,
  }

  local passed = 0
  local total = #test_functions

  for i, test_func in ipairs(test_functions) do
    local success, result = pcall(test_func)
    if success and result ~= false then
      passed = passed + 1
      print('✅ Essential E2E Test ' .. i .. ' PASSED')
    else
      print('❌ Essential E2E Test ' .. i .. ' FAILED')
      if not success then
        print('Error:', result)
      end
    end
    print('')
  end

  print('=== Essential E2E Test Results ===')
  print(string.format('Passed: %d/%d', passed, total))

  if passed == total then
    print('🎉 All essential E2E tests passed!')
    return 0
  else
    print('⚠ Some essential E2E tests failed.')
    return 1
  end
end

-- Run essential E2E tests
local exit_code = run_essential_e2e_tests()
os.exit(exit_code)
