-- lua/devcontainer/terminal/session.lua
-- Terminal session management

local M = {}
local log = require('devcontainer.utils.log')

-- Internal state for tracking sessions
local sessions = {}
local active_session = nil

-- Session object structure
local Session = {}
Session.__index = Session

function Session:new(name, container_id, config)
  local session = {
    name = name,
    container_id = container_id,
    buffer_id = nil,
    job_id = nil,
    created_at = os.time(),
    last_accessed = os.time(),
    history_file = nil,
    config = config or {},
  }

  setmetatable(session, Session)
  return session
end

function Session:is_valid()
  return self.buffer_id
    and vim.api.nvim_buf_is_valid(self.buffer_id)
    and self.job_id
    and vim.fn.jobwait({ self.job_id }, 0)[1] == -1 -- Job is still running
end

function Session:update_access_time()
  self.last_accessed = os.time()
end

function Session:get_display_name()
  local status = self:is_valid() and '●' or '○'
  return string.format('%s %s', status, self.name)
end

function Session:close(force_close_buffer)
  if self.job_id then
    vim.fn.jobstop(self.job_id)
    self.job_id = nil
  end

  if self.buffer_id and vim.api.nvim_buf_is_valid(self.buffer_id) then
    -- Close buffer if forced or configured to close on exit
    if force_close_buffer or self.config.close_on_exit then
      vim.api.nvim_buf_delete(self.buffer_id, { force = true })
    end
    self.buffer_id = nil
  end

  log.debug('Terminal session closed: %s', self.name)
end

-- Module functions

function M.setup(config)
  M.config = config or {}

  -- Create history directory if needed
  if M.config.persistent_history and M.config.history_dir then
    local fs = require('devcontainer.utils.fs')
    fs.ensure_directory(M.config.history_dir)
  end

  log.debug('Terminal session manager initialized')
end

function M.create_session(name, container_id, opts)
  opts = opts or {}

  -- Validate inputs
  if not name or name == '' then
    return nil, 'Session name is required'
  end

  if not container_id then
    return nil, 'Container ID is required'
  end

  -- Check if session already exists
  if sessions[name] then
    if sessions[name]:is_valid() then
      return nil, string.format('Session "%s" already exists', name)
    else
      -- Clean up invalid session
      sessions[name]:close()
      sessions[name] = nil
    end
  end

  -- Create new session
  local session = Session:new(name, container_id, vim.tbl_extend('force', M.config, opts))
  sessions[name] = session

  log.info('Created terminal session: %s (container: %s)', name, container_id:sub(1, 12))
  return session, nil
end

function M.get_session(name)
  local session = sessions[name]

  if not session then
    return nil
  end

  -- Check if session is still valid
  if not session:is_valid() then
    log.debug('Session %s is no longer valid, cleaning up', name)
    session:close()
    sessions[name] = nil
    return nil
  end

  session:update_access_time()
  return session
end

function M.list_sessions()
  local valid_sessions = {}
  local invalid_sessions = {}

  for name, session in pairs(sessions) do
    if session:is_valid() then
      table.insert(valid_sessions, session)
    else
      table.insert(invalid_sessions, name)
    end
  end

  -- Clean up invalid sessions
  for _, name in ipairs(invalid_sessions) do
    sessions[name]:close()
    sessions[name] = nil
  end

  -- Sort by last accessed time (most recent first)
  table.sort(valid_sessions, function(a, b)
    return a.last_accessed > b.last_accessed
  end)

  return valid_sessions
end

function M.get_active_session()
  if active_session and active_session:is_valid() then
    return active_session
  end

  active_session = nil
  return nil
end

function M.set_active_session(session)
  if session and session:is_valid() then
    active_session = session
    session:update_access_time()
    log.debug('Active terminal session: %s', session.name)
  else
    active_session = nil
  end
end

function M.close_session(name, force_close_buffer)
  local session = sessions[name]
  if not session then
    return false, string.format('Session "%s" not found', name)
  end

  session:close(force_close_buffer)
  sessions[name] = nil

  -- Update active session if needed
  if active_session == session then
    active_session = nil
  end

  log.info('Closed terminal session: %s', name)
  return true, nil
end

function M.close_all_sessions(force_close_buffer)
  local count = 0
  for name, session in pairs(sessions) do
    session:close(force_close_buffer)
    count = count + 1
  end

  sessions = {}
  active_session = nil

  log.info('Closed %d terminal sessions', count)
  return count
end

function M.get_next_session(current_name)
  local session_list = M.list_sessions()
  if #session_list <= 1 then
    return nil
  end

  for i, session in ipairs(session_list) do
    if session.name == current_name then
      return session_list[i + 1] or session_list[1]
    end
  end

  return session_list[1]
end

function M.get_prev_session(current_name)
  local session_list = M.list_sessions()
  if #session_list <= 1 then
    return nil
  end

  for i, session in ipairs(session_list) do
    if session.name == current_name then
      return session_list[i - 1] or session_list[#session_list]
    end
  end

  return session_list[1]
end

function M.generate_unique_name(base_name)
  base_name = base_name or 'terminal'

  if not sessions[base_name] then
    return base_name
  end

  local counter = 1
  while sessions[base_name .. '_' .. counter] do
    counter = counter + 1
  end

  return base_name .. '_' .. counter
end

function M.get_session_stats()
  local stats = {
    total = 0,
    active = 0,
    inactive = 0,
    sessions = {},
  }

  for name, session in pairs(sessions) do
    stats.total = stats.total + 1

    if session:is_valid() then
      stats.active = stats.active + 1
    else
      stats.inactive = stats.inactive + 1
    end

    table.insert(stats.sessions, {
      name = name,
      valid = session:is_valid(),
      created_at = session.created_at,
      last_accessed = session.last_accessed,
      container = session.container_id and session.container_id:sub(1, 12) or 'unknown',
    })
  end

  return stats
end

return M
