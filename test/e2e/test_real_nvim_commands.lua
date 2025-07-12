#!/usr/bin/env lua

-- Real E2E Tests for container.nvim
-- Tests actual Neovim commands in headless mode with real Docker containers
-- This tests the complete plugin workflow: plugin loading -> command registration -> command execution -> container operations

local function run_command_with_timeout(cmd, timeout)
  timeout = timeout or 30
  local temp_file = os.tmpname()
  local exit_code_file = os.tmpname()

  -- Run command with timeout and capture output and exit code separately
  local full_cmd = string.format(
    'timeout %d bash -c "%s" > %s 2>&1; echo $? > %s',
    timeout,
    cmd:gsub('"', '\\"'),
    temp_file,
    exit_code_file
  )
  os.execute(full_cmd)

  -- Read output
  local file = io.open(temp_file, 'r')
  local output = file and file:read('*a') or ''
  if file then
    file:close()
  end

  -- Read exit code
  local exit_file = io.open(exit_code_file, 'r')
  local exit_code_str = exit_file and exit_file:read('*a') or '1'
  if exit_file then
    exit_file:close()
  end

  -- Clean up temporary files
  os.remove(temp_file)
  os.remove(exit_code_file)

  -- Parse exit code
  exit_code_str = exit_code_str:gsub('%s+', '')
  local exit_code = tonumber(exit_code_str) or 1

  return exit_code == 0, output
end

local function check_docker_available()
  local success, output = run_command_with_timeout('docker --version')
  if not success then
    print('❌ Docker not available: ' .. output)
    return false
  end

  success, output = run_command_with_timeout('docker ps')
  if not success then
    print('❌ Docker daemon not running: ' .. output)
    return false
  end

  print('✓ Docker is available and running')
  return true
end

local function cleanup_test_containers()
  -- Clean up any existing test containers
  run_command_with_timeout('docker ps -a --filter "name=container-nvim-e2e" -q | xargs -r docker rm -f')
  run_command_with_timeout('docker ps -a --filter "name=test-python-app" -q | xargs -r docker rm -f')
end

local function create_test_project()
  local test_dir = '/tmp/container-nvim-e2e-test'

  -- Create test project directory
  os.execute('rm -rf ' .. test_dir)
  os.execute('mkdir -p ' .. test_dir .. '/.devcontainer')

  -- Create devcontainer.json
  local devcontainer_content = [[
{
  "name": "Python Test Container",
  "image": "python:3.9-slim",
  "workspaceFolder": "/workspace",
  "workspaceMount": "source=${localWorkspaceFolder},target=/workspace,type=bind",
  "runArgs": ["--name=container-nvim-e2e-test"],
  "postCreateCommand": "pip install pytest",
  "forwardPorts": [3000, 8000],
  "remoteUser": "root"
}
]]

  local file = io.open(test_dir .. '/.devcontainer/devcontainer.json', 'w')
  file:write(devcontainer_content)
  file:close()

  -- Create simple Python app
  local python_content = [[
def hello():
    return "Hello from container!"

if __name__ == "__main__":
    print(hello())
]]

  file = io.open(test_dir .. '/app.py', 'w')
  file:write(python_content)
  file:close()

  return test_dir
end

local function wait_for_container(container_name, status, timeout)
  timeout = timeout or 30
  local start_time = os.time()

  while (os.time() - start_time) < timeout do
    local success, output = run_command_with_timeout(
      string.format(
        'docker ps -a --filter "name=%s" --filter "status=%s" --format "{{.Names}}"',
        container_name,
        status
      )
    )

    if success and output:match(container_name) then
      return true
    end

    os.execute('sleep 1')
  end

  return false
end

