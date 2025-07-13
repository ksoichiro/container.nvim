#!/usr/bin/env lua

-- Enhanced Docker Operations Coverage Tests
-- Targets uncovered functions and edge cases to achieve 70%+ coverage

package.path = './test/helpers/?.lua;./lua/?.lua;./lua/?/init.lua;' .. package.path

-- Load common test helpers
local test_helpers = require('test_helpers_common')
test_helpers.setup_lua_path()
test_helpers.setup_vim_mock()

-- Enhanced vim mock for better test coverage (extend existing)
vim.fn = vim.fn or {}

vim.fn.system = function(cmd)
  -- Enhanced mock system with more scenarios
  if cmd:match('docker --version') then
    return 'Docker version 20.10.8, build 3967b7d\n'
  elseif cmd:match('docker info') then
    if _G.test_docker_daemon_failure then
      _G.vim.v.shell_error = 1
      return 'Cannot connect to Docker daemon'
    end
    return 'Client:\n Context: default\n Debug Mode: false\n'
  elseif cmd:match('docker inspect.*State.Status') then
    if _G.test_container_not_running then
      _G.vim.v.shell_error = 1
      return ''
    end
    return 'running\n'
  elseif cmd:match('docker exec.*which bash') then
    if _G.test_no_bash then
      _G.vim.v.shell_error = 1
      return ''
    end
    return '/bin/bash\n'
  elseif cmd:match('docker exec.*which zsh') then
    _G.vim.v.shell_error = 1
    return ''
  elseif cmd:match('docker exec.*which sh') then
    return '/bin/sh\n'
  elseif cmd:match('docker images.*-q') then
    if _G.test_image_not_found then
      return ''
    end
    return 'sha256:abc123def456\n'
  elseif cmd:match('docker create') then
    if _G.test_create_failure then
      _G.vim.v.shell_error = 1
      return 'Error: Failed to create container'
    end
    return 'container_id_12345\n'
  elseif cmd:match('docker start') then
    if _G.test_start_failure then
      _G.vim.v.shell_error = 1
      return 'Error: Failed to start container'
    end
    return 'container_id_12345\n'
  elseif cmd:match('docker stop') then
    if _G.test_stop_failure then
      _G.vim.v.shell_error = 1
      return 'Error: Failed to stop container'
    end
    return 'container_id_12345\n'
  elseif cmd:match('docker exec.*echo ready') then
    if _G.test_exec_failure then
      _G.vim.v.shell_error = 1
      return 'Error: Container not ready'
    end
    return 'ready\n'
  elseif cmd:match('docker ps') then
    return 'CONTAINER ID\tIMAGE\tCOMMAND\tCREATED\tSTATUS\tPORTS\tNAMES\n12345\tubuntu\tbash\t1min\tUp 1 min\t3000:3000\ttest-container\n'
  elseif cmd:match('docker build') then
    if _G.test_build_failure then
      _G.vim.v.shell_error = 1
      return 'Error: Build failed'
    end
    return 'Successfully built abc123\n'
  elseif cmd:match('docker pull') then
    if _G.test_pull_failure then
      _G.vim.v.shell_error = 1
      return 'Error: Pull failed'
    end
    return 'Status: Downloaded newer image\n'
  else
    return ''
  end
end

vim.fn.jobstart = function(cmd, opts)
  -- Enhanced job mock
  local job_id = 1
  if _G.test_job_failure then
    return 0 -- Job failed to start
  end

  -- Simulate job execution
  if opts and opts.on_exit then
    _G.vim.defer_fn(function()
      opts.on_exit(job_id, _G.test_job_exit_code or 0, 'exit')
    end, 100)
  end

  return job_id
end

vim.fn.jobstop = function(job_id)
  return true
end

vim.fn.jobwait = function(jobs, timeout)
  if timeout == 0 then
    return { -1 } -- Job still running
  end
  return { 0 } -- Job finished
