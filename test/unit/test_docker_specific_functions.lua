#!/usr/bin/env lua

-- Specific Function Coverage Tests for Docker Module
-- Targeting specific uncovered lines and edge cases

package.path = './test/helpers/?.lua;./lua/?.lua;./lua/?/init.lua;' .. package.path

local helpers = require('init')
helpers.setup_vim_mock()
helpers.setup_lua_path()

-- Enhanced mocking for specific function testing
local function setup_enhanced_mocks()
  -- Store original functions for restoration
  local orig = {
    system = vim.fn.system,
    jobstart = vim.fn.jobstart,
    jobwait = vim.fn.jobwait,
    jobstop = vim.fn.jobstop,
    timer_stop = vim.fn.timer_stop,
    sha256 = vim.fn.sha256,
    getcwd = vim.fn.getcwd,
    shellescape = vim.fn.shellescape,
    defer_fn = vim.defer_fn,
    schedule = vim.schedule,
    wait = vim.wait,
    loop = vim.loop,
  }

  -- Mock vim.loop for hrtime
  vim.loop = vim.loop or {}
  vim.loop.hrtime = function()
    return os.clock() * 1e9 -- Convert to nanoseconds
  end

  -- Enhanced sha256 mock
  vim.fn.sha256 = function(str)
    local sum = 0
    for i = 1, #str do
      sum = sum + string.byte(str, i)
    end
    return string.format('%016x', sum) .. string.rep('0', 48)
  end

  -- Enhanced getcwd mock
  vim.fn.getcwd = function()
    return '/test/workspace'
  end

  -- Enhanced shellescape mock
  vim.fn.shellescape = function(str)
    if not str then
      return "''"
    end
    return "'" .. str:gsub("'", "'\"'\"'") .. "'"
  end

  -- Enhanced defer_fn mock
  vim.defer_fn = function(fn, delay)
    if fn then
      -- Execute immediately for testing
      fn()
    end
    return 1
  end

  -- Enhanced schedule mock
  vim.schedule = function(fn)
    if fn then
      fn()
    end
  end

  -- Enhanced wait mock
  vim.wait = function(timeout, condition, interval)
    if condition then
      -- Check condition a few times
      for i = 1, 5 do
        if condition() then
          return true
        end
      end
    end
    return false
  end

  -- Enhanced timer_stop mock
  vim.fn.timer_stop = function(timer_id)
    return 1
  end

  return orig
end

local function restore_mocks(orig)
  vim.fn.system = orig.system
  vim.fn.jobstart = orig.jobstart
  vim.fn.jobwait = orig.jobwait
  vim.fn.jobstop = orig.jobstop
  vim.fn.timer_stop = orig.timer_stop
  vim.fn.sha256 = orig.sha256
  vim.fn.getcwd = orig.getcwd
  vim.fn.shellescape = orig.shellescape
  vim.defer_fn = orig.defer_fn
  vim.schedule = orig.schedule
  vim.wait = orig.wait
  vim.loop = orig.loop
end

local tests = {}

