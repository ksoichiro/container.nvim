-- lua/devcontainer/history.lua
-- Command execution history management

local M = {}
local log = require('container.utils.log')
local fs = require('container.utils.fs')

-- History storage
local history = {
  exec_commands = {},
  max_entries = 1000,
}

-- Get history file path
local function get_history_file()
  local data_dir = vim.fn.stdpath('data') .. '/devcontainer'
  fs.ensure_directory(data_dir)
  return data_dir .. '/command_history.json'
end

-- Load history from file
function M.load()
  local history_file = get_history_file()
  if not fs.is_file(history_file) then
    return
  end

  local content, err = fs.read_file(history_file)
  if not content then
    log.warn('Failed to load command history: %s', err)
    return
  end

  local ok, data = pcall(vim.json.decode, content)
  if ok and data then
    history = vim.tbl_extend('force', history, data)

    -- Trim to max entries
    if #history.exec_commands > history.max_entries then
      local start_idx = #history.exec_commands - history.max_entries + 1
      history.exec_commands = vim.list_slice(history.exec_commands, start_idx)
    end
  end
end

-- Save history to file
function M.save()
  local history_file = get_history_file()
  local content = vim.json.encode(history)

  local ok, err = fs.write_file(history_file, content)
  if not ok then
    log.warn('Failed to save command history: %s', err)
  end
end

-- Add command to history
function M.add_exec_command(command, container_name, exit_code, output, duration)
  table.insert(history.exec_commands, {
    command = command,
    container_name = container_name,
    exit_code = exit_code,
    output = output,
    duration = duration,
    timestamp = os.date('%Y-%m-%d %H:%M:%S'),
  })

  -- Trim old entries
  if #history.exec_commands > history.max_entries then
    table.remove(history.exec_commands, 1)
  end

  -- Save to file
  M.save()
end

-- Get execution history
function M.get_exec_history(limit)
  limit = limit or 100
  local start_idx = math.max(1, #history.exec_commands - limit + 1)

  -- Return in reverse chronological order
  local result = {}
  for i = #history.exec_commands, start_idx, -1 do
    table.insert(result, history.exec_commands[i])
  end

  return result
end

-- Search history
function M.search_history(pattern, limit)
  limit = limit or 100
  local results = {}

  for i = #history.exec_commands, 1, -1 do
    local entry = history.exec_commands[i]
    if entry.command:match(pattern) then
      table.insert(results, entry)
      if #results >= limit then
        break
      end
    end
  end

  return results
end

-- Clear history
function M.clear()
  history.exec_commands = {}
  M.save()
end

-- Get statistics
function M.get_stats()
  local stats = {
    total_commands = #history.exec_commands,
    containers = {},
    success_rate = 0,
    total_duration = 0,
  }

  local success_count = 0

  for _, entry in ipairs(history.exec_commands) do
    -- Container stats
    local container = entry.container_name or 'unknown'
    stats.containers[container] = (stats.containers[container] or 0) + 1

    -- Success rate
    if entry.exit_code == 0 then
      success_count = success_count + 1
    end

    -- Total duration
    if entry.duration then
      stats.total_duration = stats.total_duration + entry.duration
    end
  end

  if stats.total_commands > 0 then
    stats.success_rate = (success_count / stats.total_commands) * 100
  end

  return stats
end

-- Initialize
M.load()

return M
