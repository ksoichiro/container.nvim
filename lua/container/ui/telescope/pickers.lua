-- lua/devcontainer/ui/telescope/pickers.lua
-- Telescope pickers for container.nvim

local M = {}

local pickers = require('telescope.pickers')
local finders = require('telescope.finders')
local conf = require('telescope.config').values
local actions = require('telescope.actions')
local action_state = require('telescope.actions.state')
local previewers = require('telescope.previewers')

-- Helper to create container display string
local function create_container_display(container)
  local status_icon = container.running and '🚀' or '📦'
  return string.format(
    '%-20s %s %-15s %-30s %s',
    container.name,
    status_icon,
    container.status,
    container.image,
    container.project_path or ''
  )
end

-- Devcontainer picker
function M.containers(opts)
  opts = opts or {}
  local docker = require('container.docker')
  local parser = require('container.parser')

  -- Get list of containers and potential devcontainer directories
  local containers = docker.list_devcontainers()
  local projects = parser.find_devcontainer_projects(opts.search_path or vim.fn.getcwd())

  -- Combine containers and projects
  local entries = {}

  -- Add running containers
  for _, container in ipairs(containers) do
    table.insert(entries, {
      type = 'container',
      container = container,
      display = create_container_display(container),
      ordinal = container.name .. ' ' .. container.status,
      value = vim.tbl_extend('force', container, { type = 'container' }),
    })
  end

  -- Add projects with devcontainer.json
  for _, project in ipairs(projects) do
    local container_name = docker.get_container_name(project.path)
    local is_running = vim.tbl_contains(
      vim.tbl_map(function(c)
        return c.name
      end, containers),
      container_name
    )

    if not is_running then
      table.insert(entries, {
        type = 'project',
        project = project,
        display = create_container_display({
          name = project.name,
          status = 'not started',
          image = project.config.image or 'unknown',
          project_path = project.path,
          running = false,
        }),
        ordinal = project.name .. ' not started',
        value = vim.tbl_extend('force', project, { type = 'project' }),
      })
    end
  end

  -- If no entries, show empty message
  if #entries == 0 then
    require('container.utils.notify').ui('No devcontainers or projects found')
    return
  end

  pickers
    .new(opts, {
      prompt_title = 'DevContainers',
      finder = finders.new_table({
        results = entries,
        entry_maker = function(entry)
          return {
            value = entry.value,
            display = entry.display,
            ordinal = entry.ordinal,
            type = entry.type,
          }
        end,
      }),
      sorter = conf.generic_sorter(opts),
      selection_strategy = 'reset',
      initial_mode = 'insert',
      previewer = previewers.new_buffer_previewer({
        title = 'DevContainer Info',
        define_preview = function(self, entry)
          local lines = {}

          if entry.type == 'container' then
            local container = entry.value
            table.insert(lines, '# Container Information')
            table.insert(lines, '')
            table.insert(lines, 'Name: ' .. container.name)
            table.insert(lines, 'Status: ' .. container.status)
            table.insert(lines, 'Image: ' .. container.image)
            table.insert(lines, 'ID: ' .. (container.id or 'N/A'))
            table.insert(lines, '')

            if container.ports and #container.ports > 0 then
              table.insert(lines, '## Forwarded Ports')
              for _, port in ipairs(container.ports) do
                table.insert(lines, '- ' .. port)
              end
            end
          else
            local project = entry.value
            table.insert(lines, '# Project Information')
            table.insert(lines, '')
            table.insert(lines, 'Name: ' .. project.name)
            table.insert(lines, 'Path: ' .. project.path)
            table.insert(lines, '')
            table.insert(lines, '## devcontainer.json')
            table.insert(lines, '```json')
            local json_lines = vim.split(vim.json.encode(project.config), '\n')
            vim.list_extend(lines, json_lines)
            table.insert(lines, '```')
          end

          vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
          vim.bo[self.state.bufnr].filetype = 'markdown'
        end,
      }),
      attach_mappings = function(prompt_bufnr, map)
        actions.select_default:replace(function()
          local selection = action_state.get_selected_entry()
          if not selection then
            return
          end

          actions.close(prompt_bufnr)

          if selection.type == 'container' then
            local container = selection.value
            if container.running then
              -- Attach to running container
              require('container').attach(container.name)
            else
              -- Start stopped container
              require('container').start_container(container.name)
            end
          else
            -- Open project
            local project = selection.value
            require('container').open(project.path)
          end
        end)

        -- Additional mappings
        map('i', '<C-s>', function()
          local selection = action_state.get_selected_entry()
          if not selection then
            return
          end
          actions.close(prompt_bufnr)
          if selection.type == 'container' and selection.value.running then
            require('container').stop_container(selection.value.name)
          end
        end)

        map('i', '<C-r>', function()
          local selection = action_state.get_selected_entry()
          if not selection then
            return
          end
          actions.close(prompt_bufnr)
          if selection.type == 'container' then
            require('container').restart_container(selection.value.name)
          elseif selection.type == 'project' then
            require('container').rebuild(selection.value.path)
          end
        end)

        return true
      end,
    })
    :find()
