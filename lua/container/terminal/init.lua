-- lua/devcontainer/terminal/init.lua
-- Enhanced terminal integration main module

local M = {}
local log = require('container.utils.log')
local notify = require('container.utils.notify')

-- Lazy load submodules
local session_manager = nil
local display = nil
local history = nil

-- Initialize terminal system
function M.setup(config)
  session_manager = require('container.terminal.session')
  display = require('container.terminal.display')
  history = require('container.terminal.history')

  -- Initialize session manager with config
  session_manager.setup(config.terminal or {})

  log.debug('Terminal system initialized')
end

-- Create or switch to a terminal session
function M.terminal(opts)
  opts = opts or {}

  -- Get current container
  local container = require('container')
  local container_id = container.get_container_id()

  if not container_id then
    notify.critical('No active container. Start container first with :ContainerStart')
    return false
  end

  -- Determine session name
  local session_name = opts.name or 'main'
  if session_name == '' then
    session_name = session_manager.generate_unique_name('terminal')
  end

  -- Try to get existing session
  local session = session_manager.get_session(session_name)

  if session then
    -- Switch to existing session
    local success, err = display.switch_to_session(session)
    if not success then
      log.error('Failed to switch to session %s: %s', session_name, err)
      return false
    end

    log.info('Switched to existing terminal session: %s', session_name)
    return true
  end

  -- Create new session
  local config = require('container.config').get()
  local err
  session, err = session_manager.create_session(session_name, container_id, config.terminal)

  if not session then
    notify.critical(string.format('Failed to create terminal session: %s', err))
    return false
  end

  -- Create terminal buffer with specified position
  local position = opts.position or config.terminal.default_position
  local buf_id, _, create_err = display.create_terminal_buffer(session, position, opts)

  if not buf_id then
    session_manager.close_session(session_name)
    notify.critical(string.format('Failed to create terminal: %s', create_err))
    return false
  end

  -- Update session with buffer info
  session.buffer_id = buf_id

  -- Load history if enabled
  if config.terminal.persistent_history then
    local project_path = vim.fn.getcwd()
    local history_lines = history.load_history(session, project_path)

    if history_lines then
      history.restore_history_to_buffer(buf_id, history_lines)
    end

    -- Set up auto-save for this session
    history.setup_auto_save(session, project_path)
  end

  -- Build terminal command
  local shell = opts.shell or config.terminal.default_shell
  local environment = config.terminal.environment or {}
  local cmd = display.build_terminal_command(container_id, shell, environment)

  -- Switch to the terminal buffer before calling termopen
  vim.api.nvim_set_current_buf(buf_id)

  -- Ensure buffer is unmodified for termopen
  vim.api.nvim_buf_set_option(buf_id, 'modified', false)

  -- Start terminal job
  local job_id = vim.fn.termopen(table.concat(cmd, ' '), {
    on_exit = function(job_id, exit_code, event)
      log.debug('Terminal session %s exited with code %d', session_name, exit_code)

      -- Save history before cleanup
      if config.terminal.persistent_history then
        local content = history.get_buffer_content(buf_id)
        history.save_history(session, vim.fn.getcwd(), content)
      end

      -- Update session
      session.job_id = nil

      -- Close buffer if configured
      if config.terminal.close_on_exit and vim.api.nvim_buf_is_valid(buf_id) then
        vim.schedule(function()
          vim.api.nvim_buf_delete(buf_id, { force = true })
        end)
      end
    end,
  })

  if job_id <= 0 then
    session_manager.close_session(session_name)
    notify.critical('Failed to start terminal process')
    return false
  end

  -- Update session with job info
  session.job_id = job_id

  -- Set as active session
  session_manager.set_active_session(session)

  -- Enter insert mode if configured
  if config.terminal.auto_insert then
    vim.schedule(function()
      vim.cmd('startinsert')
    end)
  end

  log.info('Created terminal session: %s (container: %s)', session_name, container_id:sub(1, 12))
  return true
