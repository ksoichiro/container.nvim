#!/usr/bin/env lua

-- test/run_async_tests.lua
-- Test runner for all async utility tests
-- Provides unified execution and reporting for async module test coverage

-- Add project lua directory to package path
package.path = './lua/?.lua;./lua/?/init.lua;' .. package.path

-- Test configuration
local TEST_SUITES = {
  {
    name = 'Unit Tests (Comprehensive)',
    file = 'test/unit/test_async_comprehensive.lua',
    description = 'Comprehensive unit tests with mocked dependencies',
    requires_neovim = false,
  },
  {
    name = 'Unit Tests (Error Scenarios)',
    file = 'test/unit/test_async_error_scenarios.lua',
    description = 'Error handling and edge case unit tests',
    requires_neovim = false,
  },
  {
    name = 'Integration Tests (Real Operations)',
    file = 'test/integration/test_async_real_operations.lua',
    description = 'Integration tests with real file system and commands',
    requires_neovim = true,
  },
  {
    name = 'Integration Tests (Performance)',
    file = 'test/integration/test_async_performance.lua',
    description = 'Performance and stress tests',
    requires_neovim = true,
  },
}

-- Color codes for output
local COLORS = {
  GREEN = '\27[32m',
  RED = '\27[31m',
  YELLOW = '\27[33m',
  BLUE = '\27[34m',
  RESET = '\27[0m',
  BOLD = '\27[1m',
}

-- Helper to check if running in Neovim
local function is_neovim_environment()
  return vim and vim.loop and vim.fn and vim.api
end

-- Helper to run unit tests (non-Neovim)
local function run_unit_test(test_file)
  local success, test_module = pcall(require, test_file:gsub('/', '.'):gsub('%.lua$', ''))

  if not success then
    return false, 0, 0, 'Failed to load test module: ' .. test_module
  end

  if type(test_module) ~= 'table' or type(test_module.run) ~= 'function' then
    return false, 0, 0, 'Test module does not export run function'
  end

  local test_success = test_module.run()
  local total = test_module.total_tests and test_module.total_tests() or 0
  local passed = test_module.passed_tests and test_module.passed_tests() or 0

  return test_success, total, passed, nil
end

-- Helper to run integration tests (requires Neovim)
local function run_integration_test_with_neovim(test_file)
  local cmd = string.format('nvim --headless -u NONE -c "luafile %s"', test_file)
  local exit_code = os.execute(cmd)

  -- In Lua 5.1, os.execute returns exit code directly
  -- In Lua 5.2+, it returns (true/false, "exit", code)
  local success
  if type(exit_code) == 'number' then
    success = exit_code == 0
  else
    success = exit_code == true
  end

  return success
end

-- Print test suite header
local function print_suite_header(suite)
  print(COLORS.BLUE .. COLORS.BOLD .. '=== ' .. suite.name .. ' ===' .. COLORS.RESET)
  print(COLORS.YELLOW .. suite.description .. COLORS.RESET)
  print()
end

-- Print test results
local function print_test_results(suite_name, success, total, passed, error_msg)
  if error_msg then
    print(COLORS.RED .. '✗ ' .. suite_name .. ' failed: ' .. error_msg .. COLORS.RESET)
    return
  end

  local status_color = success and COLORS.GREEN or COLORS.RED
  local status_symbol = success and '✓' or '✗'

  print(
    status_color
      .. status_symbol
      .. ' '
      .. suite_name
      .. (total > 0 and string.format(' (%d/%d tests passed)', passed, total) or '')
      .. COLORS.RESET
  )
end

-- Run all test suites
local function run_all_tests()
  print(COLORS.BOLD .. 'Container.nvim Async Utils Test Suite' .. COLORS.RESET)
  print(string.rep('=', 50))
  print()

  local total_suites = #TEST_SUITES
  local passed_suites = 0
  local total_tests = 0
  local total_passed = 0
  local skipped_suites = 0

  local is_neovim = is_neovim_environment()

  if not is_neovim then
    print(
      COLORS.YELLOW
        .. 'Note: Running in standalone Lua mode. Integration tests will use nvim --headless.'
        .. COLORS.RESET
    )
    print()
  end

  for _, suite in ipairs(TEST_SUITES) do
    print_suite_header(suite)

    if suite.requires_neovim and not is_neovim then
      -- Run integration test with external Neovim
      local success = run_integration_test_with_neovim(suite.file)
      if success then
        passed_suites = passed_suites + 1
        print_test_results(suite.name, true, 0, 0, nil)
      else
        print_test_results(suite.name, false, 0, 0, 'Integration test failed (check nvim output)')
      end
    elseif suite.requires_neovim and is_neovim then
      -- Running in Neovim, but this script is for external execution
      print(COLORS.YELLOW .. 'Skipping ' .. suite.name .. ' (requires external nvim execution)' .. COLORS.RESET)
      skipped_suites = skipped_suites + 1
    else
      -- Run unit test
      local success, suite_total, suite_passed, error_msg = run_unit_test(suite.file)

      total_tests = total_tests + suite_total
      total_passed = total_passed + suite_passed

      if success then
        passed_suites = passed_suites + 1
      end

      print_test_results(suite.name, success, suite_total, suite_passed, error_msg)
    end

    print()
  end

  -- Print summary
  print(string.rep('=', 50))
  print(COLORS.BOLD .. 'Test Summary' .. COLORS.RESET)
  print(string.rep('-', 20))

  local effective_suites = total_suites - skipped_suites
  local suite_success_rate = effective_suites > 0 and (passed_suites / effective_suites * 100) or 0
  local test_success_rate = total_tests > 0 and (total_passed / total_tests * 100) or 0

  print(string.format('Test Suites: %d/%d passed (%.1f%%)', passed_suites, effective_suites, suite_success_rate))
  if skipped_suites > 0 then
    print(string.format('Skipped Suites: %d', skipped_suites))
  end

  if total_tests > 0 then
    print(string.format('Individual Tests: %d/%d passed (%.1f%%)', total_passed, total_tests, test_success_rate))
  end

  local overall_success = passed_suites == effective_suites and (total_tests == 0 or total_passed == total_tests)

  if overall_success then
    print(COLORS.GREEN .. COLORS.BOLD .. '\n✓ All async utility tests passed!' .. COLORS.RESET)
    return 0
  else
    print(COLORS.RED .. COLORS.BOLD .. '\n✗ Some async utility tests failed!' .. COLORS.RESET)
    return 1
  end
