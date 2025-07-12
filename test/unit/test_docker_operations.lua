#!/usr/bin/env lua

-- Unit Tests for Docker Operations
-- Tests specific Docker command building and execution logic

package.path = './test/helpers/?.lua;./lua/?.lua;./lua/?/init.lua;' .. package.path

local helpers = require('init')
helpers.setup_vim_mock()
helpers.setup_lua_path()

local tests = {}

-- Test Docker module initialization
function tests.test_docker_module_init()
  print('=== Docker Module Initialization Test ===')

  local success, docker = pcall(require, 'container.docker')
  if not success then
    print('✗ Failed to load docker module:', docker)
    return false
  end

  print('✓ Docker module loaded successfully')

  -- Check essential functions exist
  local required_functions = {
    'check_docker_availability',
    'run_docker_command',
    'create_container_async',
    'start_container_async',
    'generate_container_name',
    'prepare_image',
  }

  for _, func_name in ipairs(required_functions) do
    if type(docker[func_name]) ~= 'function' then
      print('✗ Missing required function:', func_name)
      return false
    end
  end

  print('✓ All required functions present')
  return true
end

-- Test container name generation
function tests.test_container_name_generation()
  print('\n=== Container Name Generation Test ===')

  local docker = require('container.docker')

  local test_configs = {
    {
      name = 'test-project',
      base_path = '/path/to/project',
      expected_pattern = 'test%-project%-[a-f0-9]+%-devcontainer',
    },
    {
      name = 'My Project With Spaces',
      base_path = '/another/path',
      expected_pattern = 'my%-project%-with%-spaces%-[a-f0-9]+%-devcontainer',
    },
    {
      name = 'project_with_underscores',
      base_path = '/test/path',
      expected_pattern = 'project_with_underscores%-[a-f0-9]+%-devcontainer',
    },
  }

  for i, config in ipairs(test_configs) do
    local container_name = docker.generate_container_name(config)

    if container_name:match(config.expected_pattern) then
      print('✓ Test', i, 'container name generation:', container_name)
    else
      print('✗ Test', i, 'failed. Expected pattern:', config.expected_pattern)
      print('  Got:', container_name)
      return false
    end
  end

  -- Test uniqueness for same name, different paths
  local config1 = { name = 'same-name', base_path = '/path1' }
  local config2 = { name = 'same-name', base_path = '/path2' }

  local name1 = docker.generate_container_name(config1)
  local name2 = docker.generate_container_name(config2)

  if name1 ~= name2 then
    print('✓ Different paths generate unique names')
  else
    print('✗ Same names generated for different paths')
    return false
  end

  return true
end

-- Test Docker command argument building
function tests.test_docker_command_building()
  print('\n=== Docker Command Building Test ===')

  local docker = require('container.docker')

  -- Test create command arguments
  local test_config = {
    name = 'test-container',
    base_path = '/test/path',
    image = 'alpine:latest',
    workspace_folder = '/workspace',
    environment = {
      NODE_ENV = 'development',
      DEBUG = 'true',
    },
    ports = {
      { host_port = 3000, container_port = 3000 },
      { host_port = 8080, container_port = 80 },
    },
    mounts = {
      {
        type = 'bind',
        source = '/host/path',
        target = '/container/path',
        readonly = false,
      },
    },
    remote_user = 'vscode',
    privileged = false,
    init = true,
  }

  local args = docker._build_create_args(test_config)

  -- Check required arguments are present
  local required_checks = {
    { pattern = 'create', description = 'create command' },
    { pattern = '--name', description = 'container name flag' },
    { pattern = '-it', description = 'interactive mode' },
    { pattern = '-w', description = 'working directory flag' },
    { pattern = '/workspace', description = 'working directory value' },
    { pattern = '-e', description = 'environment variable flag' },
    { pattern = 'NODE_ENV=development', description = 'environment variable' },
    { pattern = '-p', description = 'port mapping flag' },
    { pattern = '3000:3000', description = 'port mapping' },
    { pattern = '--mount', description = 'mount flag' },
    { pattern = '--user', description = 'user flag' },
    { pattern = 'vscode', description = 'user value' },
    { pattern = '--init', description = 'init flag' },
    { pattern = 'alpine:latest', description = 'image name' },
  }

  local args_string = table.concat(args, ' ')
  print('Generated command args:', args_string)

  for _, check in ipairs(required_checks) do
    if not args_string:find(check.pattern, 1, true) then
      print('✗ Missing required argument:', check.description, '(' .. check.pattern .. ')')
      return false
    end
  end

  print('✓ All required arguments present in create command')

  -- Test that privileged mode is not added when false
  if args_string:find('--privileged', 1, true) then
    print('✗ Privileged flag should not be present when disabled')
    return false
  end
  print('✓ Privileged flag correctly omitted')

  return true
