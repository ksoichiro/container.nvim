-- lua/devcontainer/ui/telescope.lua
-- Telescope integration for devcontainer.nvim

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
  local ok = pcall(telescope.load_extension, 'devcontainer')
  if not ok then
    -- Extension not available yet, register it
    M.register_extension()
    -- Try loading again
    pcall(telescope.load_extension, 'devcontainer')
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
      containers = require('devcontainer.ui.telescope.pickers').containers,
      sessions = require('devcontainer.ui.telescope.pickers').sessions,
      ports = require('devcontainer.ui.telescope.pickers').ports,
      history = require('devcontainer.ui.telescope.pickers').history,
    },
  })
end

-- Convenience functions
function M.containers(opts)
  require('telescope').extensions.devcontainer.containers(opts)
end

function M.sessions(opts)
  require('telescope').extensions.devcontainer.sessions(opts)
end

function M.ports(opts)
  require('telescope').extensions.devcontainer.ports(opts)
end

function M.history(opts)
  require('telescope').extensions.devcontainer.history(opts)
end

return M