end

-- Quick test runner (subset for fast feedback)
local function run_quick_tests()
  print(COLORS.BOLD .. 'Container.nvim Async Utils Quick Test Suite' .. COLORS.RESET)
  print(string.rep('=', 50))
  print()

  local quick_suites = {
    TEST_SUITES[1], -- Unit Tests (Comprehensive)
    TEST_SUITES[2], -- Unit Tests (Error Scenarios)
  }

  local passed_suites = 0
  local total_tests = 0
  local total_passed = 0

  for _, suite in ipairs(quick_suites) do
    print_suite_header(suite)

    local success, suite_total, suite_passed, error_msg = run_unit_test(suite.file)

    total_tests = total_tests + suite_total
    total_passed = total_passed + suite_passed

    if success then
      passed_suites = passed_suites + 1
    end

    print_test_results(suite.name, success, suite_total, suite_passed, error_msg)
    print()
  end

  -- Print summary
  print(string.rep('=', 50))
  print(COLORS.BOLD .. 'Quick Test Summary' .. COLORS.RESET)
  print(string.rep('-', 20))

  local suite_success_rate = #quick_suites > 0 and (passed_suites / #quick_suites * 100) or 0
  local test_success_rate = total_tests > 0 and (total_passed / total_tests * 100) or 0

  print(string.format('Test Suites: %d/%d passed (%.1f%%)', passed_suites, #quick_suites, suite_success_rate))
  print(string.format('Individual Tests: %d/%d passed (%.1f%%)', total_passed, total_tests, test_success_rate))

  local overall_success = passed_suites == #quick_suites and total_passed == total_tests

  if overall_success then
    print(COLORS.GREEN .. COLORS.BOLD .. '\n✓ All quick async utility tests passed!' .. COLORS.RESET)
    return 0
  else
    print(COLORS.RED .. COLORS.BOLD .. '\n✗ Some quick async utility tests failed!' .. COLORS.RESET)
    return 1
  end
end

-- Print usage information
local function print_usage()
  print(COLORS.BOLD .. 'Container.nvim Async Utils Test Runner' .. COLORS.RESET)
  print()
  print('Usage: lua test/run_async_tests.lua [options]')
  print()
  print('Options:')
  print('  --help, -h     Show this help message')
  print('  --quick, -q    Run only unit tests for quick feedback')
  print('  --list, -l     List available test suites')
  print('  --all          Run all test suites (default)')
  print()
  print('Test Suites:')
  for i, suite in ipairs(TEST_SUITES) do
    print(string.format('  %d. %s', i, suite.name))
    print(string.format('     %s', suite.description))
    print(string.format('     Requires Neovim: %s', suite.requires_neovim and 'Yes' or 'No'))
    print()
  end
end

-- List available test suites
local function list_test_suites()
  print(COLORS.BOLD .. 'Available Test Suites:' .. COLORS.RESET)
  print()

  for i, suite in ipairs(TEST_SUITES) do
    local neovim_indicator = suite.requires_neovim and ' (Neovim)' or ' (Standalone)'
    print(string.format('%d. %s%s', i, suite.name, neovim_indicator))
    print(string.format('   File: %s', suite.file))
    print(string.format('   Description: %s', suite.description))
    print()
  end
end

-- Main execution
local function main()
  local args = arg or {}

  if #args == 0 then
    -- Default: run all tests
    return run_all_tests()
  end

  local command = args[1]

  if command == '--help' or command == '-h' then
    print_usage()
    return 0
  elseif command == '--quick' or command == '-q' then
    return run_quick_tests()
  elseif command == '--list' or command == '-l' then
    list_test_suites()
    return 0
  elseif command == '--all' then
    return run_all_tests()
  else
    print(COLORS.RED .. 'Unknown option: ' .. command .. COLORS.RESET)
    print('Use --help for usage information.')
    return 1
  end
end

-- Execute main function and exit with appropriate code
local exit_code = main()
os.exit(exit_code)
