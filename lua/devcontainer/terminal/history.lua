-- lua/devcontainer/terminal/history.lua
-- Terminal history persistence and management

local M = {}
local log = require('devcontainer.utils.log')

-- Get history file path for a session
function M.get_history_file_path(session, project_path)
  if not session.config.persistent_history or not session.config.history_dir then
    return nil
  end

  -- Create project-specific directory
  local project_hash = vim.fn.sha256(project_path or vim.fn.getcwd())
  local project_dir = string.format('%s/%s', session.config.history_dir, project_hash:sub(1, 8))

  -- Ensure directory exists
  local fs = require('devcontainer.utils.fs')
  fs.ensure_directory(project_dir)

  -- Return history file path
  local safe_name = session.name:gsub('[^%w%-_]', '_')
  return string.format('%s/%s.history', project_dir, safe_name)
end

-- Load history for a session
function M.load_history(session, project_path)
  local history_file = M.get_history_file_path(session, project_path)
  if not history_file then
    return nil
  end

  -- Check if file exists
  if vim.fn.filereadable(history_file) == 0 then
    log.debug('No history file found for session: %s', session.name)
    return nil
  end

  -- Read history file
  local lines = vim.fn.readfile(history_file)
  if not lines or #lines == 0 then
    return nil
  end

  -- Limit history size
  local max_lines = session.config.max_history_lines or 10000
  if #lines > max_lines then
    lines = vim.list_slice(lines, #lines - max_lines + 1, #lines)
  end

  log.debug('Loaded %d lines of history for session: %s', #lines, session.name)
  return lines
end

-- Save history for a session
function M.save_history(session, project_path, content)
  local history_file = M.get_history_file_path(session, project_path)
  if not history_file then
    return false, 'History persistence disabled'
  end

  if not content or #content == 0 then
    return true, 'No content to save'
  end

  -- Limit history size
  local max_lines = session.config.max_history_lines or 10000
  local lines = content

  if #lines > max_lines then
    lines = vim.list_slice(lines, #lines - max_lines + 1, #lines)
  end

  -- Write to file
  local success = pcall(vim.fn.writefile, lines, history_file)
  if not success then
    log.error('Failed to save history for session: %s', session.name)
    return false, 'Failed to write history file'
  end

  log.debug('Saved %d lines of history for session: %s', #lines, session.name)
  return true, nil
end

-- Get terminal buffer content as lines
function M.get_buffer_content(buf_id)
  if not buf_id or not vim.api.nvim_buf_is_valid(buf_id) then
    return {}
  end

  -- Get all lines from terminal buffer
  local lines = vim.api.nvim_buf_get_lines(buf_id, 0, -1, false)

  -- Filter out empty lines from the end
  while #lines > 0 and lines[#lines] == '' do
    table.remove(lines)
  end

  return lines
end

-- Restore history to terminal buffer
function M.restore_history_to_buffer(buf_id, history_lines)
  if not buf_id or not vim.api.nvim_buf_is_valid(buf_id) then
    return false, 'Invalid buffer'
  end

  if not history_lines or #history_lines == 0 then
    return true, 'No history to restore'
  end

  -- Insert history at the beginning of the buffer
  -- Note: This is tricky with terminal buffers since they're managed by the terminal job
  -- We'll implement a simple approach that works with most terminals

  local success = pcall(vim.api.nvim_buf_set_lines, buf_id, 0, 0, false, history_lines)
  if not success then
    log.warn('Failed to restore history to terminal buffer')
    return false, 'Failed to insert history'
  end

  log.debug('Restored %d lines of history to terminal buffer', #history_lines)
  return true, nil
end

-- Set up automatic history saving for a session
function M.setup_auto_save(session, project_path)
  if not session.config.persistent_history then
    return
  end

  local buf_id = session.buffer_id
  if not buf_id or not vim.api.nvim_buf_is_valid(buf_id) then
    return
  end

  -- Create autogroup for this session
  local group_name = 'DevcontainerTerminalHistory_' .. session.name
  local group = vim.api.nvim_create_augroup(group_name, { clear = true })

  -- Save history when buffer is written or when leaving
  local function save_current_history()
    local content = M.get_buffer_content(buf_id)
    if #content > 0 then
      M.save_history(session, project_path, content)
    end
  end

  -- Save on buffer write
  vim.api.nvim_create_autocmd('BufWritePost', {
    buffer = buf_id,
    group = group,
    callback = save_current_history,
  })

  -- Save when leaving buffer
  vim.api.nvim_create_autocmd('BufLeave', {
    buffer = buf_id,
    group = group,
    callback = save_current_history,
  })

  -- Save when Neovim exits
  vim.api.nvim_create_autocmd('VimLeave', {
    buffer = buf_id,
    group = group,
    callback = save_current_history,
  })

  log.debug('Set up auto-save for session history: %s', session.name)
end

-- Clean up old history files
function M.cleanup_old_history(config, days_to_keep)
  if not config.history_dir then
    return 0
  end

  days_to_keep = days_to_keep or 30
  local cutoff_time = os.time() - (days_to_keep * 24 * 60 * 60)

  local fs = require('devcontainer.utils.fs')
  local history_dir = config.history_dir

  if vim.fn.isdirectory(history_dir) == 0 then
    return 0
  end

  local cleaned_count = 0

  -- Get all project directories
  local project_dirs = vim.fn.globpath(history_dir, '*', false, true)

  for _, project_dir in ipairs(project_dirs) do
    if vim.fn.isdirectory(project_dir) == 1 then
      -- Get all history files in this project
      local history_files = vim.fn.globpath(project_dir, '*.history', false, true)

      for _, history_file in ipairs(history_files) do
        local stat = vim.loop.fs_stat(history_file)
        if stat and stat.mtime.sec < cutoff_time then
          if vim.fn.delete(history_file) == 0 then
            cleaned_count = cleaned_count + 1
            log.debug('Deleted old history file: %s', history_file)
          end
        end
      end

      -- Remove empty project directories
      local remaining_files = vim.fn.globpath(project_dir, '*', false, true)
      if #remaining_files == 0 then
        if vim.fn.delete(project_dir, 'd') == 0 then
          log.debug('Removed empty project directory: %s', project_dir)
        end
      end
    end
  end

  if cleaned_count > 0 then
    log.info('Cleaned up %d old terminal history files', cleaned_count)
  end

  return cleaned_count
end

-- Get history statistics
function M.get_history_stats(config)
  if not config.history_dir then
    return {
      enabled = false,
      total_files = 0,
      total_size = 0,
      projects = 0,
    }
  end

  local stats = {
    enabled = true,
    total_files = 0,
    total_size = 0,
    projects = 0,
    history_dir = config.history_dir,
  }

  if vim.fn.isdirectory(config.history_dir) == 0 then
    return stats
  end

  -- Get all project directories
  local project_dirs = vim.fn.globpath(config.history_dir, '*', false, true)
  stats.projects = #project_dirs

  for _, project_dir in ipairs(project_dirs) do
    if vim.fn.isdirectory(project_dir) == 1 then
      -- Get all history files in this project
      local history_files = vim.fn.globpath(project_dir, '*.history', false, true)

      for _, history_file in ipairs(history_files) do
        local stat = vim.loop.fs_stat(history_file)
        if stat then
          stats.total_files = stats.total_files + 1
          stats.total_size = stats.total_size + stat.size
        end
      end
    end
  end

  return stats
end

-- Export history for a session (for backup or sharing)
function M.export_session_history(session, project_path, export_path)
  local history_file = M.get_history_file_path(session, project_path)
  if not history_file or vim.fn.filereadable(history_file) == 0 then
    return false, 'No history file found'
  end

  -- Copy history file to export location
  local success = pcall(vim.fn.writefile, vim.fn.readfile(history_file), export_path)
  if not success then
    return false, 'Failed to export history'
  end

  log.info('Exported history for session %s to %s', session.name, export_path)
  return true, nil
end

return M
