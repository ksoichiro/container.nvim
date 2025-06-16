-- lua/devcontainer/ui/statusline.lua
-- StatusLine integration for devcontainer status display

local M = {}

local config = require('devcontainer.config')
local log = require('devcontainer.utils.log')

-- Cache for performance
local cache = {
  status = nil,
  last_update = 0,
  update_interval = 1000, -- Update every second
}

-- Get container status for statusline display
function M.get_status()
  local cfg = config.get()
  if not cfg or not cfg.ui or not cfg.ui.status_line then
    return ''
  end

  -- Check cache
  local now = vim.loop.now()
  if cache.status and (now - cache.last_update) < cache.update_interval then
    return cache.status
  end

  -- Get current state
  local devcontainer = require('devcontainer')
  local state = devcontainer.get_state()

  if not state.initialized then
    cache.status = ''
    cache.last_update = now
    return ''
  end

  local icons = cfg.ui.icons or {}
  local status_text = ''

  if state.current_container then
    -- Get container status
    local status = state.container_status
    if status == 'running' then
      status_text = string.format('%s %s', icons.running or '✅', 'DevContainer')
    elseif status == 'exited' or status == 'stopped' then
      status_text = string.format('%s %s', icons.stopped or '⏹️', 'DevContainer')
    elseif status == 'created' then
      status_text = string.format('%s %s', icons.building or '🔨', 'DevContainer')
    else
      status_text = string.format('%s %s', icons.container or '🐳', 'DevContainer')
    end
  else
    -- No container
    local parser = require('devcontainer.parser')
    local devcontainer_path = parser.find_devcontainer_json()
    if devcontainer_path then
      -- devcontainer.json exists but no container
      status_text = string.format('%s %s', icons.stopped or '⏹️', 'DevContainer (available)')
    end
  end

  -- Cache the result
  cache.status = status_text
  cache.last_update = now

  return status_text
end

-- Get detailed status for custom statuslines
function M.get_detailed_status()
  local cfg = config.get()
  if not cfg or not cfg.ui or not cfg.ui.status_line then
    return {}
  end

  local devcontainer = require('devcontainer')
  local state = devcontainer.get_state()

  local details = {
    enabled = cfg.ui.status_line,
    initialized = state.initialized,
    has_container = state.current_container ~= nil,
    container_id = state.current_container,
    container_status = state.container_status,
    config_name = state.current_config and state.current_config.name or nil,
  }

  -- Add terminal session info
  local terminal = require('devcontainer.terminal')
  local sessions = terminal.list_sessions()
  details.terminal_sessions = vim.tbl_count(sessions)
  details.active_terminal = nil
  for name, session in pairs(sessions) do
    if session.active then
      details.active_terminal = name
      break
    end
  end

  return details
end

-- Component for lualine
function M.lualine_component()
  return function()
    return M.get_status()
  end
end

-- Component for lightline
function M.lightline_component()
  return M.get_status()
end

-- Clear cache (useful when state changes)
function M.clear_cache()
  cache.status = nil
  cache.last_update = 0
end

-- Setup autocommands to clear cache on state changes
function M.setup()
  local cfg = config.get()
  if not cfg or not cfg.ui or not cfg.ui.status_line then
    return
  end

  -- Create autocommand group
  local group = vim.api.nvim_create_augroup('DevcontainerStatusline', { clear = true })

  -- Clear cache on relevant events
  vim.api.nvim_create_autocmd('User', {
    group = group,
    pattern = {
      'DevcontainerStarted',
      'DevcontainerStopped',
      'DevcontainerBuilt',
      'DevcontainerOpened',
      'DevcontainerClosed',
    },
    callback = function()
      M.clear_cache()
    end,
  })

  -- Also clear cache periodically for external changes
  vim.api.nvim_create_autocmd('CursorHold', {
    group = group,
    callback = function()
      M.clear_cache()
    end,
  })

  log.debug('StatusLine integration setup complete')
end

return M
