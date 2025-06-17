-- lua/devcontainer/config.lua
-- Configuration management

local M = {}
local log = require('devcontainer.utils.log')

-- Default configuration
M.defaults = {
  -- Basic settings
  auto_start = false,
  auto_start_mode = 'notify', -- 'notify', 'prompt', 'immediate', 'off'
  auto_start_delay = 2000, -- milliseconds to wait before auto-start
  log_level = 'info',
  container_runtime = 'docker', -- 'docker' or 'podman'

  -- devcontainer settings
  devcontainer_path = '.devcontainer',
  dockerfile_path = '.devcontainer/Dockerfile',
  compose_file = '.devcontainer/docker-compose.yml',

  -- Workspace settings
  workspace = {
    auto_mount = true,
    mount_point = '/workspace',
    exclude_patterns = { '.git', 'node_modules', '.next', '__pycache__' },
  },

  -- LSP settings
  lsp = {
    auto_setup = true,
    timeout = 5000,
    port_range = { 8000, 9000 },
    servers = {}, -- Server-specific configurations
    on_attach = nil, -- Custom on_attach function
  },

  -- Terminal settings
  terminal = {
    -- Default shell and behavior
    default_shell = '/bin/bash',
    auto_insert = true, -- Automatically enter insert mode
    close_on_exit = false, -- Keep buffer open when process exits

    -- Session management
    persistent_history = true, -- Save terminal history across sessions
    max_history_lines = 10000, -- Maximum lines to keep in history
    history_dir = (vim.fn and vim.fn.stdpath('data') or '/tmp') .. '/devcontainer/terminal_history',

    -- Default positioning
    default_position = 'split', -- 'split', 'vsplit', 'tab', 'float'

    -- Size configuration
    split_size = 0.3, -- Size ratio for splits (0.1 to 0.9)

    -- Split configuration
    split = {
      height = 15, -- Lines for horizontal split
      width = 80, -- Columns for vertical split
    },

    -- Float configuration
    float = {
      width = 0.8, -- Ratio of editor width
      height = 0.6, -- Ratio of editor height
      border = 'rounded', -- 'single', 'double', 'rounded', 'solid', 'shadow'
      title = 'DevContainer Terminal',
      title_pos = 'center', -- 'left', 'center', 'right'
    },

    -- Environment configuration
    environment = {
      'TERM=xterm-256color',
      'COLORTERM=truecolor',
    },

    -- Keymaps for terminal mode
    keymaps = {
      -- Terminal mode keymaps
      close = '<C-q>', -- Close terminal
      escape = '<C-\\><C-n>', -- Exit terminal mode

      -- Normal mode keymaps
      new_session = '<leader>tn', -- Create new terminal session
      list_sessions = '<leader>tl', -- List terminal sessions
      next_session = '<leader>t]', -- Next terminal session
      prev_session = '<leader>t[', -- Previous terminal session
    },
  },

  -- UI settings
  ui = {
    picker = 'telescope', -- 'telescope', 'fzf-lua', 'vim.ui.select'
    show_notifications = true,
    notification_level = 'normal', -- 'verbose', 'normal', 'minimal', 'silent'
    status_line = true,
    icons = {
      container = '🐳',
      running = '✅',
      stopped = '⏹️',
      building = '🔨',
      error = '❌',
    },
    statusline = {
      -- Display format for statusline
      -- Available variables: {icon}, {name}, {status}
      format = {
        running = '{icon} {name}',
        stopped = '{icon} {name}',
        available = '{icon} {name} (available)',
        building = '{icon} {name}',
        error = '{icon} {name}',
      },
      -- Text labels (can be customized or set to empty string)
      labels = {
        container_name = 'DevContainer', -- Default name when container name is not available
        available_suffix = 'available', -- Text shown for available containers
      },
      -- Whether to show container name or use generic label
      show_container_name = true,
      -- Fallback when no specific format is defined
      default_format = '{icon} {name}',
    },
  },

  -- Port forwarding
  port_forwarding = {
    auto_forward = true,
    notification = true,
    bind_address = '127.0.0.1',
    common_ports = { 3000, 8080, 5000, 3001 },
    -- Dynamic port allocation settings
    enable_dynamic_ports = true,
    port_range_start = 10000,
    port_range_end = 20000,
    conflict_resolution = 'auto', -- 'auto', 'prompt', 'error'
  },

  -- Docker settings
  docker = {
    build_args = {},
    network_mode = 'bridge',
    privileged = false,
    init = true,
    remove_orphans = true,
  },

  -- Test integration settings
  test_integration = {
    enabled = true, -- Enable automatic test plugin integration
    auto_setup = true, -- Automatically setup when container starts
    output_mode = 'buffer', -- 'buffer' (default), 'terminal', 'quickfix'
  },

  -- Development settings
  dev = {
    reload_on_change = true,
    debug_mode = false,
  },
}

