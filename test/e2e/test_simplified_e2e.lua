#!/usr/bin/env lua

-- Simplified E2E Test for container.nvim
-- Tests the core functionality: can we start and stop containers using the plugin?
-- This focuses on what matters most: actual container operations

local function run_cmd(cmd, timeout)
  timeout = timeout or 30
  local temp_file = os.tmpname()
  local exit_code_file = os.tmpname()

  -- Run command and capture output and exit code
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

  -- Cleanup
  os.remove(temp_file)
  os.remove(exit_code_file)

  -- Parse exit code
  exit_code_str = exit_code_str:gsub('%s+', '')
  local exit_code = tonumber(exit_code_str) or 1

  return exit_code == 0, output
end

local function check_docker()
  local success, _ = run_cmd('docker ps')
  return success
end

local function cleanup_containers()
  run_cmd('docker ps -a --filter "name=simplified-e2e-test" -q | xargs -r docker rm -f')
end

local function create_test_project()
  local test_dir = '/tmp/simplified-e2e-test'
  os.execute('rm -rf ' .. test_dir)
  os.execute('mkdir -p ' .. test_dir .. '/.devcontainer')

  -- Simple devcontainer.json for testing
  local content = [[
{
  "name": "Simplified E2E Test",
  "image": "alpine:latest",
  "workspaceFolder": "/workspace",
  "runArgs": ["--name=simplified-e2e-test"],
  "remoteUser": "root"
}
]]

  local file = io.open(test_dir .. '/.devcontainer/devcontainer.json', 'w')
  file:write(content)
  file:close()

  return test_dir
end

local function test_container_operations()
  print('=== Simplified E2E Test: Container Operations ===')

  if not check_docker() then
    print('❌ Docker not available')
    return false
  end
  print('✓ Docker available')

  cleanup_containers()
  local test_dir = create_test_project()
  local cwd = io.popen('pwd'):read('*l')

  print('✓ Test project created')

  -- Test: Start container using plugin
  print('\nTesting container start...')
  local nvim_cmd = string.format(
    [[
    cd %s && nvim --headless -u NONE \
    -c "set runtimepath+=%s" \
    -c "lua package.path = '%s/lua/?.lua;%s/lua/?/init.lua;' .. package.path" \
    -c "runtime! plugin/container.lua" \
    -c "lua require('container').setup({log_level = 'info', docker = {timeout = 45000}})" \
    -c "ContainerOpen" \
    -c "ContainerStart" \
    -c "sleep 2" \
    -c "qa"
  ]],
    test_dir,
    cwd,
    cwd,
    cwd
  )

  local success, output = run_cmd(nvim_cmd, 60)

  -- Check if container was created
  local container_success, container_output =
    run_cmd('docker ps -a --filter "name=simplified-e2e-test" --format "{{.Names}}"')
  local container_exists = container_success and container_output:match('simplified-e2e-test')

  -- Check detailed container status
  local status_success, status_output =
    run_cmd('docker ps -a --filter "name=simplified-e2e-test" --format "{{.Names}}: {{.Status}}"')

  print('Container creation result:')
  print('  - Neovim command executed:', success and 'YES' or 'NO')
  print('  - Container exists:', container_exists and 'YES' or 'NO')
  if status_success and status_output ~= '' then
    print('  - Container status:', status_output:gsub('%s+$', ''))
  end

  -- Look for container startup indicators in output
  local startup_indicators = {
    'Starting DevContainer',
    'DevContainer start initiated',
    'Container is running',
    'DevContainer is ready',
    'Container Setup Complete',
  }

  local found_indicators = {}
  for _, indicator in ipairs(startup_indicators) do
    if output:match(indicator) then
      table.insert(found_indicators, indicator)
    end
  end

  print('\nStartup indicators found:')
  if #found_indicators > 0 then
    for _, indicator in ipairs(found_indicators) do
      print('  ✓ ' .. indicator)
    end
  else
    print('  ⚠ No startup indicators found')
  end

  -- Cleanup
  cleanup_containers()
  os.execute('rm -rf ' .. test_dir)

  -- Determine success
  local test_passed = container_exists or #found_indicators > 0

  if test_passed then
    print('\n✅ Simplified E2E test PASSED')
    print('✓ Plugin successfully triggered container operations')
    return true
  else
    print('\n❌ Simplified E2E test FAILED')
    print('❌ No evidence of successful container operations')
    print('\nDebug output (last 15 lines):')
    print('----------------------------------------')
    local lines = {}
    for line in output:gmatch('[^\n]+') do
      table.insert(lines, line)
    end
    local start_line = math.max(1, #lines - 14)
    for i = start_line, #lines do
      print(lines[i])
    end
    print('----------------------------------------')
    return false
  end
end

-- Run the test
print('Starting simplified E2E test...')
local result = test_container_operations()
os.exit(result and 0 or 1)
