#!/usr/bin/env lua

-- Real Container Integration Tests
-- Tests that actually create and verify Docker containers

package.path = './test/helpers/?.lua;./lua/?.lua;./lua/?/init.lua;' .. package.path

local helpers = require('init')
helpers.setup_vim_mock()
helpers.setup_lua_path()

-- Test utilities
local function run_command(cmd)
  local handle = io.popen(cmd .. ' 2>&1')
  local result = handle:read('*a')
  local success = handle:close()
  return success, result
end

local function wait_for_condition(condition_fn, timeout_ms, check_interval_ms)
  timeout_ms = timeout_ms or 120000 -- 2 minutes default for container operations
  check_interval_ms = check_interval_ms or 2000 -- 2 seconds default

  local start_time = os.time() * 1000
  while (os.time() * 1000 - start_time) < timeout_ms do
    if condition_fn() then
      return true
    end
    os.execute('sleep ' .. (check_interval_ms / 1000))
  end
  return false
end

local function cleanup_test_containers()
  print('Cleaning up test containers...')
  run_command('docker ps -a --filter name=container-nvim-test -q | xargs -r docker rm -f')
  run_command('docker ps -a --filter name=simple-test -q | xargs -r docker rm -f')
end

local function setup_test_project()
  -- Create a minimal test project with valid devcontainer.json
  local test_dir = '/tmp/container-nvim-test-project'
  os.execute('rm -rf ' .. test_dir)
  os.execute('mkdir -p ' .. test_dir .. '/.devcontainer')

  -- Create a simple devcontainer.json
  local devcontainer_content = [[{
  "name": "container-nvim-test",
  "image": "alpine:latest",
  "workspaceFolder": "/workspace",
  "postCreateCommand": "echo 'Container ready'",
  "mounts": [
    "source=${localWorkspaceFolder},target=/workspace,type=bind,consistency=cached"
  ]
}]]

  local file = io.open(test_dir .. '/.devcontainer/devcontainer.json', 'w')
  file:write(devcontainer_content)
  file:close()

  -- Create a simple test file
  local test_file = io.open(test_dir .. '/test.txt', 'w')
  test_file:write('This is a test file for container.nvim integration testing.\n')
  test_file:close()

  return test_dir
end

local tests = {}

-- Test 1: Real container lifecycle with verification
function tests.test_real_container_lifecycle()
  print('=== Real Container Lifecycle Test ===')

  -- Setup test environment
  local test_dir = setup_test_project()
  local original_cwd = io.popen('pwd'):read('*l')

  -- Change to test directory
  os.execute('cd ' .. test_dir)

  print('Test project created at:', test_dir)

  -- Initialize plugin
  local container = require('container')
  local success, error_msg

  -- Step 1: Setup and open
  print('Step 1: Setting up plugin and opening devcontainer...')
  success, error_msg = pcall(function()
    container.setup({
      log_level = 'debug',
      docker = { timeout = 120000 }, -- 2 minutes for real operations
    })
    return container.open(test_dir)
  end)

  if not success then
    print('✗ Setup/Open failed:', error_msg)
    return false
  end
  print('✓ Plugin setup and devcontainer open successful')

  -- Step 2: Build/prepare image
  print('Step 2: Preparing container image...')
  success, error_msg = pcall(function()
    return container.build()
  end)

  if not success then
    print('✗ Build failed:', error_msg)
    return false
  end
  print('✓ Container image preparation successful')

  -- Step 3: Start container
  print('Step 3: Starting container...')
  success, error_msg = pcall(function()
    return container.start()
  end)

  if not success then
    print('✗ Start failed:', error_msg)
    return false
  end
  print('✓ Container start initiated')

  -- Step 4: Wait for actual container creation and verify
  print('Step 4: Waiting for container creation...')
  local container_created = wait_for_condition(function()
    local cmd_success, output = run_command('docker ps -a --filter name=container-nvim-test --format "{{.Names}}"')
    if cmd_success and output:gsub('%s+', '') ~= '' then
      print('  Found container:', output:gsub('%s+', ''))
      return true
    end
    return false
  end, 180000, 5000) -- 3 minutes, check every 5 seconds

  if not container_created then
    print('✗ Container was not created within timeout')
    return false
  end
  print('✓ Container successfully created')

  -- Step 5: Verify container is running
  print('Step 5: Verifying container status...')
  local container_running = wait_for_condition(function()
    local cmd_success, output =
      run_command('docker ps --filter name=container-nvim-test --filter status=running --format "{{.Names}}"')
    return cmd_success and output:gsub('%s+', '') ~= ''
  end, 60000, 2000) -- 1 minute, check every 2 seconds

  if container_running then
    print('✓ Container is running')
  else
    print('⚠ Container created but not running - checking status...')
    local _, status_output =
      run_command('docker ps -a --filter name=container-nvim-test --format "{{.Names}} {{.Status}}"')
    print('  Container status:', status_output:gsub('%s+$', ''))
  end

  -- Step 6: Test command execution in container
  print('Step 6: Testing command execution...')
  local exec_success = false
  if container_running then
    exec_success, error_msg = pcall(function()
      local result, err = container.execute('echo "Hello from container"')
      if not result then
        error('Command execution failed: ' .. (err or 'unknown'))
      end
      return result
    end)

    if exec_success then
      print('✓ Command execution successful')
    else
      print('⚠ Command execution failed:', error_msg)
    end
  else
    print('⚠ Skipping command execution - container not running')
  end

  -- Step 7: Get container details for verification
  print('Step 7: Getting container details...')
  local _, container_details = run_command(
    'docker inspect --format "{{.Config.Image}} {{.Config.WorkingDir}} {{.State.Status}}" $(docker ps -aq --filter name=container-nvim-test)'
  )
  if container_details and container_details ~= '' then
    print('✓ Container details:', container_details:gsub('%s+$', ''))
  end

  -- Step 8: Test file access
  print('Step 8: Testing file access in container...')
  if container_running then
    local file_test_success, file_output =
      run_command('docker exec $(docker ps -q --filter name=container-nvim-test) ls -la /workspace/test.txt')
    if file_test_success and file_output:match('test.txt') then
      print('✓ Workspace files accessible in container')
    else
      print('⚠ Workspace files not accessible:', file_output)
    end
  end

  -- Step 9: Cleanup
  print('Step 9: Cleaning up...')
  pcall(function()
    container.stop()
  end)

  -- Force cleanup
  cleanup_test_containers()

  -- Return to original directory
  os.execute('cd ' .. original_cwd)
  os.execute('rm -rf ' .. test_dir)

  print('✓ Test cleanup completed')

  return container_created