-- Current configuration
local current_config = {}

-- Deep copy of configuration
local function deep_copy(t)
  if type(t) ~= 'table' then
    return t
  end

  local copy = {}
  for k, v in pairs(t) do
    copy[k] = deep_copy(v)
  end
  return copy
end

-- Merge configurations
local function merge_config(target, source)
  for key, value in pairs(source) do
    if type(value) == 'table' and type(target[key]) == 'table' then
      merge_config(target[key], value)
    else
      target[key] = value
    end
  end
end

-- Validate configuration
local function validate_config(config)
  local errors = {}

  -- Validate log level
  local valid_log_levels = { 'debug', 'info', 'warn', 'error' }
  if not vim.tbl_contains(valid_log_levels, config.log_level:lower()) then
    table.insert(errors, 'Invalid log_level: ' .. config.log_level)
  end

  -- Validate container runtime
  local valid_runtimes = { 'docker', 'podman' }
  if not vim.tbl_contains(valid_runtimes, config.container_runtime) then
    table.insert(errors, 'Invalid container_runtime: ' .. config.container_runtime)
  end

  -- Validate auto_start_mode
  local valid_auto_start_modes = { 'notify', 'prompt', 'immediate', 'off' }
  if not vim.tbl_contains(valid_auto_start_modes, config.auto_start_mode) then
    table.insert(errors, 'Invalid auto_start_mode: ' .. config.auto_start_mode)
  end

  -- Validate auto_start_delay
  if type(config.auto_start_delay) ~= 'number' or config.auto_start_delay < 0 then
    table.insert(errors, 'auto_start_delay must be a non-negative number')
  end

  -- Validate terminal default_position
  local valid_positions = { 'split', 'vsplit', 'tab', 'float' }
  if not vim.tbl_contains(valid_positions, config.terminal.default_position) then
    table.insert(errors, 'Invalid terminal default_position: ' .. config.terminal.default_position)
  end

  -- Validate terminal float border
  local valid_borders = { 'single', 'double', 'rounded', 'solid', 'shadow' }
  if config.terminal.float.border and not vim.tbl_contains(valid_borders, config.terminal.float.border) then
    table.insert(errors, 'Invalid terminal float border: ' .. config.terminal.float.border)
  end

  -- Validate port range
  if config.lsp.port_range[1] >= config.lsp.port_range[2] then
    table.insert(errors, 'Invalid LSP port_range: start port must be less than end port')
  end

  -- Validate picker
  local valid_pickers = { 'telescope', 'fzf-lua', 'vim.ui.select' }
  if not vim.tbl_contains(valid_pickers, config.ui.picker) then
    table.insert(errors, 'Invalid ui.picker: ' .. config.ui.picker)
  end

  -- Validate paths
  if config.workspace.mount_point == '' then
    table.insert(errors, 'workspace.mount_point cannot be empty')
  end

  return errors
end

-- Configuration setup
function M.setup(user_config)
  user_config = user_config or {}

  -- Copy default configuration
  current_config = deep_copy(M.defaults)

  -- Merge user configuration
  merge_config(current_config, user_config)

  -- Validate configuration
  local errors = validate_config(current_config)
  if #errors > 0 then
    for _, error in ipairs(errors) do
      log.error('Configuration error: %s', error)
    end
    return false, errors
  end

  -- Set log level
  log.set_level(current_config.log_level)

  log.debug('Configuration loaded successfully')
  return true, current_config
end

-- Get current configuration
function M.get()
  return current_config
end

-- Get specific configuration item
function M.get_value(path)
  local keys = vim.split(path, '.', { plain = true })
  local value = current_config

  for _, key in ipairs(keys) do
    if type(value) == 'table' and value[key] ~= nil then
      value = value[key]
    else
      return nil
    end
  end

  return value