end

-- Create new terminal session
function M.new_session(name)
  name = name or session_manager.generate_unique_name('terminal')
  return M.terminal({ name = name })
end

-- List all terminal sessions
function M.list_sessions()
  local sessions = session_manager.list_sessions()

  if #sessions == 0 then
    notify.status('No active terminal sessions')
    return
  end

  local formatted = display.format_session_list(sessions)

  -- Simple list display (can be enhanced with Telescope later)
  local lines = { '=== DevContainer Terminal Sessions ===' }
  for _, item in ipairs(formatted) do
    table.insert(lines, item.display)
  end

  -- Display in a temporary buffer
  local buf_id = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(buf_id, 'buftype', 'nofile')
  vim.api.nvim_buf_set_option(buf_id, 'modifiable', false)

  -- Open in a split
  vim.cmd('split')
  vim.api.nvim_win_set_buf(vim.api.nvim_get_current_win(), buf_id)
  vim.api.nvim_win_set_height(vim.api.nvim_get_current_win(), math.min(#lines + 2, 15))

  -- Set up keymap to select session
  vim.api.nvim_buf_set_keymap(buf_id, 'n', '<CR>', '', {
    noremap = true,
    silent = true,
    callback = function()
      local line_num = vim.api.nvim_win_get_cursor(0)[1]
      if line_num > 1 and line_num <= #formatted + 1 then
        local selected = formatted[line_num - 1]
        if selected and selected.session then
          -- Close list buffer
          vim.api.nvim_buf_delete(buf_id, { force = true })
          -- Switch to selected session
          display.switch_to_session(selected.session)
        end
      end
    end,
  })
end

-- Switch to next terminal session
function M.next_session()
  local current_session = session_manager.get_active_session()
  if not current_session then
    notify.status('No active terminal session', 'warn')
    return
  end

  local next_session = session_manager.get_next_session(current_session.name)
  if next_session then
    display.switch_to_session(next_session)
    notify.terminal(string.format('Switched to session: %s', next_session.name))
  else
    notify.status('No other terminal sessions')
  end
end

-- Switch to previous terminal session
function M.prev_session()
  local current_session = session_manager.get_active_session()
  if not current_session then
    notify.status('No active terminal session', 'warn')
    return
  end

  local prev_session = session_manager.get_prev_session(current_session.name)
  if prev_session then
    display.switch_to_session(prev_session)
    notify.terminal(string.format('Switched to session: %s', prev_session.name))
  else
    notify.status('No other terminal sessions')
  end
end

-- Close specific terminal session
function M.close_session(name)
  if not name then
    local current_session = session_manager.get_active_session()
    if current_session then
      name = current_session.name
    else
      notify.status('No active terminal session to close', 'warn')
      return
    end
  end

  -- Force close buffer when manually closing session
  local success, err = session_manager.close_session(name, true)
  if success then
    notify.terminal(string.format('Closed terminal session: %s', name))
  else
    notify.critical(string.format('Failed to close session: %s', err))
  end
end

-- Close all terminal sessions
function M.close_all_sessions()
  local count = session_manager.close_all_sessions(true)
  notify.terminal(string.format('Closed %d terminal sessions', count))
end

-- Rename terminal session
function M.rename_session(old_name, new_name)
  if not old_name then
    local current_session = session_manager.get_active_session()
    if current_session then
      old_name = current_session.name
    else
      notify.status('No active terminal session to rename', 'warn')
      return
    end
  end

  if not new_name then
    new_name = vim.fn.input('New session name: ', old_name)
    if new_name == '' then
      return
    end
  end

  local session = session_manager.get_session(old_name)
  if not session then
    notify.critical(string.format('Session "%s" not found', old_name))
    return
  end

  -- Check if new name already exists
  if session_manager.get_session(new_name) then
    notify.critical(string.format('Session "%s" already exists', new_name))
    return
  end

  -- Rename session (simple approach: create new, copy state, remove old)
  local success, err = session_manager.create_session(new_name, session.container_id, session.config)
  if not success then
    notify.critical(string.format('Failed to create renamed session: %s', err))
    return
  end

  local new_session = session_manager.get_session(new_name)
  new_session.buffer_id = session.buffer_id
  new_session.job_id = session.job_id
  new_session.created_at = session.created_at

  -- Update buffer name
  if session.buffer_id and vim.api.nvim_buf_is_valid(session.buffer_id) then
    vim.api.nvim_buf_set_name(session.buffer_id, string.format('DevContainer:%s', new_name))
  end

  -- Remove old session without closing the actual terminal
  session.buffer_id = nil
  session.job_id = nil
  session_manager.close_session(old_name)

  -- Set new session as active if old one was active
  local current_active = session_manager.get_active_session()
  if not current_active or current_active.name == old_name then
    session_manager.set_active_session(new_session)
  end

  notify.terminal(string.format('Renamed session "%s" to "%s"', old_name, new_name))
end

-- Get terminal status information
function M.get_status()
  local sessions = session_manager.list_sessions()
  local active_session = session_manager.get_active_session()
  local stats = session_manager.get_session_stats()

  local config = require('container.config').get()
  local history_stats = history.get_history_stats(config.terminal)

  return {
    total_sessions = #sessions,
    active_session = active_session and active_session.name or nil,
    sessions = sessions,
    stats = stats,
    history = history_stats,
  }
end

-- Show terminal status
function M.show_status()
  local status = M.get_status()

  local lines = { '=== DevContainer Terminal Status ===' }
  table.insert(lines, string.format('Total sessions: %d', status.total_sessions))
  table.insert(lines, string.format('Active session: %s', status.active_session or 'none'))
  table.insert(lines, '')

  if status.total_sessions > 0 then
    table.insert(lines, 'Sessions:')
    for _, session in ipairs(status.sessions) do
      local status_icon = session:is_valid() and '●' or '○'
      local time_str = os.date('%H:%M:%S', session.last_accessed)
      table.insert(lines, string.format('  %s %s (last: %s)', status_icon, session.name, time_str))
    end
    table.insert(lines, '')
  end

  -- History information
  if status.history.enabled then
    table.insert(lines, 'History:')
    table.insert(lines, string.format('  Files: %d', status.history.total_files))
    table.insert(lines, string.format('  Projects: %d', status.history.projects))
    table.insert(lines, string.format('  Total size: %.1f KB', status.history.total_size / 1024))
    table.insert(lines, string.format('  Directory: %s', status.history.history_dir))
  else
    table.insert(lines, 'History: disabled')
  end

  -- Display in buffer
  local buf_id = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(buf_id, 'buftype', 'nofile')
  vim.api.nvim_buf_set_option(buf_id, 'modifiable', false)

  vim.cmd('split')
  vim.api.nvim_win_set_buf(vim.api.nvim_get_current_win(), buf_id)
  vim.api.nvim_win_set_height(vim.api.nvim_get_current_win(), math.min(#lines + 2, 20))
end

-- Clean up old history files
function M.cleanup_history(days_to_keep)
  local config = require('container.config').get()
  local count = history.cleanup_old_history(config.terminal, days_to_keep)
  notify.terminal(string.format('Cleaned up %d old history files', count))
end

-- Setup automatic cleanup when container stops
local function setup_container_event_handlers()
  vim.api.nvim_create_autocmd('User', {
    pattern = 'ContainerStopped',
    callback = function()
      local config = require('container.config').get()
      if config.terminal.close_on_container_stop then
        -- Close all terminal sessions when container stops
        local count = session_manager.close_all_sessions(true)
        if count > 0 then
          notify.terminal(string.format('Auto-closed %d terminal sessions (container stopped)', count))
        end
      end
    end,
  })
end

-- Initialize event handlers
setup_container_event_handlers()

return M
