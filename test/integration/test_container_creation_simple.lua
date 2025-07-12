#!/usr/bin/env lua

-- Simple Container Creation Test for container.nvim
-- Quick verification that containers are actually created

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

local function cleanup_containers()
  print('Cleaning up any existing test containers...')
  run_command('docker ps -a --filter name=container-nvim-test -q | xargs -r docker rm -f')
end

local function create_simple_test_project()
  local test_dir = '/tmp/container-nvim-simple-test'

  -- Clean and create test directory
  os.execute('rm -rf ' .. test_dir)
  os.execute('mkdir -p ' .. test_dir .. '/.devcontainer')

  -- Create minimal devcontainer.json with simple Alpine image
  local devcontainer_config = [[{
  "name": "Simple Test Container",
  "image": "alpine:latest",
  "workspaceFolder": "/workspace"
}]]

  local file = io.open(test_dir .. '/.devcontainer/devcontainer.json', 'w')
  file:write(devcontainer_config)
  file:close()

  print('✓ Simple test project created at:', test_dir)
  return test_dir
end

print('=== container.nvim Simple Container Creation Test ===')
print('Testing if container.start() actually creates Docker containers')
print('')

-- Check Docker availability
local docker_available, docker_output = run_command('docker --version')
if not docker_available then
  print('❌ Docker not available. Skipping test.')
  os.exit(0)
end
print('✓ Docker available:', docker_output:gsub('%s+$', ''))

-- Cleanup any existing containers
cleanup_containers()

-- Create test project
local test_project = create_simple_test_project()

-- Initialize plugin
local container = require('container')

print('Step 1: Setting up plugin...')
local setup_success = pcall(function()
  container.setup({
    log_level = 'debug',
    docker = { timeout = 30000 }, -- 30 seconds
  })
end)

if not setup_success then
  print('✗ Plugin setup failed')
  os.exit(1)
end
print('✓ Plugin setup successful')

print('Step 2: Opening test project...')
local open_success = pcall(function()
  return container.open(test_project)
end)

if not open_success then
  print('✗ Failed to open test project')
  os.exit(1)
end
print('✓ Test project opened')

print('Step 3: Checking current Docker containers...')
local before_success, before_containers =
  run_command('docker ps -a --format "{{.Names}}" | grep -E "(container-nvim|test)" || echo "No test containers"')
print('Before container creation:', before_containers:gsub('%s+$', ''))

print('Step 4: Starting container (this should create a Docker container)...')
local start_success = pcall(function()
  return container.start()
end)

if not start_success then
  print('✗ Container start failed')
else
  print('✓ Container start command completed')
end

print('Step 5: Checking Docker containers after start...')
-- Wait a moment for container creation
os.execute('sleep 5')

local after_success, after_containers =
  run_command('docker ps -a --format "{{.Names}}" | grep -E "(container-nvim|test)" || echo "No test containers"')
print('After container creation:', after_containers:gsub('%s+$', ''))

-- Check specifically for any new containers
local all_containers_success, all_containers =
  run_command('docker ps -a --format "{{.Names}}\\t{{.Image}}\\t{{.Status}}"')
if all_containers_success then
  print('')
  print('All current Docker containers:')
  print(all_containers)
end

print('Step 6: Checking plugin state...')
local state = container.get_state()
if state then
  print('Plugin state available')
  -- Print some basic state info if available
else
  print('No plugin state available')
end

-- Cleanup
print('Step 7: Cleanup...')
pcall(function()
  container.stop()
end)
cleanup_containers()
os.execute('rm -rf ' .. test_project)

print('')
print('=== Test Complete ===')
print('Check the output above to see if any Docker containers were created.')
print('If containers were created, the plugin is working correctly.')
print('If no containers appeared, there may be an issue with container creation.')
