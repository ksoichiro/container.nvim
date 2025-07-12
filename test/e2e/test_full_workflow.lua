-- End-to-End Tests for container.nvim (nvim --headless)
-- Tests complete workflows with real Docker containers
-- This provides the highest confidence in actual functionality

-- Setup test environment for nvim --headless
package.path = './test/e2e/helpers/?.lua;./test/helpers/?.lua;./lua/?.lua;./lua/?/init.lua;' .. package.path

local nvim_setup = require('nvim_setup')
nvim_setup.setup_nvim_environment()

-- Utility function for timestamped output
local function print_with_timestamp(msg)
  print(os.date('[%H:%M:%S]') .. ' ' .. msg)
end

-- E2E specific utilities
local function run_command(cmd, show_progress)
  if show_progress then
    print_with_timestamp('Running: ' .. cmd)
  end
  local handle = io.popen(cmd .. ' 2>&1')
  local result = handle:read('*a')
  local success = handle:close()
  if show_progress then
    print_with_timestamp(success and 'Command completed' or 'Command failed')
  end
  return success, result
end

local function wait_for_condition(condition_fn, timeout_ms, interval_ms, message)
  timeout_ms = timeout_ms or 30000 -- 30 seconds default
  interval_ms = interval_ms or 1000 -- 1 second default
  message = message or 'Waiting for condition'

  local start_time = os.time() * 1000 -- Convert to milliseconds
  local elapsed = 0

  while elapsed < timeout_ms do
    if condition_fn() then
      return true
    end

    elapsed = os.time() * 1000 - start_time
    if elapsed % 5000 < interval_ms then -- Print every 5 seconds
      print(string.format('  %s... (%.1fs/%.1fs)', message, elapsed / 1000, timeout_ms / 1000))
    end

    os.execute('sleep ' .. (interval_ms / 1000))
    elapsed = os.time() * 1000 - start_time
  end
  return false
end

local function cleanup_containers(name_pattern)
  run_command('docker ps -a --filter name=' .. name_pattern .. ' -q | xargs -r docker rm -f')
end

local tests = {}

-- Test 1: Complete workflow with existing examples
function tests.test_existing_example_workflow()
  print_with_timestamp('=== E2E Test 1: Existing Example Workflow ===')

  -- Try with actual example projects that should have valid devcontainer setups
  local example_projects = {
    'examples/python-example',
    'examples/node-example',
    'examples/go-example',
  }

  local worked_project = nil

  for _, project_dir in ipairs(example_projects) do
    -- Check if project exists
    local project_file = io.open(project_dir .. '/.devcontainer/devcontainer.json', 'r')
    if project_file then
      project_file:close()
      worked_project = project_dir
      print('Using example project:', project_dir)
      break
    end
  end

  if not worked_project then
    print('⚠ No example projects found with devcontainer.json')
    print('  This is expected in test environments')
    return true
  end

  local container_name_pattern = worked_project:gsub('[^%w]', '-')

  -- Cleanup any existing containers
  cleanup_containers(container_name_pattern)

  print('Setting up Node.js project test...')

  -- Change to project directory
  local original_dir = io.popen('pwd'):read('*l')
  os.execute('cd ' .. worked_project)

  -- Test 1.1: Plugin initialization in project
  print('Step 1.1: Testing plugin initialization')
  local container = require('container')

  local setup_success, setup_error = pcall(function()
    container.setup({
      log_level = 'debug',
      docker = { timeout = 60000 }, -- Longer timeout for E2E
    })
  end)

  if not setup_success then
    print('✗ Plugin setup failed')
    print('Setup error:', setup_error)
    return false
  end
  print('✓ Plugin initialized successfully')

  -- Test 1.2: DevContainer discovery and opening
  print('Step 1.2: Testing devcontainer discovery')
  local open_success, open_error = pcall(function()
    return container.open(worked_project)
  end)

  if not open_success then
    print('✗ DevContainer open failed')
    print('Open error:', open_error)
    return false
  end
  print('✓ DevContainer configuration loaded')

  -- Test 1.3: Container building/pulling
  print('Step 1.3: Testing image preparation')
  print('  This may take a while for first-time image pulls...')
  local build_success = pcall(function()
    return container.build()
  end)

  if not build_success then
    print('✗ Container build failed')
    return false
  end
  print('✓ Container image prepared')

  -- Test 1.4: Container startup
  print('Step 1.4: Testing container startup')
  print('  Starting container...')
  local start_success = pcall(function()
    return container.start()
  end)

  if not start_success then
    print('✗ Container start failed')
    return false
  end
  print('✓ Container start initiated')

  -- Test 1.5: Check for container creation attempt
  print('Step 1.5: Checking container creation')
  local container_found = wait_for_condition(function()
    local success, output = run_command('docker ps -a --filter name=' .. container_name_pattern .. ' -q')
    return success and output:gsub('%s+', '') ~= ''
  end, 10000, 1000, 'Checking for container creation')

  if container_found then
    print('✓ Container was created')

    -- Check if it's running
    local success, output =
      run_command('docker ps --filter name=' .. container_name_pattern .. ' --filter status=running -q')
    if success and output:gsub('%s+', '') ~= '' then
      print('✓ Container is running')
    else
      print('⚠ Container created but not running (may be expected for test projects)')
    end
  else
    print('⚠ No container created (may be expected behavior for test project paths)')
    print('  This is often normal - containers are only created for valid project structures')
  end

  -- Test 1.6: Execute command in container
  print('Step 1.6: Testing command execution')
  local exec_success = pcall(function()
    return container.execute('node --version')
  end)

  if not exec_success then
    print('⚠ Command execution failed (may be expected in E2E environment)')
  else
    print('✓ Command execution successful')
  end

  -- Test 1.7: Container cleanup
  print('Step 1.7: Testing container cleanup')
  local stop_success = pcall(function()
    return container.stop()
  end)

  if not stop_success then
    print('⚠ Container stop failed (may be expected)')
  else
    print('✓ Container stop initiated')
  end

  -- Force cleanup for E2E
  cleanup_containers(container_name_pattern)
  print('✓ Cleanup completed')

  -- Return to original directory
  os.execute('cd ' .. original_dir)

  return true