end

-- Terminal session picker
function M.sessions(opts)
  opts = opts or {}
  local terminal = require('container.terminal')
  local sessions = terminal.list_sessions()

  -- If no sessions, show empty message
  if not sessions or #sessions == 0 then
    require('container.utils.notify').ui('No terminal sessions found')
    return
  end

  pickers
    .new(opts, {
      prompt_title = 'Terminal Sessions',
      finder = finders.new_table({
        results = sessions,
        entry_maker = function(session)
          local status_icon = session.active and '✅' or '⏸️'
          return {
            value = session,
            display = string.format(
              '%-20s %s %-15s %-10s %s',
              session.name,
              status_icon,
              session.container_name or 'local',
              session.active and 'active' or 'inactive',
              session.created_at or ''
            ),
            ordinal = session.name .. ' ' .. (session.container_name or ''),
          }
        end,
      }),
      sorter = conf.generic_sorter(opts),
      selection_strategy = 'reset',
      initial_mode = 'insert',
      previewer = previewers.new_buffer_previewer({
        title = 'Session Info',
        define_preview = function(self, entry)
          local session = entry.value
          local lines = {
            '# Terminal Session',
            '',
            'Name: ' .. session.name,
            'Container: ' .. (session.container_name or 'local'),
            'Status: ' .. (session.active and 'Active' or 'Inactive'),
            'Created: ' .. session.created_at,
            '',
            '## Configuration',
            'Shell: ' .. (session.shell or 'default'),
            'Position: ' .. (session.position or 'default'),
          }

          if session.buffer_id and vim.api.nvim_buf_is_valid(session.buffer_id) then
            table.insert(lines, '')
            table.insert(lines, '## Recent Output')
            local buf_lines = vim.api.nvim_buf_get_lines(session.buffer_id, -20, -1, false)
            vim.list_extend(lines, buf_lines)
          end

          vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
          vim.bo[self.state.bufnr].filetype = 'markdown'
        end,
      }),
      attach_mappings = function(prompt_bufnr, map)
        actions.select_default:replace(function()
          local selection = action_state.get_selected_entry()
          if not selection then
            return
          end
          actions.close(prompt_bufnr)
          terminal.switch_to_session(selection.value.name)
        end)

        -- Close session
        map('i', '<C-x>', function()
          local selection = action_state.get_selected_entry()
          if not selection then
            return
          end
          actions.close(prompt_bufnr)
          terminal.close_session(selection.value.name)
        end)

        -- Rename session
        map('i', '<C-r>', function()
          local selection = action_state.get_selected_entry()
          if not selection then
            return
          end
          vim.ui.input({ prompt = 'New name: ', default = selection.value.name }, function(new_name)
            if new_name and new_name ~= '' then
              terminal.rename_session(selection.value.name, new_name)
              actions.close(prompt_bufnr)
            end
          end)
        end)

        return true
      end,
    })
    :find()
end

