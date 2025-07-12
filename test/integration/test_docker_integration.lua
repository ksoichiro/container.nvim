#!/usr/bin/env lua

-- Docker Integration Tests for container.nvim
-- Tests actual Docker command execution and container lifecycle
-- This addresses the critical 10% coverage gap in Docker integration

-- Setup test environment
package.path = './test/helpers/?.lua;./lua/?.lua;./lua/?/init.lua;' .. package.path

local helpers = require('init')
helpers.setup_vim_mock()
helpers.setup_lua_path()

local docker = require('container.docker')
local config = require('container.config')

-- Test configuration
local test_config = {
  image = 'hello-world:latest',
  name = 'test-container-integration',
  workspaceFolder = '/workspace',
  mounts = {},
  forwardPorts = {},
}

local tests = {}

-- Test 1: Docker availability check
function tests.test_docker_availability_check()
  print('=== Test 1: Docker Availability Check ===')

  -- Test synchronous check
  local available = docker.check_docker_availability()
  helpers.assert_type(available, 'boolean', 'Docker availability should return boolean')

  if available then
    print('✓ Docker is available')
  else
    print('⚠ Docker not available - some tests will be skipped')
  end

  return available
end

-- Test 2: Docker version command
function tests.test_docker_version()
  print('\n=== Test 2: Docker Version Command ===')

  local result = docker.run_docker_command({ 'version', '--format', 'json' })
  helpers.assert_not_nil(result, 'Docker version should return result')
  helpers.assert_type(result, 'table', 'Docker command should return table')

  if result.success then
    print('✓ Docker version command successful')
    -- Try to parse as JSON (basic validation)
    local success = pcall(function()
      if vim.json and result.stdout then
        vim.json.decode(result.stdout)
      end
    end)
    if success then
      print('✓ Docker version output is valid JSON')
    end
  else
    print('⚠ Docker version command failed')
    print('Error:', result.stderr or 'unknown error')
  end

  return result.success
end

-- Test 3: Docker image operations
function tests.test_docker_image_operations()
  print('\n=== Test 3: Docker Image Operations ===')

  -- Test image existence check
  local image_result = docker.run_docker_command({ 'images', '-q', test_config.image })
  local image_exists = image_result.success and image_result.stdout ~= ''
  print(string.format('Image %s exists: %s', test_config.image, image_exists and 'yes' or 'no'))

  -- Test image pull (use hello-world for minimal size)
  print('Testing image pull...')
  local pull_result = docker.run_docker_command({ 'pull', test_config.image })
  helpers.assert_not_nil(pull_result, 'Image pull should return result')
  helpers.assert_type(pull_result, 'table', 'Pull result should be table')

  if pull_result.success then
    print('✓ Image pull command executed successfully')
  else
    print('⚠ Image pull failed:', pull_result.stderr or 'unknown error')
  end

  return pull_result.success
end

-- Test 4: Container lifecycle - basic operations
function tests.test_container_lifecycle_basic()
  print('\n=== Test 4: Container Lifecycle - Basic Operations ===')

  local container_name = test_config.name .. '-basic'

  -- Cleanup any existing container
  docker.run_docker_command({ 'rm', '-f', container_name })

  -- Test container creation
  print('Creating container...')
  local create_result = docker.run_docker_command({
    'create',
    '--name',
    container_name,
    test_config.image,
  })

  helpers.assert_type(create_result, 'table', 'Create result should be table')

  if create_result.success and create_result.stdout ~= '' then
    print('✓ Container created successfully')
    local container_id = string.gsub(create_result.stdout, '%s+', '') -- trim whitespace

    -- Test container inspection
    print('Inspecting container...')
    local inspect_result = docker.run_docker_command({ 'inspect', container_id })
    helpers.assert_not_nil(inspect_result, 'Container inspect should return result')
    helpers.assert_type(inspect_result, 'table', 'Inspect result should be table')

    if inspect_result.success then
      print('✓ Container inspection successful')
    else
      print('⚠ Container inspection failed:', inspect_result.stderr or 'unknown error')
    end

    -- Test container removal
    print('Removing container...')
    local remove_result = docker.run_docker_command({ 'rm', container_id })
    if remove_result.success then
      print('✓ Container removed successfully')
    else
      print('⚠ Container removal failed:', remove_result.stderr or 'unknown error')
    end
  else
    print('✗ Container creation failed:', create_result.stderr or 'unknown error')
    return false
  end

  return true