-- Test specific shell detection edge cases
function tests.test_shell_detection_edge_cases()
  print('=== Shell Detection Edge Cases ===')

  local orig = setup_enhanced_mocks()
  local docker = require('container.docker')

  local test_cases = {
    {
      name = 'Container not running',
      container_id = 'stopped-container',
      setup = function()
        vim.fn.system = function(cmd)
          if cmd:match('docker inspect %-f') then
            vim.v.shell_error = 1
            return 'Error: No such container'
          end
          return ''
        end
      end,
      expected = 'sh',
    },
    {
      name = 'Container status not running',
      container_id = 'not-running-container',
      setup = function()
        vim.fn.system = function(cmd)
          if cmd:match('docker inspect %-f') then
            vim.v.shell_error = 0
            return 'exited'
          end
          return ''
        end
      end,
      expected = 'sh',
    },
    {
      name = 'Bash available',
      container_id = 'bash-container',
      setup = function()
        vim.fn.system = function(cmd)
          if cmd:match('docker inspect %-f') then
            vim.v.shell_error = 0
            return 'running'
          elseif cmd:match('which bash') then
            vim.v.shell_error = 0
            return '/bin/bash'
          end
          return ''
        end
      end,
      expected = 'bash',
    },
    {
      name = 'Only zsh available',
      container_id = 'zsh-container',
      setup = function()
        vim.fn.system = function(cmd)
          if cmd:match('docker inspect %-f') then
            vim.v.shell_error = 0
            return 'running'
          elseif cmd:match('which bash') then
            vim.v.shell_error = 1
            return ''
          elseif cmd:match('which zsh') then
            vim.v.shell_error = 0
            return '/usr/bin/zsh'
          end
          return ''
        end
      end,
      expected = 'zsh',
    },
    {
      name = 'Only sh available',
      container_id = 'sh-only-container',
      setup = function()
        vim.fn.system = function(cmd)
          if cmd:match('docker inspect %-f') then
            vim.v.shell_error = 0
            return 'running'
          elseif cmd:match('which bash') then
            vim.v.shell_error = 1
            return ''
          elseif cmd:match('which zsh') then
            vim.v.shell_error = 1
            return ''
          elseif cmd:match('which sh') then
            vim.v.shell_error = 0
            return '/bin/sh'
          end
          return ''
        end
      end,
      expected = 'sh',
    },
    {
      name = 'No shells available - fallback',
      container_id = 'no-shell-container',
      setup = function()
        vim.fn.system = function(cmd)
          if cmd:match('docker inspect %-f') then
            vim.v.shell_error = 0
            return 'running'
          elseif cmd:match('which') then
            vim.v.shell_error = 1
            return ''
          end
          return ''
        end
      end,
      expected = 'sh',
    },
  }

  for _, test_case in ipairs(test_cases) do
    -- Clear cache first
    docker.clear_shell_cache()

    -- Setup test-specific mocks
    test_case.setup()

    -- Test shell detection
    local detected_shell = docker.detect_shell(test_case.container_id)

    if detected_shell == test_case.expected then
      print('✓', test_case.name, '- detected:', detected_shell)
    else
      print('✗', test_case.name, '- expected:', test_case.expected, 'got:', detected_shell)
      restore_mocks(orig)
      return false
    end

    -- Test caching by calling again
    local cached_shell = docker.detect_shell(test_case.container_id)
    if cached_shell == test_case.expected then
      print('✓', test_case.name, '- cache works')
    else
      print('✗', test_case.name, '- cache failed')
      restore_mocks(orig)
      return false
    end
  end

  restore_mocks(orig)
  return true
end

-- Test run_docker_command variations
function tests.test_run_docker_command_variations()
  print('\n=== Run Docker Command Variations ===')

  local orig = setup_enhanced_mocks()
  local docker = require('container.docker')

  -- Test with cwd option
  vim.fn.system = function(cmd)
    if cmd:match('cd .* &&') then
      vim.v.shell_error = 0
      return 'success with cwd'
    end
    vim.v.shell_error = 0
    return 'success'
  end

  local result1 = docker.run_docker_command({ 'ps' }, { cwd = '/test/directory' })
  if result1.success and result1.stdout:match('success with cwd') then
    print('✓ Docker command with cwd works')
  else
    print('✗ Docker command with cwd failed')
    restore_mocks(orig)
    return false
  end

  -- Test lightweight vs verbose logging
  local result2 = docker.run_docker_command({ 'inspect', 'container' }, { verbose = false })
  if result2.success then
    print('✓ Lightweight command (no verbose logging) works')
  else
    print('✗ Lightweight command failed')
    restore_mocks(orig)
    return false
  end

  local result3 = docker.run_docker_command({ 'inspect', 'container' }, { verbose = true })
  if result3.success then
    print('✓ Lightweight command with verbose logging works')
  else
    print('✗ Lightweight command with verbose failed')
    restore_mocks(orig)
    return false
  end

  -- Test images command
  local result4 = docker.run_docker_command({ 'images', '-q' }, {})
  if result4.success then
    print('✓ Images command (lightweight) works')
  else
    print('✗ Images command failed')
    restore_mocks(orig)
    return false
  end

  -- Test ps command
  local result5 = docker.run_docker_command({ 'ps', '-a' }, {})
  if result5.success then
    print('✓ PS command (lightweight) works')
  else
    print('✗ PS command failed')
    restore_mocks(orig)
    return false
  end

  -- Test command failure
  vim.fn.system = function(cmd)
    vim.v.shell_error = 1
    return 'Command failed'
  end

  local result6 = docker.run_docker_command({ 'invalid', 'command' })
  if not result6.success and result6.stderr == 'Command failed' then
    print('✓ Command failure handling works')
  else
    print('✗ Command failure handling failed')
    restore_mocks(orig)
    return false
  end

  restore_mocks(orig)
  return true
