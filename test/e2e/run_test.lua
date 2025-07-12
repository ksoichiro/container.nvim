#!/usr/bin/env lua

-- E2E Test Runner for container.nvim
-- Manages execution of E2E tests through nvim --headless

local function run_command(cmd)
  print('Running: ' .. cmd)
  local handle = io.popen(cmd .. ' 2>&1')
  local result = handle:read('*a')
  local success = handle:close()
  return success
end

local function run_nvim_test(test_file)
  local cmd = string.format('nvim --headless -u NONE -c "lua dofile(\'test/e2e/%s\')" -c "qa"', test_file)
  return run_command(cmd)
end

local function check_prerequisites()
  print('=== Checking Prerequisites ===')

  -- Check if nvim is available (try both direct command and which)
  if not run_command('nvim --version >/dev/null 2>&1') then
    print('❌ Error: Neovim not found. E2E tests require Neovim.')
    print('Please ensure nvim is available in your PATH.')
    return false
  end
  print('✓ Neovim available')

  -- Check if docker is available
  if not run_command('docker --version >/dev/null 2>&1') then
    print('❌ Error: Docker not found. E2E tests require Docker.')
    return false
  end
  print('✓ Docker CLI available')

  -- Check if docker daemon is running
  if not run_command('docker ps >/dev/null 2>&1') then
    print('❌ Error: Docker daemon not running. Please start Docker.')
    return false
  end
  print('✓ Docker daemon running')

  return true
end

-- Define test cases to run
local test_cases = {
  {
    file = 'test_essential_e2e.lua',
    name = 'Essential E2E Tests',
    description = 'Core functionality verification',
  },
  {
    file = 'test_container_lifecycle.lua',
    name = 'Container Lifecycle Tests',
    description = 'Container creation, management, and cleanup',
  },
  {
    file = 'test_full_workflow.lua',
    name = 'Full Workflow Tests',
    description = 'Complete development workflow scenarios',
  },
}

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
    local success = run_nvim_test(test_case.file)
    if success then
      passed = passed + 1
      print('✅ ' .. test_case.name .. ' PASSED')
    else
      print('❌ ' .. test_case.name .. ' FAILED')
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