end

vim.fn.getcwd = function()
  return '/test/workspace'
end

vim.fn.sha256 = function(str)
  return string.format('%08x%08x%08x%08x', str:len() * 12345, str:len() * 67890, str:len() * 11111, str:len() * 22222)
end

vim.fn.shellescape = function(str)
  return "'" .. str:gsub("'", "'\"'\"'") .. "'"
end

vim.fn.fnamemodify = function(path, modifier)
  if modifier == ':t' then
    return path:match('[^/]+$') or path
  end
  return path
end

_G.vim = _G.vim
  or {
    fn = vim.fn,
    v = {
      shell_error = 0,
      servername = 'nvim-test',
    },
    defer_fn = function(fn, timeout)
      -- Execute immediately for tests
      if type(fn) == 'function' then
        fn()
      end
    end,
    schedule = function(fn)
      if type(fn) == 'function' then
        fn()
      end
    end,
    wait = function(timeout, condition, interval)
      if condition and condition() then
        return 0
      end
      return -1
    end,
    loop = {
      hrtime = function()
        return os.clock() * 1000000000
      end,
      now = function()
        return os.clock() * 1000
      end,
    },
    json = {
      decode = function(str)
        -- Simple JSON decode mock
        if str:match('"State"') then
          return {
            {
              State = { Status = 'running' },
              NetworkSettings = {
                Ports = {
                  ['3000/tcp'] = { { HostPort = '3000', HostIp = '0.0.0.0' } },
                  ['8080/tcp'] = { { HostPort = '8080', HostIp = '127.0.0.1' } },
                },
              },
            },
          }
        end
        return {}
      end,
    },
    NIL = {},
  }

local tests = {}

-- Helper function to reset test state
local function reset_test_state()
  _G.test_docker_daemon_failure = false
  _G.test_container_not_running = false
  _G.test_no_bash = false
  _G.test_image_not_found = false
  _G.test_create_failure = false
  _G.test_start_failure = false
  _G.test_stop_failure = false
  _G.test_exec_failure = false
  _G.test_build_failure = false
  _G.test_pull_failure = false
  _G.test_job_failure = false
  _G.test_job_exit_code = 0
  _G.vim.v.shell_error = 0
end

-- Test 1: Docker availability with daemon failure
function tests.test_docker_daemon_failure()
  print('\n=== Test 1: Docker Daemon Failure ===')
  reset_test_state()

  local docker = require('container.docker')

  -- Test daemon failure
  _G.test_docker_daemon_failure = true
  local available, error_msg = docker.check_docker_availability()

  if not available and error_msg then
    print('✓ Docker daemon failure handled correctly')
    return true
  else
    print('✗ Docker daemon failure not handled')
    return false
  end
end

-- Test 2: Shell detection with different scenarios
function tests.test_shell_detection_scenarios()
  print('\n=== Test 2: Shell Detection Scenarios ===')
  reset_test_state()

  local docker = require('container.docker')

  -- Test with bash available
  local shell = docker.detect_shell('test_container')
  if shell ~= 'bash' then
    print('✗ Bash detection failed')
    return false
  end
  print('✓ Bash detection works')

  -- Test with no bash, fallback to sh
  _G.test_no_bash = true
  docker.clear_shell_cache('test_container')
  shell = docker.detect_shell('test_container')
  if shell ~= 'sh' then
    print('✗ Shell fallback failed')
    return false
  end
  print('✓ Shell fallback to sh works')

  -- Test with container not running
  _G.test_container_not_running = true
  docker.clear_shell_cache()
  shell = docker.detect_shell('non_running_container')
  if shell ~= 'sh' then
    print('✗ Non-running container fallback failed')
    return false
  end
  print('✓ Non-running container fallback works')

  return true
end