end

-- Test async command variations and edge cases
function tests.test_async_command_edge_cases()
  print('\n=== Async Command Edge Cases ===')

  local orig = setup_enhanced_mocks()
  local docker = require('container.docker')

  -- Mock jobstart for various scenarios
  local job_counter = 1000

  vim.fn.jobstart = function(cmd, opts)
    job_counter = job_counter + 1
    local job_id = job_counter

    -- Simulate different job scenarios
    if cmd[1] == 'docker' and cmd[2] == 'fail' then
      return 0 -- Failed to start
    elseif cmd[1] == 'docker' and cmd[2] == 'invalid' then
      return -1 -- Invalid arguments
    end

    -- Simulate successful job
    vim.defer_fn(function()
      if opts.on_stdout then
        opts.on_stdout(job_id, { 'stdout line 1', 'stdout line 2' }, 'stdout')
      end
      if opts.on_stderr then
        opts.on_stderr(job_id, { 'stderr line 1' }, 'stderr')
      end
      if opts.on_exit then
        opts.on_exit(job_id, 0, 'exit')
      end
    end, 1)

    return job_id
  end

  -- Test successful async command
  local async_completed = false
  local async_result = nil

  docker.run_docker_command_async({ 'version' }, { timeout = 5 }, function(result)
    async_completed = true
    async_result = result
  end)

  -- Wait for completion
  local wait_count = 0
  while not async_completed and wait_count < 50 do
    vim.wait(10)
    wait_count = wait_count + 1
  end

  if async_result and async_result.success then
    print('✓ Async command success works')
    print('  - stdout:', async_result.stdout)
    print('  - stderr:', async_result.stderr)
  else
    print('✗ Async command success failed')
    restore_mocks(orig)
    return false
  end

  -- Test lightweight command suppression
  async_completed = false
  async_result = nil

  docker.run_docker_command_async({ 'inspect', 'container' }, {}, function(result)
    async_completed = true
    async_result = result
  end)

  wait_count = 0
  while not async_completed and wait_count < 50 do
    vim.wait(10)
    wait_count = wait_count + 1
  end

  if async_result and async_result.success then
    print('✓ Async lightweight command works')
  else
    print('✗ Async lightweight command failed')
    restore_mocks(orig)
    return false
  end

  -- Test with cwd option
  async_completed = false
  async_result = nil

  docker.run_docker_command_async({ 'build', '.' }, { cwd = '/test/build' }, function(result)
    async_completed = true
    async_result = result
  end)

  wait_count = 0
  while not async_completed and wait_count < 50 do
    vim.wait(10)
    wait_count = wait_count + 1
  end

  if async_result and async_result.success then
    print('✓ Async command with cwd works')
  else
    print('✗ Async command with cwd failed')
    restore_mocks(orig)
    return false
  end

  restore_mocks(orig)
  return true
end

-- Test execute_command with all modes
function tests.test_execute_command_modes()
  print('\n=== Execute Command Modes ===')

  local orig = setup_enhanced_mocks()
  local docker = require('container.docker')

  local container_id = 'test-container'

  -- Mock exec_command_async for testing
  local exec_results = {}

  -- Test sync mode
  local sync_completed = false
  local sync_result = nil

  -- Override exec_command_async to simulate execution
  local original_exec_async = docker.exec_command_async
  docker.exec_command_async = function(cid, cmd, opts, callback)
    vim.defer_fn(function()
      callback({
        success = true,
        code = 0,
        stdout = 'sync output',
        stderr = '',
      })
    end, 1)
  end

  local result = docker.execute_command(container_id, 'echo test', { mode = 'sync' })
  if result and result.success then
    print('✓ Sync execution mode works')
  else
    print('✗ Sync execution mode failed')
    restore_mocks(orig)
    return false
  end

  -- Test async mode
  local async_completed = false
  local async_result = nil

  docker.execute_command(container_id, 'echo async', {
    mode = 'async',
    callback = function(result)
      async_completed = true
      async_result = result
    end,
  })

  local wait_count = 0
  while not async_completed and wait_count < 50 do
    vim.wait(10)
    wait_count = wait_count + 1
  end

  if async_result and async_result.success then
    print('✓ Async execution mode works')
  else
    print('✗ Async execution mode failed')
    restore_mocks(orig)
    return false
  end

  -- Test fire_and_forget mode
  local fire_completed = false

  docker.exec_command_async = function(cid, cmd, opts, callback)
    vim.defer_fn(function()
      fire_completed = true
      callback({
        success = true,
        code = 0,
        stdout = 'fire and forget output',
        stderr = '',
      })
    end, 1)
  end

  docker.execute_command(container_id, 'echo fire_and_forget', { mode = 'fire_and_forget' })

  wait_count = 0
  while not fire_completed and wait_count < 50 do
    vim.wait(10)
    wait_count = wait_count + 1
  end

  if fire_completed then
    print('✓ Fire and forget execution mode works')
  else
    print('✗ Fire and forget execution mode failed')
    restore_mocks(orig)
    return false
  end

  -- Test with various options
  local options_result = docker.execute_command(container_id, { 'ls', '-la' }, {
    mode = 'sync',
    workdir = '/workspace',
    user = 'vscode',
    env = { PATH = '/usr/bin' },
    timeout = 10000,
  })

  if options_result and options_result.success then
    print('✓ Execute command with options works')
  else
    print('✗ Execute command with options failed')
    restore_mocks(orig)
    return false
  end

  -- Restore original function
  docker.exec_command_async = original_exec_async

  restore_mocks(orig)
  return true
