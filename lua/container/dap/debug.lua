-- DAP debug helper functions

local M = {}

-- Set DAP log level for debugging
function M.set_debug_log()
  require('dap').set_log_level('TRACE')
  print('DAP log level set to TRACE. Check logs at: ' .. vim.fn.stdpath('cache') .. '/dap.log')
end

-- Show DAP log
function M.show_dap_log()
  local log_path = vim.fn.stdpath('cache') .. '/dap.log'
  vim.cmd('edit ' .. log_path)
  vim.cmd('normal G') -- Go to last line
end

-- Show DAP status
function M.show_status()
  local dap = require('dap')
  local session = dap.session()

  if session then
    print('DAP Session Active:')
    print('  State: ' .. (session.state or 'unknown'))
    print('  Adapter: ' .. vim.inspect(session.adapter))
  else
    print('No active DAP session')
  end

  -- Show breakpoint information
  local breakpoints = require('dap.breakpoints').get()
  local bp_count = 0
  for _, bps in pairs(breakpoints) do
    bp_count = bp_count + #bps
  end
  print('Breakpoints set: ' .. bp_count)
end

-- Check if debugger is running in container
function M.check_container_debugger()
  local container_id = require('container').get_container_id()
  if not container_id then
    print('No active container')
    return
  end

  -- Check for dlv processes
  local result = require('container.docker').run_docker_command({
    'exec',
    container_id,
    'pgrep',
    '-l',
    'dlv',
  })

  if result.success and result.stdout ~= '' then
    print('Delve debugger processes in container:')
    print(result.stdout)
  else
    print('No dlv process found in container')
  end
end

-- Show DAP configuration
function M.show_dap_config()
  local dap = require('dap')
  print('=== DAP Configurations ===')
  print('Go configurations:')
  print(vim.inspect(dap.configurations.go))
  print('\nGo adapter:')
  print(vim.inspect(dap.adapters.container_go))
end

-- Test debugger connection
function M.test_debugger_connection()
  local container_id = require('container').get_container_id()
  if not container_id then
    print('No active container')
    return
  end

  print('Testing dlv in container...')

  -- Check if dlv is installed
  local result = require('container.docker').run_docker_command({
    'exec',
    container_id,
    'which',
    'dlv',
  })

  if result.success then
    print('dlv found at: ' .. vim.trim(result.stdout))
  else
    print('dlv not found in container!')
    return
  end

  -- Check dlv version
  local version_result = require('container.docker').run_docker_command({
    'exec',
    container_id,
    'dlv',
    'version',
  })

  if version_result.success then
    print('dlv version:')
    print(version_result.stdout)
  else
    print('Failed to get dlv version')
  end
end

-- Show current breakpoints
function M.show_breakpoints()
  local breakpoints = require('dap.breakpoints').get()
  local current_file = vim.fn.expand('%:p')

  if breakpoints[current_file] then
    print('Breakpoints in current file:')
    for _, bp in ipairs(breakpoints[current_file]) do
      print(string.format('  Line %d', bp.line))
    end
  else
    print('No breakpoints in current file')
  end

  print('\nAll breakpoints:')
  for file, bps in pairs(breakpoints) do
    if #bps > 0 then
      print(string.format('%s: %d breakpoints', file, #bps))
    end
  end
end

return M