-- Port management picker
function M.ports(opts)
  -- Completely ignore any incoming opts to prevent contamination
  local fresh_opts = {
    prompt_title = 'Forwarded Ports [' .. os.time() .. ']',
    cache_picker = false,
    layout_strategy = 'horizontal',
    selection_strategy = 'reset',
    initial_mode = 'insert',
  }

  local docker = require('container.docker')
  local all_ports = docker.get_forwarded_ports()

  -- Debug: Log the function being called
  local log = require('container.utils.log')
  log.debug('PortPicker M.ports() called with fresh state')
  log.debug('PortPicker: opts parameter was: %s', vim.inspect(opts))
  log.debug('PortPicker: all_ports from docker.get_forwarded_ports(): %s', vim.inspect(all_ports))

  -- Filter out invalid ports and ensure clean port objects
  local ports = {}
  if all_ports then
    for i, port in ipairs(all_ports) do
      log.debug('PortPicker: examining port %d: %s', i, vim.inspect(port))

      if port.local_port and port.local_port > 0 and port.container_port and port.container_port > 0 then
        -- Create completely new port object to prevent contamination
        local clean_port = {
          type = 'port',
          local_port = port.local_port,
          container_port = port.container_port,
          container_name = port.container_name or 'unknown',
          container_id = port.container_id,
          protocol = port.protocol or 'tcp',
          bind_address = port.bind_address,
          label = port.label,
          url = port.url,
        }
        table.insert(ports, clean_port)
        log.debug('PortPicker: added clean port: %s', vim.inspect(clean_port))
      else
        log.debug(
          'PortPicker: skipped invalid port: local_port=%s, container_port=%s',
          tostring(port.local_port),
          tostring(port.container_port)
        )
      end
    end
  end

  log.debug('PortPicker: final filtered clean ports: %s', vim.inspect(ports))

  -- If no valid ports, show empty message
  if #ports == 0 then
    require('container.utils.notify').ui('No valid forwarded ports found')
    return
  end

  pickers
    .new(fresh_opts, {
      prompt_title = 'Forwarded Ports',
      finder = finders.new_table({
        results = ports,
        entry_maker = function(port)
          -- Debug: Log the port object
          local log = require('container.utils.log')
          log.debug('PortPicker entry_maker: processing port: %s', vim.inspect(port))

          -- Absolutely ensure this is a port object
          if port.type ~= 'port' then
            log.error('PortPicker entry_maker: CRITICAL ERROR - Received non-port object: %s', vim.inspect(port))
            return nil
          end

          local local_port = port.local_port
          local container_port = port.container_port
          local container_name = port.container_name or 'unknown'

          -- Validate port data
          if not local_port or not container_port then
            log.warn(
              'PortPicker: Invalid port data - local_port: %s, container_port: %s',
              tostring(local_port),
              tostring(container_port)
            )
            return nil
          end

          return {
            value = port, -- Use the already clean port object directly
            display = string.format(
              '%-15s -> %-15s %-20s %-15s %s',
              tostring(local_port),
              tostring(container_port),
              container_name,
              port.protocol or 'tcp',
              port.label or ''
            ),
            ordinal = string.format('%s:%d->%d', container_name, local_port, container_port),
          }
        end,
      }),
      sorter = conf.generic_sorter(fresh_opts),
      selection_strategy = 'reset',
      initial_mode = 'insert',
      previewer = previewers.new_buffer_previewer({
        title = 'Port Details',
        define_preview = function(self, entry)
          local port = entry.value
          local lines = {
            '# Port Forwarding Details',
            '',
            'Container: ' .. port.container_name,
            'Local Port: ' .. port.local_port,
            'Container Port: ' .. port.container_port,
            'Protocol: ' .. (port.protocol or 'tcp'),
            '',
          }

          if port.label then
            table.insert(lines, 'Label: ' .. port.label)
          end

          if port.url then
            table.insert(lines, 'URL: ' .. port.url)
          end

          table.insert(lines, '')
          table.insert(lines, '## Actions')
          table.insert(lines, '- <CR>: Open in browser')
          table.insert(lines, '- <C-y>: Copy URL to clipboard')
          table.insert(lines, '- <C-x>: Stop port forwarding')

          vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
          vim.bo[self.state.bufnr].filetype = 'markdown'
        end,
      }),
      attach_mappings = function(prompt_bufnr, map)
        actions.select_default:replace(function()
          local selection = action_state.get_selected_entry()
          local log = require('container.utils.log')

          -- Debug: Log everything about the selection
          log.debug('PortPicker action: raw selection = %s', vim.inspect(selection))
          log.debug('PortPicker action: selection type = %s', type(selection))

          if not selection then
            log.error('PortPicker action: No selection received')
            return
          end

          log.debug('PortPicker action: selection.value = %s', vim.inspect(selection.value))
          log.debug('PortPicker action: selection.value type = %s', type(selection.value))

          actions.close(prompt_bufnr)
          local port = selection.value

          -- Validate that this is actually a port object
          if not port or port.type ~= 'port' then
            log.error('PortPicker action: CRITICAL - Invalid selection - not a port object')
            log.error('PortPicker action: port = %s', vim.inspect(port))
            log.error('PortPicker action: port.type = %s', tostring(port.type))
            require('container.utils.notify').critical('Invalid selection: not a port object')
            return
          end

          local local_port = port.local_port

          -- Check if port is valid
          if not local_port or local_port <= 0 then
            log.error(
              'PortPicker action: Invalid port number: %s (full port object: %s)',
              tostring(local_port),
              vim.inspect(port)
            )
            require('container.utils.notify').critical('Invalid port number: ' .. tostring(local_port))
            return
          end

          local url = port.url or string.format('http://localhost:%d', local_port)

          -- Open in browser
          vim.fn.jobstart({ 'open', url }, { detach = true })
          require('container.utils.notify').status('Opening ' .. url)
        end)

        -- Copy URL
        map('i', '<C-y>', function()
          local selection = action_state.get_selected_entry()
          if not selection then
            return
          end
          local port = selection.value

          -- Debug: Log the selection
          local log = require('container.utils.log')
          log.debug('PortPicker copy action: selection.value = %s', vim.inspect(port))

          -- Validate that this is actually a port object
          if not port or port.type ~= 'port' then
            log.error('PortPicker copy action: Invalid selection - not a port object: %s', vim.inspect(port))
            require('container.utils.notify').critical('Invalid selection: not a port object')
            return
          end

          local local_port = port.local_port

          -- Check if port is valid
          if not local_port or local_port <= 0 then
            log.error(
              'PortPicker copy action: Invalid port number: %s (full port object: %s)',
              tostring(local_port),
              vim.inspect(port)
            )
            require('container.utils.notify').critical('Invalid port number: ' .. tostring(local_port))
            return
          end

          local url = port.url or string.format('http://localhost:%d', local_port)
          vim.fn.setreg('+', url)
          require('container.utils.notify').status('Copied: ' .. url)
        end)

        -- Stop forwarding
        map('i', '<C-x>', function()
          local selection = action_state.get_selected_entry()
          if not selection then
            return
          end

          local port = selection.value

          -- Validate that this is actually a port object
          if not port or port.type ~= 'port' then
            require('container.utils.notify').critical('Invalid selection: not a port object')
            return
          end

          actions.close(prompt_bufnr)
          docker.stop_port_forward(port)
          require('container.utils.notify').status('Stopped port forwarding')
        end)

        return true
      end,
    })
    :find()