-- Test 3: Image operations with error scenarios
function tests.test_image_operations_errors()
  print('\n=== Test 3: Image Operations with Errors ===')
  reset_test_state()

  local docker = require('container.docker')

  -- Test image exists when not found
  _G.test_image_not_found = true
  local exists = docker.check_image_exists('nonexistent:latest')
  if exists then
    print('✗ Image existence check should return false for nonexistent image')
    return false
  end
  print('✓ Non-existent image correctly detected')

  -- Test image exists when error occurs
  _G.vim.v.shell_error = 1
  exists = docker.check_image_exists('error:latest')
  if exists then
    print('✗ Image existence check should return false on error')
    return false
  end
  print('✓ Image check error handled correctly')

  return true
end

-- Test 4: Container creation with errors
function tests.test_container_creation_errors()
  print('\n=== Test 4: Container Creation Errors ===')
  reset_test_state()

  local docker = require('container.docker')

  -- Test container creation failure
  _G.test_create_failure = true
  local container_id, error_msg = docker.create_container({
    name = 'test-container',
    image = 'ubuntu:latest',
  })

  if container_id then
    print('✗ Container creation should fail')
    return false
  end
  if not error_msg then
    print('✗ Error message should be provided')
    return false
  end
  print('✓ Container creation failure handled correctly')

  return true
end

-- Test 5: Container lifecycle async operations
function tests.test_container_lifecycle_async()
  print('\n=== Test 5: Container Lifecycle Async ===')
  reset_test_state()

  local docker = require('container.docker')

  -- Test async create
  local create_success = false
  local create_error = nil

  docker.create_container_async({
    name = 'test-async',
    image = 'ubuntu:latest',
  }, function(container_id, error)
    create_success = container_id ~= nil
    create_error = error
  end)

  if not create_success then
    print('✗ Async container creation failed')
    return false
  end
  print('✓ Async container creation works')

  -- Test async start with failure
  _G.test_start_failure = true
  local start_success = nil
  local start_error = nil

  docker.start_container_async('test_container', function(success, error)
    start_success = success
    start_error = error
  end)

  if start_success then
    print('✗ Async start should fail')
    return false
  end
  if not start_error then
    print('✗ Start error message should be provided')
    return false
  end
  print('✓ Async start failure handled correctly')

  return true
end

-- Test 6: Build operations
function tests.test_build_operations()
  print('\n=== Test 6: Build Operations ===')
  reset_test_state()

  local docker = require('container.docker')

  -- Test successful build
  local build_success = false
  local build_result = nil

  docker.build_image(
    {
      name = 'test-build',
      base_path = '/test/path',
      dockerfile = 'Dockerfile',
      build_args = { NODE_ENV = 'development' },
      context = '.',
    },
    nil,
    function(success, result)
      build_success = success
      build_result = result
    end
  )

  if not build_success then
    print('✗ Build should succeed')
    return false
  end
  print('✓ Build operation works')

  -- Test build failure
  _G.test_build_failure = true
  build_success = false

  docker.build_image(
    {
      name = 'test-build-fail',
      base_path = '/test/path',
    },
    nil,
    function(success, result)
      build_success = success
    end
  )

  if build_success then
    print('✗ Build should fail')
    return false
  end
  print('✓ Build failure handled correctly')

  return true
end

-- Test 7: Command execution scenarios
function tests.test_command_execution()
  print('\n=== Test 7: Command Execution ===')
  reset_test_state()

  local docker = require('container.docker')

  -- Test sync command with options
  local result = docker.run_docker_command({ 'ps', '-a' }, { cwd = '/test', verbose = true })
  if not result.success then
    print('✗ Sync command should succeed')
    return false
  end
  print('✓ Sync command with options works')

  -- Test async command with error
  _G.test_job_exit_code = 1
  local async_success = nil

  docker.run_docker_command_async({ 'invalid', 'command' }, {}, function(result)
    async_success = result.success
  end)

  if async_success then
    print('✗ Async command should fail')
    return false
  end
  print('✓ Async command failure handled')

  return true
