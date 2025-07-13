#!/usr/bin/env lua

-- Parallel E2E Test Runner for container.nvim (Fixed Version)
-- Executes tests in true parallel and aggregates results

local function run_command(cmd, show_output)
  if show_output then
    local handle = io.popen(cmd .. ' 2>&1', 'r')
    local result = {}

    while true do
      local line = handle:read('*l')
      if not line then
        break
      end
      table.insert(result, line)
    end

    local success = handle:close()
    return success, table.concat(result, '\n')
  else
    local handle = io.popen(cmd .. ' 2>&1')
    local result = handle:read('*a')
    local success = handle:close()
    return success, result
  end
end

local function check_prerequisites()
  print('=== Checking Prerequisites ===')

  local nvim_success = run_command('nvim --version >/dev/null 2>&1')
  if not nvim_success then
    print('❌ Error: Neovim not found. E2E tests require Neovim.')
    return false
  end
  print('✓ Neovim available')

  local docker_success = run_command('docker --version >/dev/null 2>&1')
  if not docker_success then
    print('❌ Error: Docker not found. E2E tests require Docker.')
    return false
  end
  print('✓ Docker CLI available')

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

local function create_test_script(test_case, output_file, script_file)
  local base_cmd = string.format(
    'nvim --headless -u test/e2e/minimal_init.lua -c "lua dofile(\'test/e2e/%s\')" -c "qa"',
    test_case.file
  )

  -- Create bash script for each test
  local script_content = string.format(
    [[#!/bin/bash
# Test script for %s
echo "Starting %s at $(date)"
%s > %s 2>&1
EXIT_CODE=$?
echo $EXIT_CODE > %s.exitcode
echo "Completed %s at $(date) with exit code $EXIT_CODE"
]],
    test_case.name,
    test_case.name,
    base_cmd,
    output_file,
    output_file,
    test_case.name
  )

  local script_handle = io.open(script_file, 'w')
  script_handle:write(script_content)
  script_handle:close()

  -- Make script executable
  os.execute('chmod +x ' .. script_file)
end

local function start_test_background(script_file, pid_file)
  -- Start test in background and capture PID
  local cmd = string.format('bash %s & echo $! > %s', script_file, pid_file)
  os.execute(cmd)
end

local function check_process_status(pid_file)
  local pid_handle = io.open(pid_file, 'r')
  if not pid_handle then
    return false
  end

  local pid = pid_handle:read('*l')
  pid_handle:close()

  if not pid then
    return false
  end

  -- Check if process is still running
  local success = run_command(string.format('kill -0 %s 2>/dev/null', pid))
  return success
end

local function wait_for_all_tests(pid_files, timeout_seconds)
  local timeout = timeout_seconds or 600 -- 10 minutes default timeout
  local start_time = os.time()

  while os.time() - start_time < timeout do
    local all_complete = true

    for _, pid_file in ipairs(pid_files) do
      if check_process_status(pid_file) then
        all_complete = false
        break
      end
    end

    if all_complete then
      print('✅ All tests completed!')
      return true
    end

    -- Wait a bit before checking again
    os.execute('sleep 2')
  end

  print('❌ Timeout reached - killing remaining processes')
  -- Kill any remaining processes
  for _, pid_file in ipairs(pid_files) do
    local pid_handle = io.open(pid_file, 'r')
    if pid_handle then
      local pid = pid_handle:read('*l')
      pid_handle:close()
      if pid then
        os.execute(string.format('kill %s 2>/dev/null', pid))
      end
    end
  end

  return false -- Timeout
end

local function parse_test_result(output_file, test_name)
  local exit_code_file = output_file .. '.exitcode'

  -- Read exit code
  local exit_code_handle = io.open(exit_code_file, 'r')
  if not exit_code_handle then
    return false, 'Could not read exit code file', -1
  end

  local exit_code_str = exit_code_handle:read('*l')
  exit_code_handle:close()

  if not exit_code_str then
    return false, 'Could not parse exit code', -1
  end

  local exit_code = tonumber(exit_code_str)
  local success = exit_code == 0

  -- Read output
  local output_handle = io.open(output_file, 'r')
  local output = ''
  if output_handle then
    output = output_handle:read('*a')
    output_handle:close()
  end

  return success, output, exit_code