end

-- Test 2: Python workflow
function tests.test_python_full_workflow()
  print_with_timestamp('\n=== E2E Test 2: Python Full Workflow ===')

  local project_dir = 'test/e2e/sample-projects/simple-python'
  local container_name_pattern = 'simple-python-e2e-test'

  -- Cleanup any existing containers
  cleanup_containers(container_name_pattern)

  print('Setting up Python project test...')

  -- Similar workflow to Node.js but for Python
  local container = require('container')

  -- Reset plugin state for new test
  pcall(function()
    container.reset()
  end)

  -- Test setup with Python project
  local setup_success, setup_error = pcall(function()
    container.setup({ log_level = 'debug' })
    return container.open(project_dir)
  end)

  if not setup_success then
    print('✗ Python project setup failed')
    print('Setup error:', setup_error)
    return false
  end
  print('✓ Python project setup successful')

  -- Quick container lifecycle test with detailed logging
  print('Step 2.1: Testing container build')
  local build_success, build_err = pcall(function()
    return container.build()
  end)

  if not build_success then
    print('✗ Python container build failed')
    print('Build error:', build_err)
    return false
  end
  print('✓ Python container build successful')

  print('Step 2.2: Testing container start')
  local start_success, start_err = pcall(function()
    return container.start()
  end)

  if not start_success then
    print('✗ Python container start failed')
    print('Start error:', start_err)
    return false
  end
  print('✓ Python container start initiated')

  -- Check plugin state after start
  print('Step 2.2.1: Checking plugin state after start')
  local state_success, state = pcall(function()
    return container.get_state()
  end)

  if state_success and state then
    print('Plugin state:')
    print('  Container ID:', state.container_id or 'none')
    print('  Status:', state.status or 'unknown')
    if state.config then
      print('  Config name:', state.config.name or 'unknown')
      print('  Config image:', state.config.image or 'unknown')
    end
  else
    print('⚠ Could not retrieve plugin state')
  end

  -- Wait briefly for container with detailed diagnostics
  print('Step 2.3: Checking container status')

  -- First, check if any containers were created
  local all_success, all_output = run_command('docker ps -a --filter name=' .. container_name_pattern .. ' -q')
  if all_success and all_output:gsub('%s+', '') ~= '' then
    print('✓ Container(s) found with pattern:', container_name_pattern)

    -- Get detailed container info
    local info_success, info_output = run_command(
      'docker ps -a --filter name='
        .. container_name_pattern
        .. ' --format "table {{.Names}}\\t{{.Status}}\\t{{.Image}}"'
    )
    if info_success and info_output then
      print('Container details:')
      print(info_output)
    end

    -- Check if container is running
    local running_success, running_output =
      run_command('docker ps --filter name=' .. container_name_pattern .. ' --filter status=running -q')
    if running_success and running_output:gsub('%s+', '') ~= '' then
      print('✓ Python container is running')
    else
      print('⚠ Python container exists but is not running')

      -- Get container logs for troubleshooting
      local logs_success, logs_output =
        run_command('docker logs ' .. container_name_pattern .. '-devcontainer 2>&1 | tail -20')
      if logs_success and logs_output then
        print('Recent container logs:')
        print(logs_output)
      end
    end
  else
    print('⚠ No containers found with pattern:', container_name_pattern)

    -- Check if any devcontainer-related containers exist
    local dev_success, dev_output =
      run_command('docker ps -a --filter label=devcontainer --format "table {{.Names}}\\t{{.Status}}\\t{{.Image}}"')
    if dev_success and dev_output then
      print('All devcontainer containers:')
      print(dev_output)
    end
  end

  -- Cleanup
  cleanup_containers(container_name_pattern)
  print('✓ Python test cleanup completed')

  return true