end

-- Test 2: Container build verification
function tests.test_container_build_verification()
  print('\n=== Container Build Verification Test ===')

  -- Check if alpine image exists or needs pulling
  print('Step 1: Checking base image availability...')
  local image_exists, _ = run_command('docker images alpine:latest -q')
  if not image_exists or image_exists:gsub('%s+', '') == '' then
    print('Pulling alpine:latest for test...')
    local pull_success, pull_output = run_command('docker pull alpine:latest')
    if not pull_success then
      print('✗ Failed to pull alpine:latest:', pull_output)
      return false
    end
  end
  print('✓ Base image available')

  -- Test image preparation logic
  print('Step 2: Testing image preparation...')
  local docker = require('container.docker')

  local test_config = {
    name = 'simple-test',
    image = 'alpine:latest',
    workspace_folder = '/workspace',
  }

  local image_prepared = false
  docker.prepare_image(test_config, nil, function(success, result)
    if success then
      print('✓ Image preparation successful')
      image_prepared = true
    else
      print('✗ Image preparation failed:', result.stderr or 'unknown')
    end
  end)

  -- Wait for async operation
  local prep_success = wait_for_condition(function()
    return image_prepared
  end, 30000, 1000)

  return prep_success
end

-- Test 3: Real Docker command verification
function tests.test_docker_command_execution()
  print('\n=== Docker Command Execution Test ===')

  local docker = require('container.docker')

  -- Test 1: Docker availability
  print('Step 1: Testing Docker availability...')
  local docker_available, docker_error = docker.check_docker_availability()
  if not docker_available then
    print('✗ Docker not available:', docker_error)
    return false
  end
  print('✓ Docker is available')

  -- Test 2: Image existence check
  print('Step 2: Testing image existence check...')
  local image_exists = docker.check_image_exists('alpine:latest')
  if not image_exists then
    print('⚠ alpine:latest not found locally')
  else
    print('✓ alpine:latest exists locally')
  end

  -- Test 3: Container list
  print('Step 3: Testing container list...')
  local containers = docker.list_containers()
  if containers then
    print('✓ Container list successful, found', #containers, 'containers')
  else
    print('✗ Container list failed')
    return false
  end

  return true
end

-- Main test runner
local function run_integration_tests()
  print('=== Container.nvim Real Container Integration Tests ===')
  print('These tests create actual Docker containers for verification')
  print('')

  -- Prerequisites check
  local docker_available, docker_output = run_command('docker --version')
  if not docker_available then
    print('❌ Docker not available. Skipping integration tests.')
    return 0
  end
  print('✓ Docker available:', docker_output:gsub('%s+$', ''))

  local daemon_available, _ = run_command('docker ps')
  if not daemon_available then
    print('❌ Docker daemon not accessible. Skipping integration tests.')
    return 0
  end
  print('✓ Docker daemon accessible')

  -- Cleanup before starting
  cleanup_test_containers()

  local test_functions = {
    tests.test_docker_command_execution,
    tests.test_container_build_verification,
    tests.test_real_container_lifecycle,
  }

  local passed = 0
  local total = #test_functions

  for i, test_func in ipairs(test_functions) do
    print('')
    local success, result = pcall(test_func)
    if success and result ~= false then
      passed = passed + 1
      print('✅ Integration Test', i, 'PASSED')
    else
      print('❌ Integration Test', i, 'FAILED')
      if not success then
        print('Error:', result)
      end
    end
  end

  -- Final cleanup
  cleanup_test_containers()

  print('')
  print('=== Integration Test Results ===')
  print(string.format('Passed: %d/%d', passed, total))

  if passed == total then
    print('🎉 All integration tests passed!')
    return 0
  else
    print('⚠ Some integration tests failed.')
    return 1
  end
end

-- Run tests
local exit_code = run_integration_tests()
os.exit(exit_code)