end

-- Update configuration item
function M.set_value(path, new_value)
  local keys = vim.split(path, '.', { plain = true })
  local target = current_config

  -- Navigate to all keys except the last one
  for i = 1, #keys - 1 do
    local key = keys[i]
    if type(target[key]) ~= 'table' then
      target[key] = {}
    end
    target = target[key]
  end

  -- Set value with the last key
  target[keys[#keys]] = new_value

  log.debug('Configuration updated: %s = %s', path, vim.inspect(new_value))
end

-- Save configuration to file
function M.save_to_file(filepath)
  local fs = require('devcontainer.utils.fs')

  local content = '-- devcontainer.nvim configuration\n'
  content = content .. 'return ' .. vim.inspect(current_config, {
    indent = '  ',
    depth = 10,
  })

  local success, err = fs.write_file(filepath, content)
  if not success then
    log.error('Failed to save configuration: %s', err)
    return false, err
  end

  log.info('Configuration saved to %s', filepath)
  return true
end

-- Load configuration from file
function M.load_from_file(filepath)
  local fs = require('devcontainer.utils.fs')

  if not fs.is_file(filepath) then
    log.warn('Configuration file not found: %s', filepath)
    return false, 'File not found'
  end

  local content, err = fs.read_file(filepath)
  if not content then
    log.error('Failed to read configuration file: %s', err)
    return false, err
  end

  local chunk, load_err = loadstring(content)
  if not chunk then
    log.error('Failed to parse configuration file: %s', load_err)
    return false, load_err
  end

  local success, config = pcall(chunk)
  if not success then
    log.error('Failed to execute configuration file: %s', config)
    return false, config
  end

  return M.setup(config)
end

-- Reset to default configuration
function M.reset()
  current_config = deep_copy(M.defaults)
  log.info('Configuration reset to defaults')
  return current_config
end

-- Display configuration differences
function M.diff_from_defaults()
  local function table_diff(default, current, prefix)
    local diffs = {}
    prefix = prefix or ''

    for key, value in pairs(current) do
      local path = prefix == '' and key or prefix .. '.' .. key

      if default[key] == nil then
        table.insert(diffs, {
          path = path,
          action = 'added',
          value = value,
        })
      elseif type(value) == 'table' and type(default[key]) == 'table' then
        local sub_diffs = table_diff(default[key], value, path)
        for _, diff in ipairs(sub_diffs) do
          table.insert(diffs, diff)
        end
      elseif value ~= default[key] then
        table.insert(diffs, {
          path = path,
          action = 'changed',
          old_value = default[key],
          new_value = value,
        })
      end
    end

    for key, value in pairs(default) do
      local path = prefix == '' and key or prefix .. '.' .. key
      if current[key] == nil then
        table.insert(diffs, {
          path = path,
          action = 'removed',
          value = value,
        })
      end
    end

    return diffs
  end

  return table_diff(M.defaults, current_config)
end

-- Display configuration details
function M.show_config()
  local diffs = M.diff_from_defaults()

  print('=== devcontainer.nvim Configuration ===')
  print()

  if #diffs == 0 then
    print('Using default configuration')
  else
    print('Differences from defaults:')
    for _, diff in ipairs(diffs) do
      if diff.action == 'changed' then
        print(string.format('  %s: %s -> %s', diff.path, vim.inspect(diff.old_value), vim.inspect(diff.new_value)))
      elseif diff.action == 'added' then
        print(string.format('  +%s: %s', diff.path, vim.inspect(diff.value)))
      elseif diff.action == 'removed' then
        print(string.format('  -%s: %s', diff.path, vim.inspect(diff.value)))
      end
    end
  end

  print()
  print('Current log level: ' .. current_config.log_level)
  print('Container runtime: ' .. current_config.container_runtime)
  print()
end

-- Get configuration schema (for completion)
function M.get_schema()
  local function extract_schema(config, prefix)
    local schema = {}
    prefix = prefix or ''

    for key, value in pairs(config) do
      local path = prefix == '' and key or prefix .. '.' .. key

      if type(value) == 'table' then
        schema[path] = {
          type = 'table',
          children = extract_schema(value, path),
        }
      else
        schema[path] = {
          type = type(value),
          default = value,
        }
      end
    end

    return schema
  end

  return extract_schema(M.defaults)
end

return M