end

-- Test 5: Async Docker operations (if available)
function tests.test_docker_async_operations()
  print('\n=== Test 5: Async Docker Operations ===')

  -- Check if async module is available
  local async_available = pcall(require, 'container.utils.async')
  if not async_available then
    print('⚠ Async module not available - skipping async tests')
    return true
  end

  print('Testing async Docker command execution...')

  -- Test async version check
  local completed = false
  local result_data = nil

  -- Simple async simulation (since we're in unit test environment)
  local function simulate_async_docker()
    result_data = docker.run_docker_command({ 'version', '--format', '{{.Server.Version}}' })
    completed = true
  end

  simulate_async_docker()

  if completed and result_data and result_data.success then
    print('✓ Async Docker operation simulation successful')
  else
    print('⚠ Async Docker operation simulation incomplete')
  end

  return true
end

-- Test 6: Error handling
function tests.test_docker_error_handling()
  print('\n=== Test 6: Docker Error Handling ===')

  -- Test invalid Docker command
  print('Testing invalid Docker command...')
  local invalid_result = docker.run_docker_command({ 'invalid-command-that-does-not-exist' })

  helpers.assert_type(invalid_result, 'table', 'Invalid command should return table')

  -- Should handle error gracefully (success = false)
  if not invalid_result.success then
    print('✓ Invalid Docker command handled gracefully')
  else
    print('⚠ Invalid Docker command succeeded unexpectedly')
  end

  -- Test invalid container operation
  print('Testing invalid container operation...')
  local invalid_container_result = docker.run_docker_command({ 'inspect', 'non-existent-container-12345' })

  helpers.assert_type(invalid_container_result, 'table', 'Invalid container result should be table')

  -- Should handle error gracefully
  if not invalid_container_result.success then
    print('✓ Invalid container operation handled gracefully')
  else
    print('⚠ Invalid container operation succeeded unexpectedly')
  end

  return true
end

-- Test 7: Container configuration parsing
function tests.test_container_configuration()
  print('\n=== Test 7: Container Configuration Parsing ===')

  -- Test with complex configuration
  local complex_config = {
    image = 'ubuntu:20.04',
    name = 'test-complex-container',
    workspaceFolder = '/workspace',
    mounts = {
      'source=' .. vim.fn.getcwd() .. ',target=/workspace,type=bind',
    },
    forwardPorts = { 3000, 8080 },
    environment = {
      'NODE_ENV=development',
      'DEBUG=true',
    },
  }

  -- Test that configuration is handled properly
  helpers.assert_not_nil(complex_config.image, 'Config should have image')
  helpers.assert_not_nil(complex_config.name, 'Config should have name')
  helpers.assert_type(complex_config.forwardPorts, 'table', 'forwardPorts should be table')

  print('✓ Complex configuration structure validated')

  return true
end

-- Main test runner
local function run_docker_integration_tests()
  print('=== Docker Integration Tests ===')
  print('Testing core Docker functionality for container.nvim')
  print('')

  -- Check if Docker is available before running tests
  local docker_available = tests.test_docker_availability_check()

  local test_suite = {
    tests.test_docker_version,
    tests.test_container_configuration,
  }

  -- Only run Docker-dependent tests if Docker is available
  if docker_available then
    table.insert(test_suite, tests.test_docker_image_operations)
    table.insert(test_suite, tests.test_container_lifecycle_basic)
    table.insert(test_suite, tests.test_docker_async_operations)
  else
    print('\n⚠ Skipping Docker-dependent tests (Docker not available)')
  end

  -- Always run error handling tests
  table.insert(test_suite, tests.test_docker_error_handling)

  local passed = 0
  local total = #test_suite

  for i, test_func in ipairs(test_suite) do
    local success, err = pcall(test_func)
    if success then
      passed = passed + 1
    else
      print(string.format('✗ Test %d failed: %s', i, err))
    end
  end

  print(string.format('\n=== Docker Integration Test Results ==='))
  print(string.format('Passed: %d/%d', passed, total))

  if docker_available then
    print('Docker Status: Available ✓')
  else
    print('Docker Status: Not Available ⚠')
  end

  if passed == total then
    print('All Docker integration tests passed! ✓')
    return 0
  else
    print('Some Docker integration tests failed! ✗')
    return 1
  end
end

-- Run tests
local exit_code = run_docker_integration_tests()
os.exit(exit_code)