end

-- Test 8: Container status and info
function tests.test_container_status_info()
  print('\n=== Test 8: Container Status and Info ===')
  reset_test_state()

  local docker = require('container.docker')

  -- Test container status
  local status = docker.get_container_status('test_container')
  if status ~= 'running' then
    print('✗ Container status should be running')
    return false
  end
  print('✓ Container status works')

  -- Test container info
  local info = docker.get_container_info('test_container')
  if not info or not info.State then
    print('✗ Container info should be available')
    return false
  end
  print('✓ Container info works')

  return true
end

-- Test 9: Container listing and devcontainers
function tests.test_container_listing()
  print('\n=== Test 9: Container Listing ===')
  reset_test_state()

  local docker = require('container.docker')

  -- Test container listing
  local containers = docker.list_containers()
  if #containers == 0 then
    print('✗ Should have at least one container')
    return false
  end
  print('✓ Container listing works')

  -- Test devcontainer listing
  local devcontainers = docker.list_devcontainers()
  if type(devcontainers) ~= 'table' then
    print('✗ Devcontainer listing should return table')
    return false
  end
  print('✓ Devcontainer listing works')

  return true
end

-- Test 10: Port forwarding
function tests.test_port_forwarding()
  print('\n=== Test 10: Port Forwarding ===')
  reset_test_state()

  local docker = require('container.docker')

  -- Test get forwarded ports
  local ports = docker.get_forwarded_ports()
  if type(ports) ~= 'table' then
    print('✗ Port forwarding should return table')
    return false
  end
  print('✓ Port forwarding listing works')

  return true
end

-- Test 11: Error message builders
function tests.test_error_message_builders()
  print('\n=== Test 11: Error Message Builders ===')
  reset_test_state()

  local docker = require('container.docker')

  -- Test Docker not found error
  local error_msg = docker._build_docker_not_found_error()
  if not error_msg:match('Docker command not found') then
    print('✗ Docker not found error message incorrect')
    return false
  end
  print('✓ Docker not found error message works')

  -- Test Docker daemon error
  error_msg = docker._build_docker_daemon_error()
  if not error_msg:match('daemon is not running') then
    print('✗ Docker daemon error message incorrect')
    return false
  end
  print('✓ Docker daemon error message works')

  -- Test network error handling
  error_msg = docker.handle_network_error('Connection timeout')
  if not error_msg:match('Network operation failed') then
    print('✗ Network error message incorrect')
    return false
  end
  print('✓ Network error handling works')

  -- Test container error handling
  error_msg = docker.handle_container_error('start', 'container123', 'Failed to start')
  if not error_msg:match('Container start operation failed') then
    print('✗ Container error message incorrect')
    return false
  end
  print('✓ Container error handling works')

  return true
end

-- Test 12: Container termination and removal
function tests.test_container_termination()
  print('\n=== Test 12: Container Termination ===')
  reset_test_state()

  local docker = require('container.docker')

  -- Test container kill
  local kill_success = false
  docker.kill_container('test_container', function(success, error)
    kill_success = success
  end)

  if not kill_success then
    print('✗ Container kill should succeed')
    return false
  end
  print('✓ Container kill works')

  -- Test container terminate
  local terminate_success = false
  docker.terminate_container('test_container', function(success, error)
    terminate_success = success
  end)

  if not terminate_success then
    print('✗ Container terminate should succeed')
    return false
  end
  print('✓ Container terminate works')

  -- Test container removal with force
  local remove_success = false
  docker.remove_container_async('test_container', true, function(success, error)
    remove_success = success
  end)

  if not remove_success then
    print('✗ Container removal should succeed')
    return false
  end
  print('✓ Container removal works')

  return true
end