end

-- Command history picker
function M.history(opts)
  opts = opts or {}
  local history = require('container.history').get_exec_history()

  -- If no history, show empty message
  if not history or #history == 0 then
    require('container.utils.notify').ui('No command history found')
    return
  end

  pickers
    .new(opts, {
      prompt_title = 'Command History',
      finder = finders.new_table({
        results = history,
        entry_maker = function(entry)
          local status_icon = entry.exit_code == 0 and '✅' or '❌'
          return {
            value = entry,
            display = string.format(
              '%-20s %s %-50s %-10s %s',
              entry.timestamp or '',
              status_icon,
              entry.command or '',
              tostring(entry.exit_code or 'N/A'),
              entry.container_name or 'unknown'
            ),
            ordinal = entry.command .. ' ' .. entry.timestamp,
          }
        end,
      }),
      sorter = conf.generic_sorter(opts),
      selection_strategy = 'reset',
      initial_mode = 'insert',
      previewer = previewers.new_buffer_previewer({
        title = 'Command Output',
        define_preview = function(self, entry)
          local cmd = entry.value
          local lines = {
            '# Command Execution',
            '',
            '## Command',
            '```bash',
            cmd.command,
            '```',
            '',
            '## Details',
            'Container: ' .. (cmd.container_name or 'unknown'),
            'Timestamp: ' .. cmd.timestamp,
            'Exit Code: ' .. tostring(cmd.exit_code or 'N/A'),
            'Duration: ' .. (cmd.duration and string.format('%.2fs', cmd.duration) or 'N/A'),
            '',
          }

          if cmd.output then
            table.insert(lines, '## Output')
            table.insert(lines, '```')
            local output_lines = vim.split(cmd.output, '\n')
            vim.list_extend(lines, output_lines)
            table.insert(lines, '```')
          end

          vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
          vim.bo[self.state.bufnr].filetype = 'markdown'
        end,
      }),
      attach_mappings = function(prompt_bufnr, map)
        actions.select_default:replace(function()
          local selection = action_state.get_selected_entry()
          if not selection then
            return
          end
          actions.close(prompt_bufnr)

          -- Re-execute command
          vim.ui.input({
            prompt = 'Execute command: ',
            default = selection.value.command,
          }, function(command)
            if command and command ~= '' then
              require('container').exec(command)
            end
          end)
        end)

        -- Copy command
        map('i', '<C-y>', function()
          local selection = action_state.get_selected_entry()
          if not selection then
            return
          end
          vim.fn.setreg('+', selection.value.command)
          require('container.utils.notify').status('Copied command to clipboard')
        end)

        -- Edit and execute
        map('i', '<C-e>', function()
          local selection = action_state.get_selected_entry()
          if not selection then
            return
          end
          actions.close(prompt_bufnr)
          vim.ui.input({
            prompt = 'Edit command: ',
            default = selection.value.command,
          }, function(command)
            if command and command ~= '' then
              require('container').exec(command)
            end
          end)
        end)

        return true
      end,
    })
    :find()
