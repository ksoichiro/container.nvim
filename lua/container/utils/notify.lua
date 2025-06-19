-- lua/devcontainer/utils/notify.lua
-- Centralized notification system with level control

local M = {}

-- Lazy load config to avoid circular dependency
local config = nil
local function get_config()
  if not config then
    local ok, c = pcall(require, 'container.config')
    if ok then
      config = c
    end
  end
  return config
end

-- Notification levels (higher number = more important)
local LEVELS = {
  debug = 1,
  info = 2,
  warn = 3,
  error = 4,
}

-- Notification categories
local CATEGORIES = {
  -- Critical operations that users should always know about
  critical = 'critical',
  -- Container lifecycle events (start, stop, attach)
  container = 'container',
  -- Terminal operations (create, switch, close)
  terminal = 'terminal',
  -- UI/UX feedback (copied, opened, etc.)
  ui = 'ui',
  -- Status information (no sessions found, etc.)
  status = 'status',
}

-- Determine if notification should be shown based on level and category
local function should_notify(level, category)
  local c = get_config()
  if not c then
    return true -- Default to showing notifications if config not loaded
  end

  local cfg = c.get()
  if not cfg or not cfg.ui or not cfg.ui.show_notifications then
    return false
  end

  local notification_level = cfg.ui.notification_level or 'normal'

  -- Always show errors
  if level == 'error' then
    return true
  end

  -- Silent mode: only show errors
  if notification_level == 'silent' then
    return false
  end

  -- Minimal mode: only show critical and container operations
  if notification_level == 'minimal' then
    return category == CATEGORIES.critical or category == CATEGORIES.container
  end

  -- Normal mode: show critical, container, and warnings
  if notification_level == 'normal' then
    return category == CATEGORIES.critical or category == CATEGORIES.container or level == 'warn'
  end

  -- Verbose mode: show everything
  if notification_level == 'verbose' then
    return true
  end

  return false
end

-- Send notification with level and category filtering
function M.notify(message, level, category, opts)
  level = level or 'info'
  category = category or CATEGORIES.status
  opts = opts or {}

  if not should_notify(level, category) then
    return
  end

  -- Convert level to vim.log.levels
  local vim_level = vim.log.levels.INFO
  if level == 'error' then
    vim_level = vim.log.levels.ERROR
  elseif level == 'warn' then
    vim_level = vim.log.levels.WARN
  elseif level == 'info' then
    vim_level = vim.log.levels.INFO
  end

  -- Set default title
  if not opts.title then
    opts.title = 'container.nvim'
  end

  vim.notify(message, vim_level, opts)
end

-- Convenience functions for different categories
function M.critical(message, level, opts)
  return M.notify(message, level or 'error', CATEGORIES.critical, opts)
end

function M.container(message, level, opts)
  return M.notify(message, level or 'info', CATEGORIES.container, opts)
end

function M.terminal(message, level, opts)
  return M.notify(message, level or 'info', CATEGORIES.terminal, opts)
end

function M.ui(message, level, opts)
  return M.notify(message, level or 'info', CATEGORIES.ui, opts)
end

function M.status(message, level, opts)
  return M.notify(message, level or 'info', CATEGORIES.status, opts)
end

-- Export categories for external use
M.CATEGORIES = CATEGORIES

return M