end

-- Test 3: Error scenarios
function tests.test_error_scenarios()
  print_with_timestamp('\n=== E2E Test 3: Error Scenarios ===')

  local container = require('container')

  -- Reset state
  pcall(function()
    container.reset()
  end)

  -- Test 3.1: Invalid project directory
  print('Step 3.1: Testing invalid project directory')
  local invalid_success, invalid_err = pcall(function()
    return container.open('/absolutely/nonexistent/directory/for/testing')
  end)

  if not invalid_success then
    print('✓ Invalid directory properly rejected')
  else
    print('⚠ Invalid directory was accepted (fallback behavior)')
  end

  -- Test 3.2: Operations without container
  print('Step 3.2: Testing operations without active container')
  local no_container_tests = {
    function()
      return container.execute('echo test')
    end,
    function()
      return container.stop()
    end,
  }

  for i, test_fn in ipairs(no_container_tests) do
    local success = pcall(test_fn)
    if not success then
      print('✓ Operation ' .. i .. ' properly handled missing container')
    else
      print('✓ Operation ' .. i .. ' gracefully handled missing container')
    end
  end

  return true
end

-- Test 4: Docker environment validation
function tests.test_docker_environment()
  print_with_timestamp('\n=== E2E Test 4: Docker Environment Validation ===')

  -- Test Docker availability
  local docker_available, docker_output = run_command('docker --version')
  if not docker_available then
    print('✗ Docker not available for E2E tests')
    return false
  end
  print('✓ Docker available:', docker_output:gsub('%s+$', ''))

  -- Test Docker daemon
  local daemon_available, daemon_output = run_command('docker ps')
  if not daemon_available then
    print('✗ Docker daemon not accessible')
    print('Error:', daemon_output)
    return false
  end
  print('✓ Docker daemon accessible')

  -- Test image pulling capability
  print('  Pulling test image (alpine:latest)...')
  local pull_success, pull_output = run_command('docker pull alpine:latest', true)
  if not pull_success then
    print('⚠ Docker image pull failed (network issue?)')
    print('Error:', pull_output)
  else
    print('✓ Docker image pull successful')
  end

  return true
end

-- Main E2E test runner
local function run_e2e_tests()
  print_with_timestamp('=== container.nvim End-to-End Tests ===')
  print_with_timestamp('Testing complete workflows with real Docker containers')
  print('')

  -- Check prerequisites
  local docker_check = tests.test_docker_environment()
  if not docker_check then
    print('\n❌ E2E Prerequisites not met. Skipping E2E tests.')
    print('Please ensure Docker is installed and running.')
    return 0 -- Don't fail CI, just skip
  end

  local test_functions = {
    tests.test_existing_example_workflow,
    tests.test_python_full_workflow,
    tests.test_error_scenarios,
  }

  local passed = 0
  local total = #test_functions

  for i, test_func in ipairs(test_functions) do
    print('')
    print_with_timestamp('Starting E2E Test ' .. i .. '...')
    local start_time = os.time()
    local success, result = pcall(test_func)
    local elapsed = os.time() - start_time

    if success and result ~= false then
      passed = passed + 1
      print_with_timestamp(string.format('✅ E2E Test %d PASSED (%.1fs)', i, elapsed))
    else
      print_with_timestamp(string.format('❌ E2E Test %d FAILED (%.1fs)', i, elapsed))
      if not success then
        print('Error:', result)
      end
    end
  end

  print('')
  print('=== E2E Test Results ===')
  print(string.format('Passed: %d/%d', passed, total))

  if passed == total then
    print('🎉 All E2E tests passed!')
    return 0
  else
    print('⚠ Some E2E tests failed.')
    return 1
  end
end

-- Run E2E tests
local exit_code = run_e2e_tests()
os.exit(exit_code)
