#!/usr/bin/env lua

-- Comprehensive Docker Coverage Tests for init.lua
-- Targeting specific uncovered functions to achieve 70%+ coverage

package.path = './test/helpers/?.lua;./lua/?.lua;./lua/?/init.lua;' .. package.path

local helpers = require('init')
helpers.setup_vim_mock()
helpers.setup_lua_path()

-- Mock vim.fn system calls for more reliable testing
local function mock_vim_system()
  -- Store original functions
  local orig_system = vim.fn.system
  local orig_jobstart = vim.fn.jobstart
  local orig_jobwait = vim.fn.jobwait
  local orig_jobstop = vim.fn.jobstop
  local orig_sha256 = vim.fn.sha256
  local orig_getcwd = vim.fn.getcwd
  local orig_shellescape = vim.fn.shellescape

  -- Mock sha256 for container name generation
  vim.fn.sha256 = function(str)
    -- Simple hash mock - just use first 8 chars of the string
    local hash = ''
    for i = 1, math.min(8, #str) do
      hash = hash .. string.format('%02x', string.byte(str, i))
    end
    return hash .. string.rep('0', 64 - #hash) -- Pad to 64 chars
  end

  -- Mock getcwd
  vim.fn.getcwd = function()
    return '/test/workspace'
  end

  -- Mock shellescape
  vim.fn.shellescape = function(str)
    return "'" .. str:gsub("'", "'\"'\"'") .. "'"
  end

  -- Mock system with realistic Docker responses
  vim.fn.system = function(cmd)
    if not cmd then
      return ''
    end

    -- Docker availability checks
    if cmd:match('docker %-%-version') then
      vim.v.shell_error = 0
      return 'Docker version 20.10.17'
    elseif cmd:match('docker info') then
      vim.v.shell_error = 0
      return 'Docker info output'

    -- Shell detection
    elseif cmd:match('docker inspect %-f "{{%.State%.Status}}"') then
      vim.v.shell_error = 0
      return 'running'
    elseif cmd:match('docker exec .* which bash') then
      vim.v.shell_error = 0
      return '/bin/bash'
    elseif cmd:match('docker exec .* which zsh') then
      vim.v.shell_error = 1
      return ''
    elseif cmd:match('docker exec .* which sh') then
      vim.v.shell_error = 0
      return '/bin/sh'

    -- Image operations
    elseif cmd:match('docker images %-q') then
      vim.v.shell_error = 0
      return 'sha256:123456'

    -- Container status
    elseif cmd:match('docker inspect .* %-%-format') then
      vim.v.shell_error = 0
      return 'running'

    -- Container info
    elseif cmd:match('docker inspect [^%-]') then
      vim.v.shell_error = 0
      return '[{"State":{"Status":"running"},"NetworkSettings":{"Ports":{"3000/tcp":[{"HostPort":"3000","HostIp":"0.0.0.0"}]}}}]'

    -- Container listing
    elseif cmd:match('docker ps') then
      vim.v.shell_error = 0
      return 'container123\ttest-container-devcontainer\tUp 5 minutes\tubuntu:latest'

    -- Container operations
    elseif cmd:match('docker create') then
      vim.v.shell_error = 0
      return 'container123456'
    elseif cmd:match('docker start') then
      vim.v.shell_error = 0
      return 'container123456'
    elseif cmd:match('docker stop') then
      vim.v.shell_error = 0
      return 'container123456'
    elseif cmd:match('docker rm') then
      vim.v.shell_error = 0
      return 'container123456'
    elseif cmd:match('docker exec .* echo ready') then
      vim.v.shell_error = 0
      return 'ready'

    -- Default success
    else
      vim.v.shell_error = 0
      return ''
    end
  end

  -- Mock jobstart for async operations
  vim.fn.jobstart = function(cmd, opts)
    if not cmd or not opts then
      return -1
    end

    -- Simulate successful job start
    local job_id = math.random(1000, 9999)

    -- Simulate callbacks after a short delay
    vim.defer_fn(function()
      if opts.on_stdout then
        opts.on_stdout(job_id, { 'Job output line 1', 'Job output line 2' }, 'stdout')
      end
      if opts.on_exit then
        opts.on_exit(job_id, 0, 'exit')
      end
    end, 10)

    return job_id
  end

  -- Mock jobwait
  vim.fn.jobwait = function(jobs, timeout)
    if not jobs then
      return {}
    end
    local results = {}
    for _, job in ipairs(jobs) do
      table.insert(results, 0) -- Success
    end
    return results
  end

  -- Mock jobstop
  vim.fn.jobstop = function(job_id)
    return 1
  end

  return {
    system = orig_system,
    jobstart = orig_jobstart,
    jobwait = orig_jobwait,
    jobstop = orig_jobstop,
    sha256 = orig_sha256,
    getcwd = orig_getcwd,
    shellescape = orig_shellescape,
  }
end

-- Restore original vim functions
local function restore_vim_system(orig_funcs)
  vim.fn.system = orig_funcs.system
  vim.fn.jobstart = orig_funcs.jobstart
  vim.fn.jobwait = orig_funcs.jobwait
  vim.fn.jobstop = orig_funcs.jobstop
  vim.fn.sha256 = orig_funcs.sha256
  vim.fn.getcwd = orig_funcs.getcwd
  vim.fn.shellescape = orig_funcs.shellescape
end

local tests = {}

-- Test 1: Comprehensive Docker Availability Checks
function tests.test_docker_availability_comprehensive()
  print('=== Comprehensive Docker Availability Tests ===')

  local orig_funcs = mock_vim_system()
  local docker = require('container.docker')

  -- Test sync availability check
  local available = docker.check_docker_availability()
  if available then
    print('✓ Docker availability check (sync) passed')
  else
    print('✗ Docker availability check (sync) failed')
    restore_vim_system(orig_funcs)
    return false
  end

  -- Test async availability check
  local async_completed = false
  local async_result = false

  docker.check_docker_availability_async(function(success, error_msg)
    async_completed = true
    async_result = success
    if not success then
      print('Async error:', error_msg)
    end
  end)

  -- Wait for async completion
  local wait_count = 0
  while not async_completed and wait_count < 100 do
    vim.wait(10)
    wait_count = wait_count + 1
  end

  if async_result then
    print('✓ Docker availability check (async) passed')
  else
    print('✗ Docker availability check (async) failed')
    restore_vim_system(orig_funcs)
    return false
  end

  -- Test Docker not found scenario
  vim.fn.system = function(cmd)
    if cmd:match('docker %-%-version') then
      vim.v.shell_error = 127
      return 'command not found'
    end
    return ''
  end

  local not_found, error_msg = docker.check_docker_availability()
  if not not_found and error_msg and error_msg:match('Docker command not found') then
    print('✓ Docker not found scenario handled correctly')
  else
    print('✗ Docker not found scenario failed')
    restore_vim_system(orig_funcs)
    return false
  end

  -- Test Docker daemon not running
  vim.fn.system = function(cmd)
    if cmd:match('docker %-%-version') then
      vim.v.shell_error = 0
      return 'Docker version 20.10.17'
    elseif cmd:match('docker info') then
      vim.v.shell_error = 1
      return 'Cannot connect to Docker daemon'
    end
    return ''
  end

  local daemon_failed, daemon_error = docker.check_docker_availability()
  if not daemon_failed and daemon_error and daemon_error:match('daemon is not running') then
    print('✓ Docker daemon failure handled correctly')
  else
    print('✗ Docker daemon failure handling failed')
    restore_vim_system(orig_funcs)
    return false
  end

  restore_vim_system(orig_funcs)
  return true
end

-- Test 2: Shell Detection and Caching
function tests.test_shell_detection_comprehensive()
  print('\n=== Comprehensive Shell Detection Tests ===')

  local orig_funcs = mock_vim_system()
  local docker = require('container.docker')

  local container_id = 'test-container-123'

  -- Test bash detection
  local shell = docker.detect_shell(container_id)
  if shell == 'bash' then
    print('✓ Bash shell detected correctly')
  else
    print('✗ Shell detection failed, got:', shell)
    restore_vim_system(orig_funcs)
    return false
  end

  -- Test shell caching (should return cached result)
  local cached_shell = docker.detect_shell(container_id)
  if cached_shell == 'bash' then
    print('✓ Shell cache working correctly')
  else
    print('✗ Shell cache failed')
    restore_vim_system(orig_funcs)
    return false
  end

  -- Test cache clearing for specific container
  docker.clear_shell_cache(container_id)
  print('✓ Shell cache cleared for specific container')

  -- Test cache clearing for all containers
  docker.clear_shell_cache()
  print('✓ All shell cache cleared')

  -- Test fallback to sh when container not running
  vim.fn.system = function(cmd)
    if cmd:match('docker inspect %-f "{{%.State%.Status}}"') then
      vim.v.shell_error = 1
      return 'container not found'
    end
    return ''
  end

  local fallback_shell = docker.detect_shell('non-running-container')
  if fallback_shell == 'sh' then
    print('✓ Fallback shell for non-running container works')
  else
    print('✗ Fallback shell failed, got:', fallback_shell)
    restore_vim_system(orig_funcs)
    return false
  end

  restore_vim_system(orig_funcs)
  return true
end

-- Test 3: Container Name Generation Edge Cases
function tests.test_container_name_generation_edge_cases()
  print('\n=== Container Name Generation Edge Cases ===')

  local orig_funcs = mock_vim_system()
  local docker = require('container.docker')

  -- Test various config scenarios
  local test_configs = {
    {
      name = 'Simple Project',
      base_path = '/home/user/project',
    },
    {
      name = 'Project with Spaces and (Special) [Characters]',
      base_path = '/path/with spaces/project',
    },
    {
      name = 'project_with_underscores',
      base_path = '/path/project',
    },
    {
      name = 'Project-with-Dashes',
      base_path = '/another/path',
    },
    {
      name = 'UPPERCASE PROJECT',
      base_path = '/uppercase/path',
    },
  }

  for i, config in ipairs(test_configs) do
    local container_name = docker.generate_container_name(config)

    -- Check format
    if container_name:match('^[a-z0-9_.-]+%-[a-f0-9]+%-devcontainer$') then
      print('✓ Config', i, 'name generation valid:', container_name)
    else
      print('✗ Config', i, 'name generation invalid:', container_name)
      restore_vim_system(orig_funcs)
      return false
    end
  end

  -- Test consistency
  local config = { name = 'test-project', base_path = '/consistent/path' }
  local name1 = docker.generate_container_name(config)
  local name2 = docker.generate_container_name(config)

  if name1 == name2 then
    print('✓ Container name generation is consistent')
  else
    print('✗ Container name generation inconsistent')
    restore_vim_system(orig_funcs)
    return false
  end

  -- Test different projects generate different names
  local config_a = { name = 'same-name', base_path = '/path/a' }
  local config_b = { name = 'same-name', base_path = '/path/b' }

  local name_a = docker.generate_container_name(config_a)
  local name_b = docker.generate_container_name(config_b)

  if name_a ~= name_b then
    print('✓ Different projects generate different names')
  else
    print('✗ Different projects generate same names')
    restore_vim_system(orig_funcs)
    return false
  end

  restore_vim_system(orig_funcs)
  return true
end

-- Test 4: Image Operations Comprehensive
function tests.test_image_operations_comprehensive()
  print('\n=== Comprehensive Image Operations Tests ===')

  local orig_funcs = mock_vim_system()
  local docker = require('container.docker')

  -- Test image exists check
  local exists = docker.check_image_exists('ubuntu:latest')
  if exists then
    print('✓ Image existence check works')
  else
    print('✗ Image existence check failed')
    restore_vim_system(orig_funcs)
    return false
  end

  -- Test non-existent image
  vim.fn.system = function(cmd)
    if cmd:match('docker images %-q nonexistent') then
      vim.v.shell_error = 0
      return '' -- Empty result means image doesn't exist
    end
    return orig_funcs.system(cmd)
  end

  local not_exists = docker.check_image_exists('nonexistent:image')
  if not not_exists then
    print('✓ Non-existent image correctly detected')
  else
    print('✗ Non-existent image detection failed')
    restore_vim_system(orig_funcs)
    return false
  end

  -- Test image check error handling
  vim.fn.system = function(cmd)
    if cmd:match('docker images %-q error%-image') then
      vim.v.shell_error = 1
      return 'error output'
    end
    return orig_funcs.system(cmd)
  end

  local error_result = docker.check_image_exists('error-image:tag')
  if not error_result then
    print('✓ Image check error handled correctly')
  else
    print('✗ Image check error handling failed')
    restore_vim_system(orig_funcs)
    return false
  end

  -- Test async image check
  local async_completed = false
  local async_exists = false

  restore_vim_system(orig_funcs)
  orig_funcs = mock_vim_system() -- Reset to working state

  docker.check_image_exists_async('ubuntu:latest', function(exists, image_id)
    async_completed = true
    async_exists = exists
  end)

  -- Wait for completion
  local wait_count = 0
  while not async_completed and wait_count < 100 do
    vim.wait(10)
    wait_count = wait_count + 1
  end

  if async_exists then
    print('✓ Async image existence check works')
  else
    print('✗ Async image existence check failed')
    restore_vim_system(orig_funcs)
    return false
  end

  restore_vim_system(orig_funcs)
  return true
end

-- Test 5: Container Creation and Arguments Building
function tests.test_container_creation_comprehensive()
  print('\n=== Comprehensive Container Creation Tests ===')

  local orig_funcs = mock_vim_system()
  local docker = require('container.docker')

  -- Test comprehensive container configuration
  local test_config = {
    name = 'test-container',
    base_path = '/test/project',
    image = 'ubuntu:latest',
    workspace_folder = '/workspace',
    workspace_source = '/host/workspace',
    workspace_mount = '/container/workspace',
    environment = {
      NODE_ENV = 'development',
      DEBUG = 'true',
      API_KEY = 'secret123',
    },
    ports = {
      { host_port = 3000, container_port = 3000 },
      { host_port = 8080, container_port = 80 },
      { host_port = 5432, container_port = 5432 },
    },
    mounts = {
      {
        type = 'bind',
        source = '/host/config',
        target = '/container/config',
        readonly = true,
        consistency = 'cached',
      },
      {
        type = 'bind',
        source = '/host/data',
        target = '/container/data',
        readonly = false,
      },
    },
    remote_user = 'vscode',
    privileged = true,
    init = true,
  }

  -- Test build create args
  local args = docker._build_create_args(test_config)
  local args_string = table.concat(args, ' ')

  -- Check all required components
  local required_checks = {
    'create',
    '--name',
    '-it',
    '-w /workspace',
    '-e NODE_ENV=development',
    '-e DEBUG=true',
    '-e API_KEY=secret123',
    '-p 3000:3000',
    '-p 8080:80',
    '-p 5432:5432',
    '--mount type=bind,source=/host/config,target=/container/config,readonly,consistency=cached',
    '--mount type=bind,source=/host/data,target=/container/data',
    '--privileged',
    '--init',
    '--user vscode',
    '-v /host/workspace:/container/workspace',
    'ubuntu:latest',
  }

  for _, check in ipairs(required_checks) do
    if not args_string:find(check, 1, true) then
      print('✗ Missing argument:', check)
      print('Full args:', args_string)
      restore_vim_system(orig_funcs)
      return false
    end
  end

  print('✓ All container creation arguments correctly built')

  -- Test async container creation
  local creation_completed = false
  local created_container_id = nil
  local creation_error = nil

  docker.create_container_async(test_config, function(container_id, error)
    creation_completed = true
    created_container_id = container_id
    creation_error = error
  end)

  -- Wait for completion
  local wait_count = 0
  while not creation_completed and wait_count < 100 do
    vim.wait(10)
    wait_count = wait_count + 1
  end

  if created_container_id and not creation_error then
    print('✓ Async container creation works')
  else
    print('✗ Async container creation failed:', creation_error)
    restore_vim_system(orig_funcs)
    return false
  end

  -- Test container creation failure
  vim.fn.system = function(cmd)
    if cmd:match('docker create') then
      vim.v.shell_error = 1
      return 'Error: image not found'
    end
    return orig_funcs.system(cmd)
  end

  local creation_failed = false
  local failure_error = nil

  docker.create_container_async(test_config, function(container_id, error)
    creation_failed = container_id == nil
    failure_error = error
  end)

  -- Wait for completion
  wait_count = 0
  while failure_error == nil and wait_count < 100 do
    vim.wait(10)
    wait_count = wait_count + 1
  end

  if creation_failed and failure_error then
    print('✓ Container creation failure handled correctly')
  else
    print('✗ Container creation failure handling failed')
    restore_vim_system(orig_funcs)
    return false
  end

  restore_vim_system(orig_funcs)
  return true
end

-- Test 6: Container Lifecycle Operations
function tests.test_container_lifecycle_comprehensive()
  print('\n=== Comprehensive Container Lifecycle Tests ===')

  local orig_funcs = mock_vim_system()
  local docker = require('container.docker')

  local container_id = 'test-container-123'

  -- Test start container async
  local start_completed = false
  local start_success = false

  docker.start_container_async(container_id, function(success, error)
    start_completed = true
    start_success = success
  end)

  -- Wait for completion
  local wait_count = 0
  while not start_completed and wait_count < 100 do
    vim.wait(10)
    wait_count = wait_count + 1
  end

  if start_success then
    print('✓ Async container start works')
  else
    print('✗ Async container start failed')
    restore_vim_system(orig_funcs)
    return false
  end

  -- Test container status
  local status = docker.get_container_status(container_id)
  if status == 'running' then
    print('✓ Container status retrieval works')
  else
    print('✗ Container status failed, got:', status)
    restore_vim_system(orig_funcs)
    return false
  end

  -- Test container info
  local info = docker.get_container_info(container_id)
  if info and info.State and info.State.Status == 'running' then
    print('✓ Container info retrieval works')
  else
    print('✗ Container info failed')
    restore_vim_system(orig_funcs)
    return false
  end

  -- Test stop container async
  local stop_completed = false
  local stop_success = false

  docker.stop_container_async(container_id, function(success, error)
    stop_completed = true
    stop_success = success
  end)

  -- Wait for completion
  wait_count = 0
  while not stop_completed and wait_count < 100 do
    vim.wait(10)
    wait_count = wait_count + 1
  end

  if stop_success then
    print('✓ Async container stop works')
  else
    print('✗ Async container stop failed')
    restore_vim_system(orig_funcs)
    return false
  end

  -- Test remove container async
  local remove_completed = false
  local remove_success = false

  docker.remove_container_async(container_id, false, function(success, error)
    remove_completed = true
    remove_success = success
  end)

  -- Wait for completion
  wait_count = 0
  while not remove_completed and wait_count < 100 do
    vim.wait(10)
    wait_count = wait_count + 1
  end

  if remove_success then
    print('✓ Async container remove works')
  else
    print('✗ Async container remove failed')
    restore_vim_system(orig_funcs)
    return false
  end

  restore_vim_system(orig_funcs)
  return true
end

-- Test 7: Command Execution Variations
function tests.test_command_execution_comprehensive()
  print('\n=== Comprehensive Command Execution Tests ===')

  local orig_funcs = mock_vim_system()
  local docker = require('container.docker')

  local container_id = 'test-container-123'

  -- Test sync command execution with options
  local result = docker.run_docker_command({ 'ps', '-a' }, { cwd = '/test/dir', verbose = true })
  if result and result.success then
    print('✓ Sync command with options works')
  else
    print('✗ Sync command with options failed')
    restore_vim_system(orig_funcs)
    return false
  end

  -- Test async command execution
  local async_completed = false
  local async_result = nil

  docker.run_docker_command_async({ '--version' }, { timeout = 30 }, function(result)
    async_completed = true
    async_result = result
  end)

  -- Wait for completion
  local wait_count = 0
  while not async_completed and wait_count < 100 do
    vim.wait(10)
    wait_count = wait_count + 1
  end

  if async_result and async_result.success then
    print('✓ Async command execution works')
  else
    print('✗ Async command execution failed')
    restore_vim_system(orig_funcs)
    return false
  end

  -- Test exec command with options
  local exec_completed = false
  local exec_result = nil

  local exec_opts = {
    workdir = '/workspace',
    user = 'vscode',
    env = { PATH = '/usr/local/bin:/usr/bin:/bin' },
    interactive = false,
    on_complete = function(result)
      exec_completed = true
      exec_result = result
    end,
  }

  docker.exec_command(container_id, 'echo "test"', exec_opts)

  -- Wait for completion
  wait_count = 0
  while not exec_completed and wait_count < 100 do
    vim.wait(10)
    wait_count = wait_count + 1
  end

  if exec_result and exec_result.success then
    print('✓ Exec command with options works')
  else
    print('✗ Exec command with options failed')
    restore_vim_system(orig_funcs)
    return false
  end

  -- Test exec command async
  local exec_async_completed = false
  local exec_async_result = nil

  docker.exec_command_async(container_id, { 'ls', '-la' }, {
    workdir = '/workspace',
    user = 'root',
    tty = true,
    detach = false,
  }, function(result)
    exec_async_completed = true
    exec_async_result = result
  end)

  -- Wait for completion
  wait_count = 0
  while not exec_async_completed and wait_count < 100 do
    vim.wait(10)
    wait_count = wait_count + 1
  end

  if exec_async_result and exec_async_result.success then
    print('✓ Async exec command works')
  else
    print('✗ Async exec command failed')
    restore_vim_system(orig_funcs)
    return false
  end

  restore_vim_system(orig_funcs)
  return true
end

-- Test 8: Headless Mode Operations
function tests.test_headless_mode_operations()
  print('\n=== Headless Mode Operations Tests ===')

  local orig_funcs = mock_vim_system()

  -- Mock headless mode
  local orig_servername = vim.v.servername
  local orig_argc = vim.fn.argc

  vim.v.servername = ''
  vim.fn.argc = function()
    return 0
  end

  local docker = require('container.docker')

  -- Test headless mode detection and async operations
  local async_completed = false
  local async_result = nil

  docker.check_docker_availability_async(function(success, error)
    async_completed = true
    async_result = success
  end)

  -- Wait for completion (should be faster in headless mode)
  local wait_count = 0
  while not async_completed and wait_count < 200 do
    vim.wait(10)
    wait_count = wait_count + 1
  end

  if async_result then
    print('✓ Headless mode async operations work')
  else
    print('✗ Headless mode async operations failed')
    vim.v.servername = orig_servername
    vim.fn.argc = orig_argc
    restore_vim_system(orig_funcs)
    return false
  end

  -- Test command streaming in headless mode
  local stream_completed = false
  local stream_exit_code = nil

  local job_id = docker.execute_command_stream('test-container', 'echo "test"', {
    on_stdout = function(line)
      -- Should handle stdout
    end,
    on_stderr = function(line)
      -- Should handle stderr
    end,
    on_exit = function(exit_code)
      stream_completed = true
      stream_exit_code = exit_code
    end,
  })

  if job_id == 1 then -- Dummy job ID in headless mode
    print('✓ Headless mode streaming works')
  else
    print('✗ Headless mode streaming failed')
    vim.v.servername = orig_servername
    vim.fn.argc = orig_argc
    restore_vim_system(orig_funcs)
    return false
  end

  -- Restore normal mode
  vim.v.servername = orig_servername
  vim.fn.argc = orig_argc

  restore_vim_system(orig_funcs)
  return true
end

-- Test 9: Error Message Builders and Network Handling
function tests.test_error_handling_comprehensive()
  print('\n=== Comprehensive Error Handling Tests ===')

  local orig_funcs = mock_vim_system()
  local docker = require('container.docker')

  -- Test Docker not found error message
  local not_found_error = docker._build_docker_not_found_error()
  if not_found_error and not_found_error:match('Docker command not found') then
    print('✓ Docker not found error message works')
  else
    print('✗ Docker not found error message failed')
    restore_vim_system(orig_funcs)
    return false
  end

  -- Test Docker daemon error message
  local daemon_error = docker._build_docker_daemon_error()
  if daemon_error and daemon_error:match('daemon is not running') then
    print('✓ Docker daemon error message works')
  else
    print('✗ Docker daemon error message failed')
    restore_vim_system(orig_funcs)
    return false
  end

  -- Test network error handling
  local network_error = docker.handle_network_error('Connection timeout')
  if network_error and network_error:match('Network operation failed') then
    print('✓ Network error handling works')
  else
    print('✗ Network error handling failed')
    restore_vim_system(orig_funcs)
    return false
  end

  -- Test container error handling
  local container_error = docker.handle_container_error('create', 'container-123', 'Image not found')
  if container_error and container_error:match('Container create operation failed') then
    print('✓ Container error handling works')
  else
    print('✗ Container error handling failed')
    restore_vim_system(orig_funcs)
    return false
  end

  restore_vim_system(orig_funcs)
  return true
end

-- Test 10: Container Listing and Port Management
function tests.test_container_listing_and_ports()
  print('\n=== Container Listing and Port Management Tests ===')

  local orig_funcs = mock_vim_system()
  local docker = require('container.docker')

  -- Test container listing
  local containers = docker.list_containers()
  if containers and #containers > 0 then
    print('✓ Container listing works')
  else
    print('✗ Container listing failed')
    restore_vim_system(orig_funcs)
    return false
  end

  -- Test devcontainer listing
  local devcontainers = docker.list_devcontainers()
  if devcontainers then
    print('✓ Devcontainer listing works')
  else
    print('✗ Devcontainer listing failed')
    restore_vim_system(orig_funcs)
    return false
  end

  -- Test port forwarding listing
  local ports = docker.get_forwarded_ports()
  if ports then
    print('✓ Port forwarding listing works')
  else
    print('✗ Port forwarding listing failed')
    restore_vim_system(orig_funcs)
    return false
  end

  -- Test container name for project
  local project_path = '/test/project'
  local container_name = docker.get_container_name(project_path)
  if container_name and container_name:match('%-devcontainer$') then
    print('✓ Container name for project works')
  else
    print('✗ Container name for project failed')
    restore_vim_system(orig_funcs)
    return false
  end

  restore_vim_system(orig_funcs)
  return true
end

-- Test 11: Image Pull Operations with Retry Logic
function tests.test_image_pull_operations()
  print('\n=== Image Pull Operations Tests ===')

  local orig_funcs = mock_vim_system()
  local docker = require('container.docker')

  -- Test simple image pull
  local pull_completed = false
  local pull_success = false

  docker.pull_image('alpine:latest', function(progress_msg)
    -- Handle progress
  end, function(success, result)
    pull_completed = true
    pull_success = success
  end)

  -- Wait for completion
  local wait_count = 0
  while not pull_completed and wait_count < 100 do
    vim.wait(10)
    wait_count = wait_count + 1
  end

  if pull_success then
    print('✓ Simple image pull works')
  else
    print('✗ Simple image pull failed')
    restore_vim_system(orig_funcs)
    return false
  end

  -- Test async image pull with progress
  local async_pull_completed = false
  local async_pull_success = false
  local progress_received = false

  local job_id = docker.pull_image_async('ubuntu:latest', function(progress_msg)
    progress_received = true
  end, function(success, result)
    async_pull_completed = true
    async_pull_success = success
  end)

  if job_id and job_id > 0 then
    print('✓ Async image pull started successfully')
  else
    print('✗ Async image pull failed to start')
    restore_vim_system(orig_funcs)
    return false
  end

  -- Wait for completion
  wait_count = 0
  while not async_pull_completed and wait_count < 200 do
    vim.wait(10)
    wait_count = wait_count + 1
  end

  if async_pull_success then
    print('✓ Async image pull completed successfully')
  else
    print('✗ Async image pull failed')
    restore_vim_system(orig_funcs)
    return false
  end

  if progress_received then
    print('✓ Pull progress messages received')
  else
    print('✗ Pull progress messages not received')
  end

  restore_vim_system(orig_funcs)
  return true
end

-- Test 12: Prepare Image Scenarios
function tests.test_prepare_image_scenarios()
  print('\n=== Prepare Image Scenarios Tests ===')

  local orig_funcs = mock_vim_system()
  local docker = require('container.docker')

  -- Test prepare existing image
  local config_existing = {
    image = 'ubuntu:latest',
  }

  local prepare_completed = false
  local prepare_success = false

  docker.prepare_image(config_existing, function(progress_msg)
    -- Handle progress
  end, function(success, result)
    prepare_completed = true
    prepare_success = success
  end)

  -- Wait for completion
  local wait_count = 0
  while not prepare_completed and wait_count < 100 do
    vim.wait(10)
    wait_count = wait_count + 1
  end

  if prepare_success then
    print('✓ Prepare existing image works')
  else
    print('✗ Prepare existing image failed')
    restore_vim_system(orig_funcs)
    return false
  end

  -- Test prepare with Dockerfile
  local config_build = {
    dockerfile = 'Dockerfile',
    name = 'custom-image',
    context = '.',
    base_path = '/test/project',
    build_args = {
      NODE_VERSION = '18',
      ENV = 'development',
    },
  }

  prepare_completed = false
  prepare_success = false

  docker.prepare_image(config_build, function(progress_msg)
    -- Handle progress
  end, function(success, result)
    prepare_completed = true
    prepare_success = success
  end)

  -- Wait for completion
  wait_count = 0
  while not prepare_completed and wait_count < 100 do
    vim.wait(10)
    wait_count = wait_count + 1
  end

  if prepare_success then
    print('✓ Prepare image with Dockerfile works')
  else
    print('✗ Prepare image with Dockerfile failed')
    restore_vim_system(orig_funcs)
    return false
  end

  -- Test error scenario (no image or dockerfile)
  local config_error = {}

  prepare_completed = false
  local prepare_error = false

  docker.prepare_image(config_error, function(progress_msg)
    -- Handle progress
  end, function(success, result)
    prepare_completed = true
    prepare_error = not success
  end)

  -- Wait for completion
  wait_count = 0
  while not prepare_completed and wait_count < 100 do
    vim.wait(10)
    wait_count = wait_count + 1
  end

  if prepare_error then
    print('✓ Prepare image error handling works')
  else
    print('✗ Prepare image error handling failed')
    restore_vim_system(orig_funcs)
    return false
  end

  restore_vim_system(orig_funcs)
  return true
end

-- Main test runner
local function run_comprehensive_docker_tests()
  print('=== Comprehensive Docker Coverage Tests ===')
  print('Targeting uncovered functions to achieve 70%+ coverage')
  print('')

  local test_functions = {
    tests.test_docker_availability_comprehensive,
    tests.test_shell_detection_comprehensive,
    tests.test_container_name_generation_edge_cases,
    tests.test_image_operations_comprehensive,
    tests.test_container_creation_comprehensive,
    tests.test_container_lifecycle_comprehensive,
    tests.test_command_execution_comprehensive,
    tests.test_headless_mode_operations,
    tests.test_error_handling_comprehensive,
    tests.test_container_listing_and_ports,
    tests.test_image_pull_operations,
    tests.test_prepare_image_scenarios,
  }

  local passed = 0
  local total = #test_functions

  for i, test_func in ipairs(test_functions) do
    local success, result = pcall(test_func)
    if success and result ~= false then
      passed = passed + 1
      print('✅ Comprehensive Test', i, 'PASSED')
    else
      print('❌ Comprehensive Test', i, 'FAILED')
      if not success then
        print('Error:', result)
      end
    end
    print('')
  end

  print('=== Comprehensive Docker Coverage Test Results ===')
  print(string.format('Passed: %d/%d', passed, total))

  if passed == total then
    print('🎉 All comprehensive Docker coverage tests passed!')
    print('Expected to significantly improve lua/container/docker/init.lua coverage to 70%+')
    return 0
  else
    print('⚠ Some comprehensive Docker coverage tests failed.')
    return 1
  end
end

-- Run tests
local exit_code = run_comprehensive_docker_tests()
os.exit(exit_code)
