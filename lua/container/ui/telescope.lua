-- lua/container/ui/telescope.lua
-- Telescope integration for container.nvim

local M = {}

-- Check if telescope is available
local function check_telescope()
  local ok, telescope = pcall(require, 'telescope')
  if not ok then
    return nil
  end
  return telescope
end

-- Setup telescope extension
function M.setup()
  local telescope = check_telescope()
  if not telescope then
    -- Silently fail if telescope is not available
    return false
  end

  -- Only try to load extension if it exists
  local ok = pcall(telescope.load_extension, 'container')
  if not ok then
    -- Extension not available yet, register it
    M.register_extension()
    -- Try loading again
    pcall(telescope.load_extension, 'container')
  end

  return true
end

-- Register telescope extension
function M.register_extension()
  local telescope = check_telescope()
  if not telescope then
    return
  end

  telescope.register_extension({
    setup = function(ext_config, config)
      -- Extension setup logic
    end,
    exports = {
      containers = require('container.ui.telescope.pickers').containers,
      sessions = require('container.ui.telescope.pickers').sessions,
      ports = require('container.ui.telescope.pickers').ports,
      history = require('container.ui.telescope.pickers').history,
    },
  })
end

-- Convenience functions
function M.containers(opts)
  require('telescope').extensions.container.containers(opts)
end

function M.sessions(opts)
  require('telescope').extensions.container.sessions(opts)
end

function M.ports(opts)
  require('telescope').extensions.container.ports(opts)
end

function M.history(opts)
  require('telescope').extensions.container.history(opts)
end

return M