end

-- Non-telescope port picker to completely avoid telescope state issues
function M.ports_simple()
  local log = require('container.utils.log')
  log.debug('Using simple non-telescope port picker')

  local docker = require('container.docker')
  local all_ports = docker.get_forwarded_ports()

  log.debug('Simple PortPicker: all_ports = %s', vim.inspect(all_ports))

  if not all_ports or #all_ports == 0 then
    require('container.utils.notify').ui('No forwarded ports found')
    return
  end

  -- Create choices for vim.ui.select
  local choices = {}
  local port_map = {}

  for i, port in ipairs(all_ports) do
    if port.local_port and port.local_port > 0 and port.container_port and port.container_port > 0 then
      local display =
        string.format('%d -> %d (%s)', port.local_port, port.container_port, port.container_name or 'unknown')
      table.insert(choices, display)
      port_map[display] = port
      log.debug('Simple PortPicker: added choice %d: %s -> %s', i, display, vim.inspect(port))
    end
  end

  if #choices == 0 then
    require('container.utils.notify').ui('No valid forwarded ports found')
    return
  end

  -- Use vim.ui.select instead of telescope
  vim.ui.select(choices, {
    prompt = 'Select port to open:',
    format_item = function(item)
      return item
    end,
  }, function(choice)
    if not choice then
      log.debug('Simple PortPicker: No choice selected')
      return
    end

    local port = port_map[choice]
    log.debug('Simple PortPicker: Selected port = %s', vim.inspect(port))

    if not port or not port.local_port then
      require('container.utils.notify').critical('Invalid port selection')
      return
    end

    local url = string.format('http://localhost:%d', port.local_port)
    vim.fn.jobstart({ 'open', url }, { detach = true })
    require('container.utils.notify').status('Opening ' .. url)
  end)
end

return M