end

-- Test shell detection logic
function tests.test_shell_detection()
  print('\n=== Shell Detection Test ===')

  local docker = require('container.docker')

  -- Test shell detection function exists
  if type(docker.detect_shell) ~= 'function' then
    print('✗ detect_shell function not available')
    return false
  end

  -- Test cache clearing function
  if type(docker.clear_shell_cache) ~= 'function' then
    print('✗ clear_shell_cache function not available')
    return false
  end

  print('✓ Shell detection functions available')

  -- We can't easily test actual shell detection without a running container
  -- But we can test the cache clearing functionality
  docker.clear_shell_cache() -- Should not error
  print('✓ Shell cache clearing works')

  return true
end

-- Test Docker command execution (dry run)
function tests.test_docker_command_execution_dry()
  print('\n=== Docker Command Execution (Dry Run) Test ===')

  local docker = require('container.docker')

  -- Test sync command execution with safe command
  local test_commands = {
    { args = { '--version' }, description = 'version check' },
    { args = { 'images', '--help' }, description = 'images help' },
  }

  for _, cmd in ipairs(test_commands) do
    local result = docker.run_docker_command(cmd.args)

    if type(result) == 'table' and type(result.success) == 'boolean' then
      print('✓', cmd.description, 'command structure correct')
    else
      print('✗', cmd.description, 'command returned invalid structure')
      return false
    end
  end

  return true
end

-- Test image operations (mock)
function tests.test_image_operations()
  print('\n=== Image Operations Test ===')

  local docker = require('container.docker')

  -- Test image existence check structure
  if type(docker.check_image_exists) ~= 'function' then
    print('✗ check_image_exists function missing')
    return false
  end

  if type(docker.check_image_exists_async) ~= 'function' then
    print('✗ check_image_exists_async function missing')
    return false
  end

  print('✓ Image operation functions present')

  -- Test prepare_image function exists and has correct structure
  if type(docker.prepare_image) ~= 'function' then
    print('✗ prepare_image function missing')
    return false
  end

  print('✓ prepare_image function present')

  return true
end

-- Test container operations (mock)
function tests.test_container_operations()
  print('\n=== Container Operations Test ===')

  local docker = require('container.docker')

  local required_container_functions = {
    'create_container_async',
    'start_container_async',
    'stop_container_async',
    'remove_container_async',
    'exec_command_async',
    'get_container_status',
    'get_container_info',
    'list_containers',
  }

  for _, func_name in ipairs(required_container_functions) do
    if type(docker[func_name]) ~= 'function' then
      print('✗ Missing container function:', func_name)
      return false
    end
  end

  print('✓ All container operation functions present')

  return true
end

-- Main test runner
local function run_docker_unit_tests()
  print('=== Docker Operations Unit Tests ===')
  print('Testing Docker command building and logic without actual containers')
  print('')

  local test_functions = {
    tests.test_docker_module_init,
    tests.test_container_name_generation,
    tests.test_docker_command_building,
    tests.test_shell_detection,
    tests.test_docker_command_execution_dry,
    tests.test_image_operations,
    tests.test_container_operations,
  }

  local passed = 0
  local total = #test_functions

  for i, test_func in ipairs(test_functions) do
    local success, result = pcall(test_func)
    if success and result ~= false then
      passed = passed + 1
      print('✅ Unit Test', i, 'PASSED')
    else
      print('❌ Unit Test', i, 'FAILED')
      if not success then
        print('Error:', result)
      end
    end
    print('')
  end

  print('=== Docker Unit Test Results ===')
  print(string.format('Passed: %d/%d', passed, total))

  if passed == total then
    print('🎉 All Docker unit tests passed!')
    return 0
  else
    print('⚠ Some Docker unit tests failed.')
    return 1
  end
end

-- Run tests
local exit_code = run_docker_unit_tests()
os.exit(exit_code)