end

-- Test specific container operations
function tests.test_container_operations_specific()
  print('\n=== Specific Container Operations ===')

  local orig = setup_enhanced_mocks()
  local docker = require('container.docker')

  -- Mock system calls for container operations
  vim.fn.system = function(cmd)
    if cmd:match('docker start') then
      vim.v.shell_error = 0
      return 'container-started'
    elseif cmd:match('docker stop') then
      vim.v.shell_error = 0
      return 'container-stopped'
    elseif cmd:match('docker exec .* echo ready') then
      vim.v.shell_error = 0
      return 'ready'
    elseif cmd:match('docker inspect .* %-%-format') then
      vim.v.shell_error = 0
      return 'running'
    end
    vim.v.shell_error = 0
    return ''
  end

  local container_id = 'test-container'

  -- Test simple container start
  local start_success, start_status = docker.start_container_simple(container_id)
  if start_success and start_status == 'running' then
    print('✓ Simple container start works')
  else
    print('✗ Simple container start failed')
    restore_mocks(orig)
    return false
  end

  -- Test container start failure
  vim.fn.system = function(cmd)
    if cmd:match('docker start') then
      vim.v.shell_error = 1
      return 'Error: container not found'
    end
    return ''
  end

  local start_fail, start_error = docker.start_container_simple('nonexistent-container')
  if not start_fail and start_error then
    print('✓ Simple container start failure handling works')
  else
    print('✗ Simple container start failure handling failed')
    restore_mocks(orig)
    return false
  end

  -- Test wait for container ready
  vim.fn.system = function(cmd)
    if cmd:match('docker inspect .* %-%-format') then
      vim.v.shell_error = 0
      return 'running'
    elseif cmd:match('docker exec .* echo') then
      vim.v.shell_error = 0
      return 'ready'
    end
    return ''
  end

  local ready_completed = false
  local ready_result = false

  docker.wait_for_container_ready(container_id, function(ready)
    ready_completed = true
    ready_result = ready
  end, 5) -- max 5 attempts

  local wait_count = 0
  while not ready_completed and wait_count < 100 do
    vim.wait(10)
    wait_count = wait_count + 1
  end

  if ready_result then
    print('✓ Wait for container ready works')
  else
    print('✗ Wait for container ready failed')
    restore_mocks(orig)
    return false
  end

  restore_mocks(orig)
  return true
end

-- Test build command generation
function tests.test_build_command_generation()
  print('\n=== Build Command Generation ===')

  local orig = setup_enhanced_mocks()
  local docker = require('container.docker')

  -- Test build_command helper
  local simple_command = docker.build_command('echo hello')
  if simple_command == 'echo hello' then
    print('✓ Simple build command works')
  else
    print('✗ Simple build command failed:', simple_command)
    restore_mocks(orig)
    return false
  end

  -- Test build_command with options
  local complex_command = docker.build_command('npm test', {
    setup_env = true,
    cd = '/workspace/app',
  })

  if
    complex_command:match('source.*profile')
    and complex_command:match('cd .*/workspace/app')
    and complex_command:match('npm test')
  then
    print('✓ Complex build command works')
  else
    print('✗ Complex build command failed:', complex_command)
    restore_mocks(orig)
    return false
  end

  -- Test with array command
  local array_command = docker.build_command({ 'ls', '-la', '/tmp' }, {
    setup_env = false,
    cd = '/workspace',
  })

  if array_command:match('cd /workspace') and array_command:match('ls %-la /tmp') then
    print('✓ Array build command works')
  else
    print('✗ Array build command failed:', array_command)
    restore_mocks(orig)
    return false
  end

  restore_mocks(orig)
  return true
