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

-- Format status text using template
local function format_status(template, icon, name, status, labels)
  if not template then
    return ''
  end

  local formatted = template
  formatted = formatted:gsub('{icon}', icon or '')
  formatted = formatted:gsub('{name}', name or '')
  formatted = formatted:gsub('{status}', status or '')

  -- Handle available suffix
  if labels and labels.available_suffix then
    formatted = formatted:gsub('%(available%)', '(' .. labels.available_suffix .. ')')
  end

  return formatted
end

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
  local statusline_config = cfg.ui.statusline or {}
  local formats = statusline_config.format or {}
  local labels = statusline_config.labels or {}
  local show_container_name = statusline_config.show_container_name ~= false
  local default_format = statusline_config.default_format or '{icon} {name}'

  local status_text = ''

  if state.current_container then
    -- Get container status
    local status = state.container_status
    local icon = ''
    local format_key = ''

    if status == 'running' then
      icon = icons.running or '✅'
      format_key = 'running'
    elseif status == 'exited' or status == 'stopped' then
      icon = icons.stopped or '⏹️'
      format_key = 'stopped'
    elseif status == 'created' then
      icon = icons.building or '🔨'
      format_key = 'building'
    else
      icon = icons.container or '🐳'
      format_key = 'error'
    end

    -- Determine container name
    local container_name = ''
    if show_container_name and state.current_config and state.current_config.name then
      container_name = state.current_config.name
    else
      container_name = labels.container_name or 'DevContainer'
    end

    -- Use format template
    local format_template = formats[format_key] or default_format
    status_text = format_status(format_template, icon, container_name, status, labels)
  else
    -- No container
    local parser = require('devcontainer.parser')
    local devcontainer_path = parser.find_devcontainer_json()
    if devcontainer_path then
      -- devcontainer.json exists but no container
      local icon = icons.stopped or '⏹️'
      local container_name = labels.container_name or 'DevContainer'

      -- Use available format template
      local format_template = formats.available or default_format
      status_text = format_status(format_template, icon, container_name, 'available', labels)
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
