-- lua/devcontainer/ui/statusline.lua
-- StatusLine integration for devcontainer status display

local M = {}

local config = require('container.config')
local log = require('container.utils.log')

-- Cache for performance
local cache = {
  status = nil,
  last_update = 0,
  update_interval = 5000, -- Update every 5 seconds
  devcontainer_available = nil,
  devcontainer_check_time = 0,
  devcontainer_check_interval = 30000, -- Check devcontainer.json existence every 30 seconds
}

-- Global state for container operations
if not _G.container_operation_state then
  _G.container_operation_state = {
    stopping = {
      active = false,
      start_time = nil,
      container_name = nil,
      refresh_timer = nil,
    },
    -- Future: building, starting, etc.
  }
end

-- Spinner characters for progress indication
local spinner_chars = { '⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏' }

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

  -- Check for active operations first (bypass cache during operations)
  local now = vim.loop.now()
  if _G.container_operation_state.stopping.active then
    local elapsed = now - _G.container_operation_state.stopping.start_time
    local frame = math.floor(elapsed / 100) % #spinner_chars + 1
    local container_name = _G.container_operation_state.stopping.container_name or 'Container'

    local icons = cfg.ui.icons or {}
    local statusline_config = cfg.ui.statusline or {}
    local formats = statusline_config.format or {}
    local labels = statusline_config.labels or {}
    local default_format = statusline_config.default_format or '{icon} {name}'

    local stopping_icon = icons.stopping or '🚫'
    local spinner_icon = spinner_chars[frame]
    local combined_icon = stopping_icon .. ' ' .. spinner_icon

    -- Use format template for stopping state
    local format_template = formats.stopping or default_format .. ' Stopping...'
    return format_status(format_template, combined_icon, container_name, 'stopping', labels)
  end

  -- Check cache for normal status
  if cache.status and (now - cache.last_update) < cache.update_interval then
    return cache.status
  end

  -- Get current state
  local devcontainer = require('container')
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
    local icon, format_key

    if status == 'running' then
      icon = icons.running or '🚀'
      format_key = 'running'
    elseif status == 'exited' or status == 'stopped' then
      icon = icons.stopped or '📦'
      format_key = 'stopped'
    elseif status == 'created' then
      icon = icons.building or '🔨'
      format_key = 'building'
    else
      icon = icons.container or '🐳'
      format_key = 'error'
    end

    -- Determine container name
    local container_name
    if show_container_name and state.current_config and state.current_config.name then
      container_name = state.current_config.name
    else
      container_name = labels.container_name or 'DevContainer'
    end

    -- Use format template
    local format_template = formats[format_key] or default_format
    status_text = format_status(format_template, icon, container_name, status, labels)
  else
    -- No container - check if devcontainer.json exists
    local devcontainer_available

    -- Check cached result or refresh if needed
    if
      cache.devcontainer_available ~= nil
      and (now - cache.devcontainer_check_time) < cache.devcontainer_check_interval
    then
      devcontainer_available = cache.devcontainer_available
    else
      -- Refresh devcontainer availability (this will trigger the debug message)
      local parser = require('container.parser')
      local devcontainer_path = parser.find_devcontainer_json()
      devcontainer_available = devcontainer_path ~= nil

      -- Cache the result
      cache.devcontainer_available = devcontainer_available
      cache.devcontainer_check_time = now
    end

    if devcontainer_available then
      -- devcontainer.json exists but no container
      local icon = icons.available or '📋'
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

  local devcontainer = require('container')
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
  local terminal = require('container.terminal')
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

-- Component for lualine (now with automatic refresh during operations)
function M.lualine_component()
  return function()
    return M.get_status()
  end
end

-- Legacy function name for backward compatibility
function M.lualine_component_with_refresh()
  return M.lualine_component()
end

-- Component for lightline
function M.lightline_component()
  return M.get_status()
end

-- Clear cache (useful when state changes)
function M.clear_cache()
  cache.status = nil
  cache.last_update = 0
  cache.devcontainer_available = nil
  cache.devcontainer_check_time = 0
end

-- Set stopping state
function M.set_stopping_state(active, container_name)
  _G.container_operation_state.stopping.active = active
  if active then
    _G.container_operation_state.stopping.start_time = vim.loop.now()
    _G.container_operation_state.stopping.container_name = container_name

    -- Start global refresh timer for all statuslines
    if not _G.container_operation_state.stopping.refresh_timer then
      _G.container_operation_state.stopping.refresh_timer = vim.uv.new_timer()
      _G.container_operation_state.stopping.refresh_timer:start(
        0,
        100,
        vim.schedule_wrap(function()
          if not _G.container_operation_state.stopping.active then
            if _G.container_operation_state.stopping.refresh_timer then
              _G.container_operation_state.stopping.refresh_timer:close()
              _G.container_operation_state.stopping.refresh_timer = nil
            end
            return
          end

          -- Refresh lualine if available
          local ok, lualine = pcall(require, 'lualine')
          if ok and lualine.refresh then
            lualine.refresh()
          end
        end)
      )
    end
  else
    _G.container_operation_state.stopping.container_name = nil

    -- Stop refresh timer
    if _G.container_operation_state.stopping.refresh_timer then
      _G.container_operation_state.stopping.refresh_timer:close()
      _G.container_operation_state.stopping.refresh_timer = nil
    end
  end

  M.clear_cache()
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
      'ContainerStarted',
      'ContainerStopped',
      'ContainerBuilt',
      'ContainerOpened',
      'ContainerClosed',
    },
    callback = function()
      M.clear_cache()
    end,
  })

  -- Clear cache when devcontainer.json files are modified
  vim.api.nvim_create_autocmd({ 'BufWritePost' }, {
    group = group,
    pattern = { 'devcontainer.json', '.devcontainer/devcontainer.json' },
    callback = function()
      M.clear_cache()
    end,
  })

  -- Removed CursorHold autocmd as it was causing excessive updates
  -- Status will update on a timer basis instead

  log.debug('StatusLine integration setup complete')
end

return M