end

local function main()
  print('=== container.nvim Parallel E2E Test Runner ===')
  print('Running E2E tests in parallel with result aggregation')
  print('')

  -- Check prerequisites
  if not check_prerequisites() then
    print('❌ Prerequisites check failed')
    os.exit(1)
  end
  print('')

  -- Create temporary directory for test outputs
  local temp_dir = '/tmp/container_nvim_e2e_' .. os.time()
  os.execute('mkdir -p ' .. temp_dir)

  print('=== Starting Parallel Test Execution ===')
  print('Temporary output directory: ' .. temp_dir)
  print('')

  local start_time = os.time()
  local test_info = {}
  local pid_files = {}

  -- Create and start all tests in parallel
  for i, test_case in ipairs(test_cases) do
    local test_file_path = 'test/e2e/' .. test_case.file
    local file = io.open(test_file_path, 'r')

    if not file then
      print('⚠ Test file not found: ' .. test_file_path)
      print('Skipping: ' .. test_case.name)
      goto continue
    end
    file:close()

    local output_file = temp_dir .. '/test_' .. i .. '_output.txt'
    local script_file = temp_dir .. '/test_' .. i .. '_script.sh'
    local pid_file = temp_dir .. '/test_' .. i .. '_pid.txt'

    table.insert(test_info, {
      test_case = test_case,
      output_file = output_file,
      script_file = script_file,
      pid_file = pid_file,
    })
    table.insert(pid_files, pid_file)

    -- Create test script
    create_test_script(test_case, output_file, script_file)

    -- Start test in background
    print(string.format('🚀 Starting test %d: %s', i, test_case.name))
    start_test_background(script_file, pid_file)

    -- Small delay to avoid race conditions
    os.execute('sleep 0.1')

    ::continue::
  end

  print('')
  print('⏳ Waiting for all tests to complete...')

  -- Wait for all tests to complete
  local completed = wait_for_all_tests(pid_files, 600) -- 10 minutes timeout

  local total_elapsed = os.time() - start_time

  if not completed then
    print('❌ Tests timed out after 10 minutes')
    os.execute('rm -rf ' .. temp_dir)
    os.exit(1)
  end

  print(string.format('✅ All tests completed in %.1fs', total_elapsed))
  print('')

  -- Aggregate results
  print('=== Test Results Aggregation ===')

  local passed = 0
  local total = #test_info
  local failed_tests = {}

  for _, info in ipairs(test_info) do
    local success, output, exit_code = parse_test_result(info.output_file, info.test_case.name)

    if success then
      passed = passed + 1
      print(string.format('✅ %s PASSED', info.test_case.name))
    else
      print(string.format('❌ %s FAILED (exit code: %d)', info.test_case.name, exit_code))
      table.insert(failed_tests, info.test_case.name)

      -- Show error output for failed tests (last 15 lines)
      print('--- Error Output ---')
      local lines = {}
      for line in output:gmatch('[^\n]+') do
        table.insert(lines, line)
      end
      local start_line = math.max(1, #lines - 14)
      for j = start_line, #lines do
        print(lines[j])
      end
      print('--- End Error Output ---')
    end
    print('')
  end

  -- Clean up temporary files
  os.execute('rm -rf ' .. temp_dir)

  -- Print final summary
  print('=== Final E2E Test Summary ===')
  print(string.format('Total execution time: %.1fs', total_elapsed))
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
    print(string.format('✨ Parallel execution completed in %.1fs', total_elapsed))
    os.exit(0)
  else
    print('⚠ Some E2E tests failed.')
    os.exit(1)
  end
end

-- Run the parallel test runner
main()
