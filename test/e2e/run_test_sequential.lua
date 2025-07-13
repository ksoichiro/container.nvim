#!/usr/bin/env lua

-- E2E Test Runner for container.nvim
-- Manages execution of E2E tests through nvim --headless

local function run_command(cmd, show_output)
  print('Running: ' .. cmd)

  if show_output then
    -- Use streaming output for real-time display
    local handle = io.popen(cmd .. ' 2>&1', 'r')
    local result = {}

    print('--- Test Output (Real-time) ---')
    while true do
      local line = handle:read('*l')
      if not line then
        break
      end
      print(line)
      io.stdout:flush() -- Force immediate output
      table.insert(result, line)
    end
    print('--- End Test Output ---')

    local success = handle:close()
    return success, table.concat(result, '\n')
  else
    -- Original non-streaming approach for silent commands
    local handle = io.popen(cmd .. ' 2>&1')
    local result = handle:read('*a')
    local success = handle:close()
    return success, result
  end
end

local function run_nvim_test(test_file)
  -- Use stdbuf to disable output buffering for real-time display
  local base_cmd =
    string.format('nvim --headless -u test/e2e/minimal_init.lua -c "lua dofile(\'test/e2e/%s\')" -c "qa"', test_file)

  -- Try to use stdbuf if available, otherwise fall back to normal command
  local handle = io.popen('which stdbuf >/dev/null 2>&1')
  local has_stdbuf = handle:close()
  handle = nil

  local cmd
  if has_stdbuf then
    cmd = 'stdbuf -o0 -e0 ' .. base_cmd
  else
    cmd = base_cmd
  end

  return run_command(cmd, true)
end

local function check_prerequisites()
  print('=== Checking Prerequisites ===')

  -- Check if nvim is available (try both direct command and which)
  local nvim_success = run_command('nvim --version >/dev/null 2>&1')
  if not nvim_success then
    print('❌ Error: Neovim not found. E2E tests require Neovim.')
    print('Please ensure nvim is available in your PATH.')
    return false
  end
  print('✓ Neovim available')

  -- Check if docker is available
  local docker_success = run_command('docker --version >/dev/null 2>&1')
  if not docker_success then
    print('❌ Error: Docker not found. E2E tests require Docker.')
    return false
  end
  print('✓ Docker CLI available')

  -- Check if docker daemon is running
  local daemon_success = run_command('docker ps >/dev/null 2>&1')
  if not daemon_success then
    print('❌ Error: Docker daemon not running. Please start Docker.')
    return false
  end
  print('✓ Docker daemon running')

  return true
end

-- Auto-discover test cases based on file naming convention
local function discover_test_cases()
  -- Try to load the discovery helper
  local discovery_path = 'test/e2e/helpers/test_discovery.lua'
  local discovery_module = loadfile(discovery_path)

  if discovery_module then
    local discovery = discovery_module()
    return discovery.discover_test_files()
  else
    -- Fallback: manual glob pattern discovery
    local test_files = {}
    local handle = io.popen('find test/e2e -name "test_*.lua" -type f 2>/dev/null | sort')

    if handle then
      for line in handle:lines() do
        local filename = line:match('test/e2e/(.+)$')
        if filename and not filename:match('helpers/') then
          table.insert(test_files, {
            file = filename,
            name = filename:gsub('%.lua$', ''):gsub('_', ' '):gsub('^%l', string.upper),
            description = 'E2E functionality testing',
          })
        end
      end
      handle:close()
    end

    return test_files
  end
end

local test_cases = discover_test_cases()

local function main()
  print('=== container.nvim E2E Test Runner ===')
  print('Running E2E tests with real Neovim commands and containers')
  print('')

  -- Check prerequisites
  if not check_prerequisites() then
    print('❌ Prerequisites check failed')
    os.exit(1)
  end
  print('')

  local passed = 0
  local total = 0
  local failed_tests = {}

  -- Run each test case
  for _, test_case in ipairs(test_cases) do
    total = total + 1
    print(string.format('=== Running Test Case %d: %s ===', total, test_case.name))
    print('Description: ' .. test_case.description)
    print('File: ' .. test_case.file)
    print('')

    -- Check if test file exists
    local test_file_path = 'test/e2e/' .. test_case.file
    local file = io.open(test_file_path, 'r')
    if not file then
      print('⚠ Test file not found: ' .. test_file_path)
      print('Skipping...')
      print('')
      table.insert(failed_tests, test_case.name .. ' (file not found)')
      goto continue
    end
    file:close()

    -- Run the test
    local start_time = os.time()
    print('⏳ Starting test execution...')
    local success = run_nvim_test(test_case.file)
    local elapsed = os.time() - start_time

    if success then
      passed = passed + 1
      print(string.format('✅ %s PASSED (%.1fs)', test_case.name, elapsed))
    else
      print(string.format('❌ %s FAILED (%.1fs)', test_case.name, elapsed))
      table.insert(failed_tests, test_case.name)
    end
    print('')

    ::continue::
  end

  -- Print summary
  print('=== E2E Test Summary ===')
  print(string.format('Total tests: %d', total))
  print(string.format('Passed: %d', passed))
  print(string.format('Failed: %d', total - passed))

  if #failed_tests > 0 then
    print('')
    print('Failed tests:')
    for _, test_name in ipairs(failed_tests) do
      print('  - ' .. test_name)
    end
  end
  print('')

  if passed == total then
    print('🎉 All E2E tests passed!')
    os.exit(0)
  else
    print('⚠ Some E2E tests failed.')
    os.exit(1)
  end
end

-- Run the test runner
main()
