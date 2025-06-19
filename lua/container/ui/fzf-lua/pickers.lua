-- lua/devcontainer/ui/fzf-lua/pickers.lua
-- fzf-lua integration for container.nvim

local M = {}

local log = require('container.utils.log')
local notify = require('container.utils.notify')

-- Check if fzf-lua is available
local function check_fzf_lua()
  local ok, fzf_lua = pcall(require, 'fzf-lua')
  if not ok then
    notify.critical('fzf-lua is not installed. Please install ibhagwan/fzf-lua')
    return false, nil
  end
  return true, fzf_lua
end

-- Container/Project picker
function M.containers(opts)
  opts = opts or {}
  local ok, fzf_lua = check_fzf_lua()
  if not ok then
    return
  end

  log.debug('FzfPicker: Starting containers picker')

  -- Get devcontainer projects (similar to telescope implementation)
  local parser = require('container.parser')
  local docker = require('container.docker')

  local containers = docker.list_devcontainers()
  local projects = parser.find_devcontainer_projects(vim.fn.getcwd())

  -- Build entries
  local entries = {}
  local entry_map = {}

  -- Add running containers
  for _, container in ipairs(containers) do
    local display = string.format('[RUNNING] %s (%s)', container.name, container.status)
    table.insert(entries, display)
    entry_map[display] = { type = 'container', container = container }
  end

  -- Add project directories with devcontainer.json
  for _, project in ipairs(projects) do
    local name = project.config and project.config.name or 'Unnamed'
    local display = string.format('%s (%s)', name, project.path)
    table.insert(entries, display)
    entry_map[display] = { type = 'project', project = project }
  end

  if #entries == 0 then
    notify.ui('No devcontainers or projects found')
    return
  end

  log.debug('FzfPicker: Found %d containers', #entries)

  fzf_lua.fzf_exec(entries, {
    prompt = 'DevContainers> ',
    preview = function(selected)
      local entry = entry_map[selected[1]]
      if entry then
        if entry.type == 'container' then
          return string.format(
            'Container: %s\nStatus: %s\nImage: %s\nPath: %s',
            entry.container.name,
            entry.container.status,
            entry.container.image or 'N/A',
            entry.container.project_path or 'N/A'
          )
        elseif entry.type == 'project' then
          local config_path = entry.project.devcontainer_path
          if config_path and vim.fn.filereadable(config_path) == 1 then
            local config_content = vim.fn.readfile(config_path)
            return table.concat(config_content, '\n')
          else
            return string.format(
              'Project: %s\nPath: %s\nConfig: %s\ndevcontainer.json not readable',
              entry.project.name,
              entry.project.path,
              config_path or 'Not found'
            )
          end
        end
      end
      return nil
    end,
    actions = {
      ['default'] = function(selected)
        local entry = entry_map[selected[1]]
        if entry then
          if entry.type == 'container' then
            log.debug('FzfPicker: Selected container: %s', entry.container.name)
            require('container').attach(entry.container.name)
          elseif entry.type == 'project' then
            log.debug('FzfPicker: Selected project path: %s', entry.project.path)
            require('container').open(entry.project.path)
          end
        end
      end,
    },
  })
end

-- Terminal session picker
function M.sessions(opts)
  opts = opts or {}
  local ok, fzf_lua = check_fzf_lua()
  if not ok then
    return
  end

  log.debug('FzfPicker: Starting sessions picker')

  local terminal = require('container.terminal')
  local status = terminal.get_status()
  local sessions = status.sessions

  if not sessions or #sessions == 0 then
    notify.ui('No terminal sessions found')
    return
  end

  -- Build entries
  local entries = {}
  local session_map = {}

  for _, session in ipairs(sessions) do
    local status_icon = session:is_valid() and '●' or '○'
    local time_str = os.date('%H:%M:%S', session.last_accessed)
    local display = string.format('%s %s (last: %s)', status_icon, session.name, time_str)

    table.insert(entries, display)
    session_map[display] = session
  end

  log.debug('FzfPicker: Found %d sessions', #entries)

  fzf_lua.fzf_exec(entries, {
    prompt = 'Terminal Sessions> ',
    preview = function(selected)
      local session = session_map[selected[1]]
      if session then
        return string.format(
          'Session: %s\nContainer: %s\nCreated: %s\nLast accessed: %s\nValid: %s',
          session.name,
          session.container_id and session.container_id:sub(1, 12) or 'N/A',
          os.date('%Y-%m-%d %H:%M:%S', session.created_at),
          os.date('%Y-%m-%d %H:%M:%S', session.last_accessed),
          session:is_valid() and 'Yes' or 'No'
        )
      end
      return nil
    end,
    actions = {
      ['default'] = function(selected)
        local session = session_map[selected[1]]
        if session then
          log.debug('FzfPicker: Selected session: %s', session.name)
          local display = require('container.terminal.display')
          display.switch_to_session(session)
        end
      end,
      ['ctrl-d'] = function(selected)
        local session = session_map[selected[1]]
        if session then
          log.debug('FzfPicker: Closing session: %s', session.name)
          terminal.close_session(session.name)
        end
      end,
    },
  })
end

-- Port management picker
function M.ports(opts)
  opts = opts or {}
  local ok, fzf_lua = check_fzf_lua()
  if not ok then
    return
  end

  log.debug('FzfPicker: Starting ports picker')

  local docker = require('container.docker')
  local all_ports = docker.get_forwarded_ports()

  if not all_ports or #all_ports == 0 then
    notify.ui('No forwarded ports found')
    return
  end

  -- Build entries
  local entries = {}
  local port_map = {}

  for _, port in ipairs(all_ports) do
    if port.local_port then
      local display =
        string.format('%d -> %d (%s)', port.local_port, port.container_port or 0, port.container_name or 'unknown')

      table.insert(entries, display)
      port_map[display] = port
    end
  end

  if #entries == 0 then
    notify.ui('No valid forwarded ports found')
    return
  end

  log.debug('FzfPicker: Found %d ports', #entries)

  fzf_lua.fzf_exec(entries, {
    prompt = 'Port Forwarding> ',
    preview = function(selected)
      local port = port_map[selected[1]]
      if port then
        local url = string.format('http://localhost:%d', port.local_port)
        return string.format(
          'Local Port: %d\nContainer Port: %d\nURL: %s\nContainer: %s\nProtocol: %s\nBind Address: %s',
          port.local_port,
          port.container_port or 0,
          url,
          port.container_name or 'unknown',
          port.protocol or 'tcp',
          port.bind_address or '0.0.0.0'
        )
      end
      return nil
    end,
    actions = {
      ['default'] = function(selected)
        local port = port_map[selected[1]]
        if port and port.local_port then
          local url = string.format('http://localhost:%d', port.local_port)
          vim.fn.jobstart({ 'open', url }, { detach = true })
          notify.status('Opening ' .. url)
        end
      end,
      ['ctrl-y'] = function(selected)
        local port = port_map[selected[1]]
        if port and port.local_port then
          local url = string.format('http://localhost:%d', port.local_port)
          vim.fn.setreg('+', url)
          notify.status('Copied: ' .. url)
        end
      end,
      ['ctrl-x'] = function(selected)
        local port = port_map[selected[1]]
        if port then
          docker.stop_port_forward(port)
          notify.status('Stopped port forwarding')
        end
      end,
    },
  })
end

-- Command history picker
function M.history(opts)
  opts = opts or {}
  local ok, fzf_lua = check_fzf_lua()
  if not ok then
    return
  end

  log.debug('FzfPicker: Starting history picker')

  -- Try to get command history
  local history_ok, history_module = pcall(require, 'container.history')
  local history = nil

  if history_ok then
    history = history_module.get_exec_history()
  end

  if not history or #history == 0 then
    notify.ui('No command history found')
    return
  end

  -- Build entries
  local entries = {}
  local history_map = {}

  for _, entry in ipairs(history) do
    local status_icon = entry.exit_code == 0 and '✅' or '❌'
    local timestamp = entry.timestamp or os.date('%H:%M:%S')
    local display = string.format('%s %s %s', status_icon, timestamp, entry.command or '')

    table.insert(entries, display)
    history_map[display] = entry
  end

  log.debug('FzfPicker: Found %d history entries', #entries)

  fzf_lua.fzf_exec(entries, {
    prompt = 'Command History> ',
    preview = function(selected)
      local entry = history_map[selected[1]]
      if entry then
        local lines = {
          'Command: ' .. (entry.command or 'N/A'),
          'Container: ' .. (entry.container_name or 'unknown'),
          'Timestamp: ' .. (entry.timestamp or 'N/A'),
          'Exit Code: ' .. tostring(entry.exit_code or 'N/A'),
          'Duration: ' .. (entry.duration and string.format('%.2fs', entry.duration) or 'N/A'),
          '',
          'Output:',
          entry.output or 'No output',
        }
        return table.concat(lines, '\n')
      end
      return nil
    end,
    actions = {
      ['default'] = function(selected)
        local entry = history_map[selected[1]]
        if entry and entry.command then
          log.debug('FzfPicker: Re-executing command: %s', entry.command)
          require('container').exec(entry.command)
        end
      end,
      ['ctrl-y'] = function(selected)
        local entry = history_map[selected[1]]
        if entry and entry.command then
          vim.fn.setreg('+', entry.command)
          notify.status('Copied command to clipboard')
        end
      end,
    },
  })
end

return M