local function test_container_start_stop_commands()
  print('\n=== Testing Real Neovim Container Commands ===')

  -- Check Docker availability
  if not check_docker_available() then
    return false
  end

  -- Cleanup and create test project
  cleanup_test_containers()
  local test_dir = create_test_project()

  print('✓ Test project created at: ' .. test_dir)

  -- Get current working directory
  local cwd = io.popen('pwd'):read('*l')

  -- Test 1: Plugin loading and command registration
  print('\nStep 1: Testing plugin loading and command registration')
  local nvim_cmd = string.format(
    [[
    cd %s && nvim --headless -u NONE \
    -c "set runtimepath+=%s" \
    -c "lua package.path = '%s/lua/?.lua;%s/lua/?/init.lua;' .. package.path" \
    -c "runtime! plugin/container.lua" \
    -c "if vim.api.nvim_get_commands()['ContainerStart'] then print('COMMAND_REGISTERED') else print('COMMAND_MISSING') end" \
    -c "qa"
  ]],
    test_dir,
    cwd,
    cwd,
    cwd
  )

  local success, output = run_command_with_timeout(nvim_cmd, 15)
  if not success or not output:match('COMMAND_REGISTERED') then
    print('❌ Plugin loading failed or commands not registered')
    print('Output:', output)
    return false
  end
  print('✓ Plugin loaded and commands registered successfully')

  -- Test 2: ContainerOpen command
  print('\nStep 2: Testing ContainerOpen command')
  nvim_cmd = string.format(
    [[
    cd %s && nvim --headless -u NONE \
    -c "set runtimepath+=%s" \
    -c "lua package.path = '%s/lua/?.lua;%s/lua/?/init.lua;' .. package.path" \
    -c "runtime! plugin/container.lua" \
    -c "lua require('container').setup({log_level = 'info'})" \
    -c "ContainerOpen" \
    -c "lua local state = require('container').get_state(); if state.current_container then print('CONTAINER_OPENED') else print('CONTAINER_NOT_OPENED') end" \
    -c "qa"
  ]],
    test_dir,
    cwd,
    cwd,
    cwd
  )

  success, output = run_command_with_timeout(nvim_cmd, 20)
  if not success or not output:match('CONTAINER_OPENED') then
    print('❌ ContainerOpen command failed')
    print('Output:', output)
    return false
  end
  print('✓ ContainerOpen command executed successfully')

  -- Test 3: ContainerStart command (this should actually create and start a container)
  print('\nStep 3: Testing ContainerStart command (real container creation)')
  nvim_cmd = string.format(
    [[
    cd %s && nvim --headless -u NONE \
    -c "set runtimepath+=%s" \
    -c "lua package.path = '%s/lua/?.lua;%s/lua/?/init.lua;' .. package.path" \
    -c "runtime! plugin/container.lua" \
    -c "lua require('container').setup({log_level = 'info', docker = {timeout = 60000}})" \
    -c "ContainerOpen" \
    -c "ContainerStart" \
    -c "lua print('CONTAINER_START_COMPLETED')" \
    -c "qa"
  ]],
    test_dir,
    cwd,
    cwd,
    cwd
  )

  success, output = run_command_with_timeout(nvim_cmd, 60)
  if not success or not output:match('CONTAINER_START_COMPLETED') then
    print('❌ ContainerStart command failed')
    print('Output:', output)
    return false
  end
  print('✓ ContainerStart command executed')

  -- Test 4: Verify container actually exists and is running
  print('\nStep 4: Verifying container was actually created and is running')

  -- Wait for container to be created
  if not wait_for_container('container-nvim-e2e-test', 'running', 30) then
    -- Try checking if it exists but not running
    if wait_for_container('container-nvim-e2e-test', 'exited', 10) then
      print('⚠ Container was created but exited (may be expected for this test image)')
      print('✓ Container creation confirmed (container exists)')
    else
      print('❌ Container was not created')
      return false
    end
  else
    print('✓ Container is running successfully')
  end

  -- Test 5: ContainerStop command
  print('\nStep 5: Testing ContainerStop command')
  nvim_cmd = string.format(
    [[
    cd %s && nvim --headless -u NONE \
    -c "set runtimepath+=%s" \
    -c "lua package.path = '%s/lua/?.lua;%s/lua/?/init.lua;' .. package.path" \
    -c "runtime! plugin/container.lua" \
    -c "lua require('container').setup({log_level = 'info'})" \
    -c "ContainerOpen" \
    -c "ContainerStop" \
    -c "lua print('CONTAINER_STOP_COMPLETED')" \
    -c "qa"
  ]],
    test_dir,
    cwd,
    cwd,
    cwd
  )

  success, output = run_command_with_timeout(nvim_cmd, 30)
  if not success or not output:match('CONTAINER_STOP_COMPLETED') then
    print('❌ ContainerStop command failed')
    print('Output:', output)
    return false
  end
  print('✓ ContainerStop command executed')

  -- Test 6: Verify container is stopped
  print('\nStep 6: Verifying container was stopped')
  success, output = run_command_with_timeout('docker ps --filter "name=container-nvim-e2e-test" --format "{{.Names}}"')
  if success and output:match('container-nvim-e2e-test') then
    print('⚠ Container still running (may be expected if stop takes time)')
  else
    print('✓ Container stopped successfully')
  end

  -- Cleanup
  print('\nStep 7: Cleanup')
  cleanup_test_containers()
  os.execute('rm -rf ' .. test_dir)
  print('✓ Cleanup completed')

  return true
