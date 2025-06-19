-- lua/telescope/_extensions/container.lua
-- Telescope extension for container.nvim

local has_telescope, telescope = pcall(require, 'telescope')
if not has_telescope then
  error('This plugin requires nvim-telescope/telescope.nvim')
end

local pickers = require('devcontainer.ui.telescope.pickers')

return telescope.register_extension({
  setup = function(ext_config, config)
    -- Extension setup can be used for configuration
  end,
  exports = {
    container = pickers.containers,
    containers = pickers.containers,
    sessions = pickers.sessions,
    ports = pickers.ports,
    history = pickers.history,
  },
})