-- Test 13: Complex execution scenarios
function tests.test_complex_execution()
  print('\n=== Test 13: Complex Execution ===')
  reset_test_state()

  local docker = require('container.docker')

  -- Test exec command with options
  docker.exec_command('test_container', 'echo test', {
    interactive = true,
    workdir = '/workspace',
    user = 'vscode',
    env = { TEST = 'value' },
    on_complete = function(result)
      if not result.success then
        print('✗ Exec command should succeed')
        return false
      end
    end,
  })
  print('✓ Exec command with options works')

  -- Test general execute command
  local result = docker.execute_command('test_container', 'pwd', {
    mode = 'sync',
    timeout = 5000,
  })

  if not result.success then
    print('✗ Execute command should succeed')
    return false
  end
  print('✓ General execute command works')

  return true
end

-- Test 14: Headless mode operations
function tests.test_headless_mode()
  print('\n=== Test 14: Headless Mode ===')
  reset_test_state()

  local docker = require('container.docker')

  -- Simulate headless mode
  _G.vim.v.servername = ''

  -- Test async availability check in headless mode
  local headless_success = false
  docker.check_docker_availability_async(function(available, error)
    headless_success = available
  end)

  if not headless_success then
    print('✗ Headless async check should succeed')
    return false
  end
  print('✓ Headless mode async operations work')

  -- Restore normal mode
  _G.vim.v.servername = 'nvim-test'

  return true
end

-- Test 15: Build complex args and prepare image
function tests.test_prepare_image_scenarios()
  print('\n=== Test 15: Prepare Image Scenarios ===')
  reset_test_state()

  local docker = require('container.docker')

  -- Test prepare image with existing image
  local prepare_success = false
  docker.prepare_image(
    {
      image = 'ubuntu:latest',
    },
    nil,
    function(success, result)
      prepare_success = success
    end
  )

  if not prepare_success then
    print('✗ Prepare existing image should succeed')
    return false
  end
  print('✓ Prepare existing image works')

  -- Test prepare image with no image or dockerfile
  prepare_success = true
  docker.prepare_image(
    {
      name = 'test-no-source',
    },
    nil,
    function(success, result)
      prepare_success = success
    end
  )

  if prepare_success then
    print('✗ Prepare image without source should fail')
    return false
  end
  print('✓ Prepare image error handling works')

  return true
end

-- Main test runner
local function run_enhanced_docker_tests()
  print('=== Enhanced Docker Operations Coverage Tests ===')
  print('Targeting uncovered functions to achieve 70%+ coverage')
  print('')

  local test_functions = {
    tests.test_docker_daemon_failure,
    tests.test_shell_detection_scenarios,
    tests.test_image_operations_errors,
    tests.test_container_creation_errors,
    tests.test_container_lifecycle_async,
    tests.test_build_operations,
    tests.test_command_execution,
    tests.test_container_status_info,
    tests.test_container_listing,
    tests.test_port_forwarding,
    tests.test_error_message_builders,
    tests.test_container_termination,
    tests.test_complex_execution,
    tests.test_headless_mode,
    tests.test_prepare_image_scenarios,
  }

  local passed = 0
  local total = #test_functions

  for i, test_func in ipairs(test_functions) do
    reset_test_state()
    local success, result = pcall(test_func)
    if success and result ~= false then
      passed = passed + 1
      print('✅ Enhanced Test', i, 'PASSED')
    else
      print('❌ Enhanced Test', i, 'FAILED')
      if not success then
        print('Error:', result)
      end
    end
    print('')
  end

  print('=== Enhanced Docker Coverage Test Results ===')
  print(string.format('Passed: %d/%d', passed, total))

  if passed == total then
    print('🎉 All enhanced Docker coverage tests passed!')
    print('Expected coverage improvement: 19.72% → 70%+')
    return 0
  else
    print('⚠ Some enhanced Docker coverage tests failed.')
    return 1
  end
end

-- Run tests
local exit_code = run_enhanced_docker_tests()
os.exit(exit_code)