end

-- Test container termination and kill operations
function tests.test_container_termination()
  print('\n=== Container Termination Operations ===')

  local orig = setup_enhanced_mocks()
  local docker = require('container.docker')

  -- Mock async command execution for kill and terminate
  local kill_completed = false
  local kill_success = false

  vim.fn.jobstart = function(cmd, opts)
    local job_id = 1234
    vim.defer_fn(function()
      if opts.on_exit then
        opts.on_exit(job_id, 0, 'exit')
      end
    end, 1)
    return job_id
  end

  -- Test kill container
  docker.kill_container('test-container', function(success, error)
    kill_completed = true
    kill_success = success
  end)

  local wait_count = 0
  while not kill_completed and wait_count < 50 do
    vim.wait(10)
    wait_count = wait_count + 1
  end

  if kill_success then
    print('✓ Container kill works')
  else
    print('✗ Container kill failed')
    restore_mocks(orig)
    return false
  end

  -- Test terminate container
  local terminate_completed = false
  local terminate_success = false

  docker.terminate_container('test-container', function(success, error)
    terminate_completed = true
    terminate_success = success
  end)

  wait_count = 0
  while not terminate_completed and wait_count < 50 do
    vim.wait(10)
    wait_count = wait_count + 1
  end

  if terminate_success then
    print('✓ Container terminate works')
  else
    print('✗ Container terminate failed')
    restore_mocks(orig)
    return false
  end

  restore_mocks(orig)
  return true
end

-- Test logs operations
function tests.test_logs_operations()
  print('\n=== Logs Operations ===')

  local orig = setup_enhanced_mocks()
  local docker = require('container.docker')

  vim.fn.system = function(cmd)
    vim.v.shell_error = 0
    return 'log line 1\nlog line 2\nlog line 3'
  end

  -- Test get logs with options
  local logs_completed = false
  local logs_result = nil

  docker.get_logs('test-container', {
    follow = false,
    tail = 10,
    since = '1h',
    on_complete = function(result)
      logs_completed = true
      logs_result = result
    end,
  })

  local wait_count = 0
  while not logs_completed and wait_count < 50 do
    vim.wait(10)
    wait_count = wait_count + 1
  end

  if logs_result and logs_result.success then
    print('✓ Logs retrieval works')
  else
    print('✗ Logs retrieval failed')
    restore_mocks(orig)
    return false
  end

  restore_mocks(orig)
  return true
end

-- Test attach and restart operations
function tests.test_attach_restart_operations()
  print('\n=== Attach and Restart Operations ===')

  local orig = setup_enhanced_mocks()
  local docker = require('container.docker')

  -- Mock container listing
  vim.fn.system = function(cmd)
    if cmd:match('docker ps') then
      vim.v.shell_error = 0
      return 'container123\ttest-container\tUp 5 minutes\tubuntu:latest'
    elseif cmd:match('docker stop') then
      vim.v.shell_error = 0
      return 'test-container'
    elseif cmd:match('docker start') then
      vim.v.shell_error = 0
      return 'test-container'
    end
    vim.v.shell_error = 0
    return ''
  end

  -- Test attach to existing container
  local attach_completed = false
  local attach_success = false
  local attached_name = nil

  docker.attach_to_container('test-container', function(success, name)
    attach_completed = true
    attach_success = success
    attached_name = name
  end)

  local wait_count = 0
  while not attach_completed and wait_count < 50 do
    vim.wait(10)
    wait_count = wait_count + 1
  end

  if attach_success and attached_name == 'test-container' then
    print('✓ Attach to existing container works')
  else
    print('✗ Attach to existing container failed')
    restore_mocks(orig)
    return false
  end

  -- Test attach to non-existent container
  attach_completed = false
  attach_success = true -- Should be false

  docker.attach_to_container('nonexistent-container', function(success, error)
    attach_completed = true
    attach_success = success
  end)

  wait_count = 0
  while not attach_completed and wait_count < 50 do
    vim.wait(10)
    wait_count = wait_count + 1
  end

  if not attach_success then
    print('✓ Attach to non-existent container handled')
  else
    print('✗ Attach to non-existent container failed')
    restore_mocks(orig)
    return false
  end

  -- Test restart container
  local restart_completed = false
  local restart_success = false

  docker.restart_container('test-container', function(success, error)
    restart_completed = true
    restart_success = success
  end)

  wait_count = 0
  while not restart_completed and wait_count < 100 do
    vim.wait(10)
    wait_count = wait_count + 1
  end

  if restart_success then
    print('✓ Container restart works')
  else
    print('✗ Container restart failed')
    restore_mocks(orig)
    return false
  end

  restore_mocks(orig)
  return true
