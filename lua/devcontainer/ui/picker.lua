-- lua/devcontainer/ui/picker.lua
-- Unified picker interface supporting multiple backends

local M = {}

local log = require('devcontainer.utils.log')
local notify = require('devcontainer.utils.notify')

-- Detect and get available picker
local function get_available_picker()
  local config = require('devcontainer.config').get()
  local configured_picker = config.ui.picker or 'telescope'

  if configured_picker == 'telescope' then
    local ok, _ = pcall(require, 'telescope')
    if ok then
      return 'telescope'
    else
      log.warn('Telescope is not available, falling back to fzf-lua')
      configured_picker = 'fzf-lua'
    end
  end

  if configured_picker == 'fzf-lua' then
    local ok, _ = pcall(require, 'fzf-lua')
    if ok then
      return 'fzf-lua'
    else
      log.warn('fzf-lua is not available, falling back to vim.ui.select')
      return 'vim.ui.select'
    end
  end

  return 'vim.ui.select'
end

-- Container/Project picker
function M.containers(opts)
  opts = opts or {}
  local picker = get_available_picker()

  log.debug('Using picker: %s for containers', picker)

  if picker == 'telescope' then
    local pickers = require('devcontainer.ui.telescope.pickers')
    return pickers.containers(opts)
  elseif picker == 'fzf-lua' then
    local pickers = require('devcontainer.ui.fzf-lua.pickers')
    return pickers.containers(opts)
  else
    -- vim.ui.select fallback
    local parser = require('devcontainer.parser')
    local projects = parser.find_devcontainer_projects(vim.fn.getcwd())

    if #projects == 0 then
      notify.ui('No devcontainers or projects found')
      return
    end

    local items = {}
    for _, project in ipairs(projects) do
      local name = project.config and project.config.name or 'Unnamed'
      table.insert(items, {
        name = name,
        path = project.path,
        display = string.format('%s (%s)', name, project.path),
      })
    end

    vim.ui.select(items, {
      prompt = 'Select DevContainer:',
      format_item = function(item)
        return item.display
      end,
    }, function(choice)
      if choice then
        require('devcontainer').open(choice.path)
      end
    end)
  end
end

-- Terminal session picker
function M.sessions(opts)
  opts = opts or {}
  local picker = get_available_picker()

  log.debug('Using picker: %s for sessions', picker)

  if picker == 'telescope' then
    local pickers = require('devcontainer.ui.telescope.pickers')
    return pickers.sessions(opts)
  elseif picker == 'fzf-lua' then
    local pickers = require('devcontainer.ui.fzf-lua.pickers')
    return pickers.sessions(opts)
  else
    -- vim.ui.select fallback
    local terminal = require('devcontainer.terminal')
    local status = terminal.get_status()
    local sessions = status.sessions

    if not sessions or #sessions == 0 then
      notify.ui('No terminal sessions found')
      return
    end

    vim.ui.select(sessions, {
      prompt = 'Select Terminal Session:',
      format_item = function(session)
        local status_icon = session:is_valid() and '●' or '○'
        local time_str = os.date('%H:%M:%S', session.last_accessed)
        return string.format('%s %s (last: %s)', status_icon, session.name, time_str)
      end,
    }, function(choice)
      if choice then
        local display = require('devcontainer.terminal.display')
        display.switch_to_session(choice)
      end
    end)
  end
end

-- Port management picker
function M.ports(opts)
  opts = opts or {}
  local picker = get_available_picker()

  log.debug('Using picker: %s for ports', picker)

  if picker == 'telescope' then
    local pickers = require('devcontainer.ui.telescope.pickers')
    return pickers.ports_simple(opts)
  elseif picker == 'fzf-lua' then
    local pickers = require('devcontainer.ui.fzf-lua.pickers')
    return pickers.ports(opts)
  else
    -- vim.ui.select fallback
    local docker = require('devcontainer.docker')
    local all_ports = docker.get_forwarded_ports()

    log.debug('vim.ui.select: get_forwarded_ports returned %d ports', all_ports and #all_ports or 0)

    if not all_ports or #all_ports == 0 then
      notify.ui('No forwarded ports found. Make sure your container is running with port mappings.')
      return
    end

    local valid_ports = {}
    for _, port in ipairs(all_ports) do
      if port.local_port then
        table.insert(valid_ports, port)
      end
    end

    if #valid_ports == 0 then
      notify.ui('No valid forwarded ports found')
      return
    end

    vim.ui.select(valid_ports, {
      prompt = 'Select Port:',
      format_item = function(port)
        return string.format(
          '%d -> %d (%s)',
          port.local_port,
          port.container_port or 0,
          port.container_name or 'unknown'
        )
      end,
    }, function(choice)
      if choice and choice.local_port then
        local url = string.format('http://localhost:%d', choice.local_port)
        vim.fn.jobstart({ 'open', url }, { detach = true })
        notify.status('Opening ' .. url)
      end
    end)
  end
end

-- Command history picker
function M.history(opts)
  opts = opts or {}
  local picker = get_available_picker()

  log.debug('Using picker: %s for history', picker)

  if picker == 'telescope' then
    local pickers = require('devcontainer.ui.telescope.pickers')
    return pickers.history(opts)
  elseif picker == 'fzf-lua' then
    local pickers = require('devcontainer.ui.fzf-lua.pickers')
    return pickers.history(opts)
  else
    -- vim.ui.select fallback
    -- TODO: Implement command history functionality
    notify.ui('Command history functionality is under development for vim.ui.select')
  end
end

return M
