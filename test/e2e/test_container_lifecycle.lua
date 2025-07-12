#!/usr/bin/env lua

-- Container Lifecycle E2E Test
-- Focused test for container start/stop functionality
-- This is a streamlined test for daily development workflow

local function run_cmd(cmd, timeout)
  timeout = timeout or 15
  local temp_file = os.tmpname()
  local exit_code_file = os.tmpname()

  -- Capture both stdout and stderr, and exit code
  local full_cmd = string.format('(%s) > %s 2>&1; echo $? > %s', cmd, temp_file, exit_code_file)
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

  -- Clean and parse exit code
  exit_code_str = exit_code_str:gsub('%s+', '')
  local exit_code = tonumber(exit_code_str) or 1

  -- Cleanup
  os.remove(temp_file)
  os.remove(exit_code_file)

  return exit_code == 0, output
end

local function check_docker()
  local success, _ = run_cmd('docker ps')
  return success
end

local function cleanup_containers()
  print('Cleaning up test containers...')

  -- Stop and remove containers with test names
  local cleanup_patterns = {
    'test-container-lifecycle',
    'lifecycle-test',
    'container-lifecycle-test',
  }

  for _, pattern in ipairs(cleanup_patterns) do
    local success, output = run_cmd(string.format('docker ps -a --filter "name=%s" -q', pattern))
    if success and output:gsub('%s+', '') ~= '' then
      print('  - Removing containers matching: ' .. pattern)
      run_cmd(string.format('docker ps -a --filter "name=%s" -q | xargs -r docker rm -f', pattern))
    end
  end

  print('✓ Container cleanup completed')
end

local function create_minimal_project()
  local test_dir = '/tmp/container-lifecycle-test'
  os.execute('rm -rf ' .. test_dir)
  os.execute('mkdir -p ' .. test_dir .. '/.devcontainer')

  -- Minimal devcontainer.json for quick testing
  local content = [[
{
  "name": "Lifecycle Test",
  "image": "alpine:latest",
  "workspaceFolder": "/workspace",
  "runArgs": ["--name=test-container-lifecycle"],
  "postCreateCommand": "echo 'Container ready'",
  "remoteUser": "root"
}
]]

  local file = io.open(test_dir .. '/.devcontainer/devcontainer.json', 'w')
  file:write(content)
  file:close()

  return test_dir
end

local function test_basic_lifecycle()
  print('=== Container Lifecycle Test ===')

  if not check_docker() then
    print('❌ Docker not available')
    return false
  end

  cleanup_containers()
  local test_dir = create_minimal_project()

  -- Get current working directory
  local cwd = io.popen('pwd'):read('*l')

  -- Test container start
  print('Testing container lifecycle...')
  local nvim_cmd = string.format(
    [[
    cd %s && timeout 45 nvim --headless -u NONE \
    -c "set runtimepath+=%s" \
    -c "lua package.path = '%s/lua/?.lua;%s/lua/?/init.lua;' .. package.path" \
    -c "runtime! plugin/container.lua" \
    -c "lua require('container').setup({log_level = 'info', docker = {timeout = 30000}})" \
    -c "ContainerOpen" \
    -c "ContainerStart" \
    -c "sleep 2" \
    -c "ContainerStop" \
    -c "echo 'LIFECYCLE_COMPLETED'" \
    -c "qa"
  ]],
    test_dir,
    cwd,
    cwd,
    cwd
  )

  local success, output = run_cmd(nvim_cmd)

  -- Wait a moment for any async operations to complete
  print('Waiting for container operations to complete...')
  os.execute('sleep 2')

  -- Force cleanup all related containers
  print('Performing final cleanup...')
  cleanup_containers()

  -- Also clean up any containers created with devcontainer naming pattern
  print('  - Cleaning devcontainer-labeled containers...')
  local devcontainer_cleanup =
    run_cmd('docker ps -a --filter "label=devcontainer.local_folder" -q | xargs -r docker rm -f')

  print('  - Cleaning any remaining lifecycle-related containers...')
  local generic_cleanup = run_cmd('docker ps -a --filter "name=lifecycle" -q | xargs -r docker rm -f')

  -- Additional cleanup for containers that might have different naming patterns
  local additional_patterns = {
    'tmp.*lifecycle',
    '.*lifecycle.*test.*',
    '.*devcontainer.*',
  }

  for _, pattern in ipairs(additional_patterns) do
    run_cmd(string.format('docker ps -a --filter "name=%s" -q | xargs -r docker rm -f', pattern))
  end

  -- Clean up test directory
  os.execute('rm -rf ' .. test_dir)
  print('✓ Test cleanup completed')

  -- Check for container lifecycle indicators in the output
  local container_started = output:match('Starting DevContainer') or output:match('Container is running')
  local container_ready = output:match('DevContainer is ready') or output:match('Container Setup Complete')
  local lifecycle_marker = output:match('LIFECYCLE_COMPLETED')

  if container_started and (container_ready or lifecycle_marker) then
    print('✅ Container lifecycle test PASSED')
    print('✓ Container was created and started successfully')
    if container_ready then
      print('✓ Container setup completed successfully')
    end
    return true
  else
    print('❌ Container lifecycle test FAILED')
    print('Expected container startup indicators in output')
    if output and output ~= '' then
      print('Checking output for indicators:')
      print('  - Container started:', container_started and 'YES' or 'NO')
      print('  - Container ready:', container_ready and 'YES' or 'NO')
      print('  - Lifecycle marker:', lifecycle_marker and 'YES' or 'NO')
      print('')
      print('Full output (last 20 lines):')
      print('----------------------------------------')
      local lines = {}
      for line in output:gmatch('[^\n]+') do
        table.insert(lines, line)
      end
      local start_line = math.max(1, #lines - 19)
      for i = start_line, #lines do
        print(lines[i])
      end
      print('----------------------------------------')
    else
      print('No output received from Neovim command')
    end
    return false
  end
end

-- Run the test
print('Starting container lifecycle test...')
local result = test_basic_lifecycle()
os.exit(result and 0 or 1)