end

-- Test error message builders
function tests.test_error_message_builders()
  print('\n=== Error Message Builders ===')

  local orig = setup_enhanced_mocks()
  local docker = require('container.docker')

  -- Test all error message builders
  local docker_not_found = docker._build_docker_not_found_error()
  if
    docker_not_found
    and docker_not_found:match('Docker command not found')
    and docker_not_found:match('Install Docker Desktop')
  then
    print('✓ Docker not found error message comprehensive')
  else
    print('✗ Docker not found error message incomplete')
    restore_mocks(orig)
    return false
  end

  local daemon_error = docker._build_docker_daemon_error()
  if daemon_error and daemon_error:match('daemon is not running') and daemon_error:match('systemctl start docker') then
    print('✓ Docker daemon error message comprehensive')
  else
    print('✗ Docker daemon error message incomplete')
    restore_mocks(orig)
    return false
  end

  local network_error = docker.handle_network_error('Connection timeout occurred')
  if
    network_error
    and network_error:match('Network operation failed')
    and network_error:match('Connection timeout occurred')
  then
    print('✓ Network error handling comprehensive')
  else
    print('✗ Network error handling incomplete')
    restore_mocks(orig)
    return false
  end

  -- Test container error for different operations
  local create_error = docker.handle_container_error('create', 'test-container', 'Image not found')
  if
    create_error
    and create_error:match('Container create operation failed')
    and create_error:match('Image not found')
  then
    print('✓ Container create error comprehensive')
  else
    print('✗ Container create error incomplete')
    restore_mocks(orig)
    return false
  end

  local start_error = docker.handle_container_error('start', 'test-container', 'Port already in use')
  if
    start_error
    and start_error:match('Container start operation failed')
    and start_error:match('docker logs test-container')
  then
    print('✓ Container start error comprehensive')
  else
    print('✗ Container start error incomplete')
    restore_mocks(orig)
    return false
  end

  local exec_error = docker.handle_container_error('exec', 'test-container', 'Command not found')
  if exec_error and exec_error:match('Container exec operation failed') and exec_error:match('docker ps') then
    print('✓ Container exec error comprehensive')
  else
    print('✗ Container exec error incomplete')
    restore_mocks(orig)
    return false
  end

  restore_mocks(orig)
  return true
end

-- Main test runner
local function run_specific_function_tests()
  print('=== Specific Function Coverage Tests for Docker Module ===')
  print('Targeting specific uncovered lines and edge cases')
  print('')

  local test_functions = {
    tests.test_shell_detection_edge_cases,
    tests.test_run_docker_command_variations,
    tests.test_async_command_edge_cases,
    tests.test_execute_command_modes,
    tests.test_container_operations_specific,
    tests.test_build_command_generation,
    tests.test_container_termination,
    tests.test_logs_operations,
    tests.test_attach_restart_operations,
    tests.test_error_message_builders,
  }

  local passed = 0
  local total = #test_functions

  for i, test_func in ipairs(test_functions) do
    local success, result = pcall(test_func)
    if success and result ~= false then
      passed = passed + 1
      print('✅ Specific Test', i, 'PASSED')
    else
      print('❌ Specific Test', i, 'FAILED')
      if not success then
        print('Error:', result)
      end
    end
    print('')
  end

  print('=== Specific Function Test Results ===')
  print(string.format('Passed: %d/%d', passed, total))

  if passed == total then
    print('🎉 All specific function tests passed!')
    print('Expected to cover additional edge cases and specific functions')
    return 0
  else
    print('⚠ Some specific function tests failed.')
    return 1
  end
end

-- Run tests
local exit_code = run_specific_function_tests()
os.exit(exit_code)
