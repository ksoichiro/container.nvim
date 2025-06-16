-- Example: Using devcontainer.nvim User events for statusline updates
-- This file demonstrates how to listen for devcontainer lifecycle events

-- Setup autocmds to listen for devcontainer events
local augroup = vim.api.nvim_create_augroup('DevcontainerStatusline', { clear = true })

-- DevcontainerOpened: Fired when a devcontainer configuration is loaded
vim.api.nvim_create_autocmd('User', {
  pattern = 'DevcontainerOpened',
  group = augroup,
  callback = function(args)
    local data = args.data or {}
    print(string.format('DevcontainerOpened: %s', data.container_name or 'unknown'))
    -- Update your statusline here
    -- Example: vim.g.devcontainer_status = 'opened'
    -- Example: vim.g.devcontainer_name = data.container_name
  end,
})

-- DevcontainerBuilt: Fired when a container image is built/prepared
vim.api.nvim_create_autocmd('User', {
  pattern = 'DevcontainerBuilt',
  group = augroup,
  callback = function(args)
    local data = args.data or {}
    print(string.format('DevcontainerBuilt: %s', data.container_name or 'unknown'))
    -- Update your statusline here
    -- Example: vim.g.devcontainer_status = 'built'
  end,
})

-- DevcontainerStarted: Fired when a container starts successfully
vim.api.nvim_create_autocmd('User', {
  pattern = 'DevcontainerStarted',
  group = augroup,
  callback = function(args)
    local data = args.data or {}
    print(string.format('DevcontainerStarted: %s (ID: %s)',
      data.container_name or 'unknown',
      data.container_id and data.container_id:sub(1, 12) or 'unknown'))
    -- Update your statusline here
    -- Example: vim.g.devcontainer_status = 'running'
    -- Example: vim.g.devcontainer_id = data.container_id
  end,
})

-- DevcontainerStopped: Fired when a container stops
vim.api.nvim_create_autocmd('User', {
  pattern = 'DevcontainerStopped',
  group = augroup,
  callback = function(args)
    local data = args.data or {}
    print(string.format('DevcontainerStopped: %s', data.container_name or 'unknown'))
    -- Update your statusline here
    -- Example: vim.g.devcontainer_status = 'stopped'
  end,
})

-- DevcontainerClosed: Fired when a devcontainer is closed/reset
vim.api.nvim_create_autocmd('User', {
  pattern = 'DevcontainerClosed',
  group = augroup,
  callback = function(args)
    local data = args.data or {}
    print(string.format('DevcontainerClosed: %s', data.container_name or 'unknown'))
    -- Update your statusline here
    -- Example: vim.g.devcontainer_status = 'closed'
    -- Example: vim.g.devcontainer_name = nil
    -- Example: vim.g.devcontainer_id = nil
  end,
})

-- Example statusline component function
-- You can use this in your statusline configuration
function _G.devcontainer_statusline()
  local status = vim.g.devcontainer_status or 'none'
  local name = vim.g.devcontainer_name

  if status == 'none' then
    return ''
  elseif status == 'opened' then
    return string.format('📦 %s (opened)', name or 'devcontainer')
  elseif status == 'built' then
    return string.format('📦 %s (built)', name or 'devcontainer')
  elseif status == 'running' then
    return string.format('📦 %s ✓', name or 'devcontainer')
  elseif status == 'stopped' then
    return string.format('📦 %s ✗', name or 'devcontainer')
  elseif status == 'closed' then
    return ''
  end

  return string.format('📦 %s (%s)', name or 'devcontainer', status)
end

-- Example usage in statusline (for lualine)
-- Add this to your lualine config:
-- {
--   sections = {
--     lualine_x = {
--       { devcontainer_statusline },
--     },
--   },
-- }
