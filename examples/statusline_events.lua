-- Example: Using container.nvim User events for statusline updates
-- This file demonstrates how to listen for container lifecycle events

-- Setup autocmds to listen for container events
local augroup = vim.api.nvim_create_augroup('ContainerStatusline', { clear = true })

-- ContainerOpened: Fired when a container configuration is loaded
vim.api.nvim_create_autocmd('User', {
  pattern = 'ContainerOpened',
  group = augroup,
  callback = function(args)
    local data = args.data or {}
    print(string.format('ContainerOpened: %s', data.container_name or 'unknown'))
    -- Update your statusline here
    -- Example: vim.g.container_status = 'opened'
    -- Example: vim.g.container_name = data.container_name
  end,
})

-- ContainerBuilt: Fired when a container image is built/prepared
vim.api.nvim_create_autocmd('User', {
  pattern = 'ContainerBuilt',
  group = augroup,
  callback = function(args)
    local data = args.data or {}
    print(string.format('ContainerBuilt: %s', data.container_name or 'unknown'))
    -- Update your statusline here
    -- Example: vim.g.container_status = 'built'
  end,
})

-- ContainerStarted: Fired when a container starts successfully
vim.api.nvim_create_autocmd('User', {
  pattern = 'ContainerStarted',
  group = augroup,
  callback = function(args)
    local data = args.data or {}
    print(string.format('ContainerStarted: %s (ID: %s)',
      data.container_name or 'unknown',
      data.container_id and data.container_id:sub(1, 12) or 'unknown'))
    -- Update your statusline here
    -- Example: vim.g.container_status = 'running'
    -- Example: vim.g.container_id = data.container_id
  end,
})

-- ContainerStopped: Fired when a container stops
vim.api.nvim_create_autocmd('User', {
  pattern = 'ContainerStopped',
  group = augroup,
  callback = function(args)
    local data = args.data or {}
    print(string.format('ContainerStopped: %s', data.container_name or 'unknown'))
    -- Update your statusline here
    -- Example: vim.g.container_status = 'stopped'
  end,
})

-- ContainerClosed: Fired when a container is closed/reset
vim.api.nvim_create_autocmd('User', {
  pattern = 'ContainerClosed',
  group = augroup,
  callback = function(args)
    local data = args.data or {}
    print(string.format('ContainerClosed: %s', data.container_name or 'unknown'))
    -- Update your statusline here
    -- Example: vim.g.container_status = 'closed'
    -- Example: vim.g.container_name = nil
    -- Example: vim.g.container_id = nil
  end,
})

-- Example statusline component function
-- You can use this in your statusline configuration
function _G.container_statusline()
  local status = vim.g.container_status or 'none'
  local name = vim.g.container_name

  if status == 'none' then
    return ''
  elseif status == 'opened' then
    return string.format('📦 %s (opened)', name or 'container')
  elseif status == 'built' then
    return string.format('📦 %s (built)', name or 'container')
  elseif status == 'running' then
    return string.format('📦 %s ✓', name or 'container')
  elseif status == 'stopped' then
    return string.format('📦 %s ✗', name or 'container')
  elseif status == 'closed' then
    return ''
  end

  return string.format('📦 %s (%s)', name or 'container', status)
end

-- Example usage in statusline (for lualine)
-- Add this to your lualine config:
-- {
--   sections = {
--     lualine_x = {
--       { container_statusline },
--     },
--   },
-- }
