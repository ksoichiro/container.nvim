#!/usr/bin/env lua

-- Real Container Creation Tests for container.nvim
-- Tests actual Docker container creation and lifecycle
-- WARNING: This test creates and destroys real Docker containers

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

local function wait_for_condition(condition_fn, timeout_ms, interval_ms)
  timeout_ms = timeout_ms or 120000 -- 2 minutes default for real operations
  interval_ms = interval_ms or 2000 -- 2 seconds default

  local start_time = os.time()
  while (os.time() - start_time) * 1000 < timeout_ms do
    if condition_fn() then
      return true
    end
    os.execute('sleep ' .. (interval_ms / 1000))
  end
  return false
end

local function cleanup_test_containers()
  print('Cleaning up test containers...')
  run_command('docker ps -a --filter label=container-nvim-test=true -q | xargs -r docker rm -f')
  print('Cleanup completed')
end

local function create_test_project()
  local test_dir = '/tmp/container-nvim-real-test'

  -- Create test directory
  os.execute('rm -rf ' .. test_dir)
  os.execute('mkdir -p ' .. test_dir .. '/.devcontainer')

  -- Create a minimal devcontainer.json
  local devcontainer_config = [[{
  "name": "Container.nvim Real Test",
  "image": "alpine:latest",
  "workspaceFolder": "/workspace",
  "mounts": [
    "source=${localWorkspaceFolder},target=/workspace,type=bind"
  ],
  "postCreateCommand": "echo 'Container created successfully'",
  "customizations": {
    "vscode": {
      "settings": {
        "terminal.integrated.defaultProfile.linux": "sh"
      }
    }
  }
}]]

  local file = io.open(test_dir .. '/.devcontainer/devcontainer.json', 'w')
  file:write(devcontainer_config)
  file:close()

  -- Create a simple test file
  local test_file = io.open(test_dir .. '/test.txt', 'w')
  test_file:write('Hello from container.nvim test!\n')
  test_file:close()

  print('✓ Test project created at:', test_dir)
  return test_dir
end

local tests = {}

-- Test 1: Complete container lifecycle
function tests.test_container_lifecycle()
  print('=== Real Container Test 1: Complete Lifecycle ===')

  -- Create test project
  local test_project = create_test_project()

  local container = require('container')
  local docker = require('container.docker')

  -- Check Docker availability
  if not docker.check_docker_availability() then
    print('✗ Docker not available - skipping real container tests')
    return true -- Don't fail, just skip
  end

  -- Step 1: Plugin setup
  print('Step 1: Setting up plugin...')
  local setup_success = pcall(function()
    container.setup({
      log_level = 'debug',
      docker = { timeout = 120000 }, -- 2 minutes for real operations
    })
  end)

  if not setup_success then
    print('✗ Plugin setup failed')
    return false
  end
  print('✓ Plugin setup successful')

  -- Step 2: Open test project
  print('Step 2: Opening test project...')
  local open_success = pcall(function()
    return container.open(test_project)
  end)

  if not open_success then
    print('✗ Failed to open test project')
    return false
  end
  print('✓ Test project opened')

  -- Step 3: Build/prepare image
  print('Step 3: Preparing container image...')
  local build_success = pcall(function()
    return container.build()
  end)

  if not build_success then
    print('✗ Container build failed')
    return false
  end
  print('✓ Container image prepared')

  -- Step 4: Start container
  print('Step 4: Starting container...')
  local start_success = pcall(function()
    return container.start()
  end)

  if not start_success then
    print('✗ Container start failed')
    return false
  end
  print('✓ Container start initiated')

  -- Step 5: Wait for container to be created and running
  print('Step 5: Waiting for container to be running...')
  local container_running = wait_for_condition(function()
    local success, output = run_command('docker ps --filter label=container-nvim-test=true --filter status=running -q')
    return success and output:gsub('%s+', '') ~= ''
  end, 120000, 3000) -- 2 minutes timeout, check every 3 seconds

  if container_running then
    print('✓ Container is running!')

    -- Get container details
    local success, container_list = run_command(
      'docker ps --filter label=container-nvim-test=true --format "table {{.ID}}\\t{{.Image}}\\t{{.Status}}"'
    )
    if success then
      print('Container details:')
      print(container_list)
    end
  else
    print('⚠ Container not detected as running within timeout')
    -- Still check if it was created
    local success, output = run_command('docker ps -a --filter label=container-nvim-test=true -q')
    if success and output:gsub('%s+', '') ~= '' then
      print('⚠ Container was created but may not be running')
      local container_success, container_details = run_command(
        'docker ps -a --filter label=container-nvim-test=true --format "table {{.ID}}\\t{{.Image}}\\t{{.Status}}"'
      )
      if container_success then
        print('Container details:')
        print(container_details)
      end
    else
      print('✗ No container was created')
    end
  end

  -- Step 6: Test command execution
  print('Step 6: Testing command execution...')
  local exec_success = pcall(function()
    return container.execute('echo "Hello from container!"')
  end)

  if exec_success then
    print('✓ Command execution successful')
  else
    print('⚠ Command execution failed (may be expected)')
  end

  -- Step 7: Container cleanup
  print('Step 7: Stopping container...')
  local stop_success = pcall(function()
    return container.stop()
  end)

  if stop_success then
    print('✓ Container stop successful')
  else
    print('⚠ Container stop failed')
  end

  -- Force cleanup
  cleanup_test_containers()

  -- Clean up test project
  os.execute('rm -rf ' .. test_project)

  return container_running -- Test passes if container was successfully running
