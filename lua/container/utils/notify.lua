-- lua/container/utils/notify.lua
-- Unified notification system with deduplication and categorization

local M = {}

-- Message deduplication cache
local message_cache = {}
local cache_timeout = 5000 -- 5 seconds
local progress_messages = {}

-- Notification levels
local LEVELS = {
  silent = 1,
  minimal = 2,
  normal = 3,
  verbose = 4,
}

-- Message categories
local CATEGORIES = {
  critical = { level = 1, vim_level = vim.log.levels.ERROR }, -- Always shown (errors)
  container = { level = 2, vim_level = vim.log.levels.INFO }, -- Container operations
  status = { level = 3, vim_level = vim.log.levels.INFO }, -- General status
  progress = { level = 3, vim_level = vim.log.levels.INFO }, -- Progress updates
  debug = { level = 4, vim_level = vim.log.levels.DEBUG }, -- Verbose information
}

-- Get current notification level from config
local function get_notification_level()
  local config = require('container.config')
  local level_name = config.get_value('ui.notification_level') or 'normal'
  return LEVELS[level_name] or LEVELS.normal
end

-- Check if notifications are enabled
local function notifications_enabled()
  local config = require('container.config')
  return config.get_value('ui.show_notifications') ~= false
end

-- Clean up old cache entries
local function cleanup_cache()
  local now = (vim.loop and vim.loop.now()) or os.time() * 1000
  for key, entry in pairs(message_cache) do
    if now - entry.timestamp > cache_timeout then
      message_cache[key] = nil
    end
  end
end

-- Check if message should be deduplicated
local function should_deduplicate(message, category)
  cleanup_cache()

  local cache_key = category .. ':' .. message
  local now = (vim.loop and vim.loop.now()) or os.time() * 1000

  if message_cache[cache_key] then
    -- Update timestamp but don't show message
    message_cache[cache_key].timestamp = now
    return true
  end

  -- Add to cache
  message_cache[cache_key] = { timestamp = now }
  return false
end

-- Core notification function
local function notify(message, category, opts)
  opts = opts or {}

  if not notifications_enabled() then
    return
  end

  local category_config = CATEGORIES[category]
  if not category_config then
    category_config = CATEGORIES.status
  end

  local notification_level = get_notification_level()

  -- Check if this category should be shown at current level
  if category_config.level > notification_level then
    return
  end

  -- Handle deduplication unless explicitly disabled
  if not opts.no_dedupe and should_deduplicate(message, category) then
    return
  end

  -- Show notification
  if vim.notify then
    vim.notify(message, category_config.vim_level, {
      title = opts.title or 'Container',
    })
  else
    -- Fallback for environments without vim.notify
    print(message)
  end
end

-- Public API functions for different categories

-- Critical messages (always shown except in silent mode)
function M.critical(message, opts)
  notify(message, 'critical', opts)
end

-- Container lifecycle events
function M.container(message, opts)
  notify(message, 'container', opts)
end

-- General status messages
function M.status(message, opts)
  notify(message, 'status', opts)
end

-- Debug/verbose messages
function M.debug(message, opts)
  notify(message, 'debug', opts)
end

-- Progress messages with consolidation
function M.progress(operation, step, total, message, opts)
  opts = opts or {}

  if not notifications_enabled() then
    return
  end

  local notification_level = get_notification_level()
  if CATEGORIES.progress.level > notification_level then
    return
  end

  -- Store progress state
  if not progress_messages[operation] then
    progress_messages[operation] = {}
  end

  local progress_info = progress_messages[operation]
  local now = (vim.loop and vim.loop.now()) or os.time() * 1000

  -- Consolidate rapid progress updates
  if progress_info.last_update and (now - progress_info.last_update) < 1000 then
    -- Update internal state but don't notify
    progress_info.step = step
    progress_info.total = total
    progress_info.message = message
    return
  end

  progress_info.last_update = now
  progress_info.step = step
  progress_info.total = total
  progress_info.message = message

  -- Format progress message
  local progress_text
  if total and total > 0 then
    local percentage = math.floor((step / total) * 100)
    progress_text = string.format('%s (%d/%d - %d%%)', message, step, total, percentage)
  else
    progress_text = message
  end

  -- Show consolidated progress
  notify(progress_text, 'progress', vim.tbl_extend('force', opts, { no_dedupe = true }))
end

-- Clear progress messages for an operation
function M.clear_progress(operation)
  if operation then
    progress_messages[operation] = nil
  else
    progress_messages = {}
  end
end

-- Force clear all cached messages
function M.clear_cache()
  message_cache = {}
  progress_messages = {}
end

-- Convenience functions for common patterns

-- Show error with critical level
function M.error(message, opts)
  M.critical('Error: ' .. message, opts)
end

-- Show warning
function M.warn(message, opts)
  M.status('Warning: ' .. message, opts)
end

-- Show success message
function M.success(message, opts)
  M.container('✅ ' .. message, opts)
end

-- Show info message
function M.info(message, opts)
  M.status(message, opts)
end

-- Get current notification statistics (for debugging)
function M.get_stats()
  return {
    cache_entries = vim.tbl_count(message_cache),
    progress_operations = vim.tbl_count(progress_messages),
    notification_level = get_notification_level(),
    notifications_enabled = notifications_enabled(),
  }
end

return M