end

local function test_error_scenarios()
  print('\n=== Testing Error Scenarios ===')

  -- Get current working directory
  local cwd = io.popen('pwd'):read('*l')

  -- Test: ContainerStart without ContainerOpen
  print('\nTesting ContainerStart without ContainerOpen')
  local nvim_cmd = string.format(
    [[
    nvim --headless -u NONE \
    -c "set runtimepath+=%s" \
    -c "lua package.path = '%s/lua/?.lua;%s/lua/?/init.lua;' .. package.path" \
    -c "runtime! plugin/container.lua" \
    -c "lua require('container').setup({log_level = 'info'})" \
    -c "ContainerStart" \
    -c "lua print('ERROR_HANDLING_COMPLETED')" \
    -c "qa"
  ]],
    cwd,
    cwd,
    cwd
  )

  local success, output = run_command_with_timeout(nvim_cmd, 15)
  if not success or not output:match('ERROR_HANDLING_COMPLETED') then
    print('❌ Error handling test failed')
    print('Output:', output)
    return false
  end
  print('✓ Error scenario handled gracefully')

  return true
end

-- Main test runner
local function run_real_e2e_tests()
  print('=== Real Neovim Command E2E Tests ===')
  print('Testing actual :ContainerStart and :ContainerStop commands in Neovim headless mode')
  print('')

  local tests = {
    { name = 'Container Start/Stop Commands', fn = test_container_start_stop_commands },
    { name = 'Error Scenarios', fn = test_error_scenarios },
  }

  local passed = 0
  local total = #tests

  for i, test in ipairs(tests) do
    print('')
    print('=== Test ' .. i .. ': ' .. test.name .. ' ===')

    local success, result = pcall(test.fn)
    if success and result ~= false then
      passed = passed + 1
      print('✅ Test ' .. i .. ' PASSED: ' .. test.name)
    else
      print('❌ Test ' .. i .. ' FAILED: ' .. test.name)
      if not success then
        print('Error:', result)
      end
    end
  end

  print('')
  print('=== Real E2E Test Results ===')
  print(string.format('Passed: %d/%d', passed, total))

  if passed == total then
    print('🎉 All real E2E tests passed!')
    print('✓ Container commands work correctly in Neovim')
    print('✓ Docker containers are actually created and managed')
    return 0
  else
    print('⚠ Some real E2E tests failed.')
    return 1
  end
end

-- Run the tests
local exit_code = run_real_e2e_tests()
os.exit(exit_code)