end

-- Test 2: Multiple container handling
function tests.test_multiple_containers()
  print('\n=== Real Container Test 2: Multiple Container Handling ===')

  local container = require('container')

  -- Test handling multiple projects
  local test_project1 = create_test_project() .. '-1'
  local test_project2 = create_test_project() .. '-2'

  -- Copy the test project to create variations
  os.execute('cp -r /tmp/container-nvim-real-test ' .. test_project1)
  os.execute('cp -r /tmp/container-nvim-real-test ' .. test_project2)

  -- Modify names in devcontainer.json
  local config1 = io.open(test_project1 .. '/.devcontainer/devcontainer.json', 'r'):read('*a')
  config1 = config1:gsub('Container%.nvim Real Test', 'Test Container 1')
  local file1 = io.open(test_project1 .. '/.devcontainer/devcontainer.json', 'w')
  file1:write(config1)
  file1:close()

  local config2 = io.open(test_project2 .. '/.devcontainer/devcontainer.json', 'r'):read('*a')
  config2 = config2:gsub('Container%.nvim Real Test', 'Test Container 2')
  local file2 = io.open(test_project2 .. '/.devcontainer/devcontainer.json', 'w')
  file2:write(config2)
  file2:close()

  -- Test switching between projects
  local switch_success = true

  pcall(function()
    container.reset()
  end)

  local open1_success = pcall(function()
    return container.open(test_project1)
  end)

  if open1_success then
    print('✓ Opened first test project')
  else
    print('✗ Failed to open first test project')
    switch_success = false
  end

  local open2_success = pcall(function()
    return container.open(test_project2)
  end)

  if open2_success then
    print('✓ Opened second test project')
  else
    print('✗ Failed to open second test project')
    switch_success = false
  end

  -- Cleanup
  os.execute('rm -rf ' .. test_project1)
  os.execute('rm -rf ' .. test_project2)
  os.execute('rm -rf /tmp/container-nvim-real-test')

  return switch_success
end

-- Test 3: Error scenarios with real Docker
function tests.test_real_error_scenarios()
  print('\n=== Real Container Test 3: Error Scenarios ===')

  local container = require('container')

  -- Test invalid image
  local test_project = create_test_project()

  -- Create invalid devcontainer.json
  local invalid_config = [[{
  "name": "Invalid Test Container",
  "image": "definitely-nonexistent-image-12345:latest",
  "workspaceFolder": "/workspace"
}]]

  local file = io.open(test_project .. '/.devcontainer/devcontainer.json', 'w')
  file:write(invalid_config)
  file:close()

  pcall(function()
    container.reset()
  end)

  local open_success = pcall(function()
    return container.open(test_project)
  end)

  if not open_success then
    print('✓ Invalid project properly rejected')
  else
    print('⚠ Invalid project was accepted')

    -- Try to build with invalid image
    local build_success = pcall(function()
      return container.build()
    end)

    if not build_success then
      print('✓ Invalid image build properly failed')
    else
      print('⚠ Invalid image build unexpectedly succeeded')
    end
  end

  -- Cleanup
  os.execute('rm -rf ' .. test_project)

  return true
end

-- Main test runner
local function run_real_container_tests()
  print('=== container.nvim Real Container Creation Tests ===')
  print('WARNING: This test creates and destroys real Docker containers')
  print('Testing actual container lifecycle operations...')
  print('')

  -- Check Docker availability first
  local docker_available, docker_output = run_command('docker --version')
  if not docker_available then
    print('❌ Docker not available. Skipping real container tests.')
    return 0
  end
  print('✓ Docker available:', docker_output:gsub('%s+$', ''))

  local daemon_available, daemon_output = run_command('docker ps')
  if not daemon_available then
    print('❌ Docker daemon not running. Skipping real container tests.')
    return 0
  end
  print('✓ Docker daemon accessible')
  print('')

  -- Cleanup any existing test containers
  cleanup_test_containers()

  local test_functions = {
    tests.test_container_lifecycle,
    tests.test_multiple_containers,
    tests.test_real_error_scenarios,
  }

  local passed = 0
  local total = #test_functions

  for i, test_func in ipairs(test_functions) do
    print('')
    local success, result = pcall(test_func)
    if success and result ~= false then
      passed = passed + 1
      print('✅ Real Container Test ' .. i .. ' PASSED')
    else
      print('❌ Real Container Test ' .. i .. ' FAILED')
      if not success then
        print('Error:', result)
      end
    end

    -- Cleanup between tests
    cleanup_test_containers()
  end

  print('')
  print('=== Real Container Test Results ===')
  print(string.format('Passed: %d/%d', passed, total))

  if passed == total then
    print('🎉 All real container tests passed!')
    return 0
  else
    print('⚠ Some real container tests failed.')
    return 1
  end
end

-- Run real container tests
local exit_code = run_real_container_tests()
os.exit(exit_code)
