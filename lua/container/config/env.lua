-- lua/devcontainer/config/env.lua
-- Environment variable configuration override module

local M = {}

-- Environment variable prefix
local ENV_PREFIX = 'DEVCONTAINER_'

-- Type conversion functions
local converters = {
  boolean = function(value)
    local lower = value:lower()
    return lower == 'true' or lower == '1' or lower == 'yes' or lower == 'on'
  end,
  number = function(value)
    return tonumber(value)
  end,
  string = function(value)
    return value
  end,
  array = function(value)
    -- Support comma-separated values
    -- Safe alternative to vim.split for test environments
    if vim.split then
      return vim.split(value, ',', { trimempty = true })
    else
      local result = {}
      for part in value:gmatch('[^,]+') do
        local trimmed = part:match('^%s*(.-)%s*$')
        if trimmed and trimmed ~= '' then
          table.insert(result, trimmed)
        end
      end
      return result
    end
  end,
}

-- Mapping of environment variables to config paths
local env_mappings = {
  -- Basic settings
  AUTO_START = { path = 'auto_start', type = 'boolean' },
  AUTO_START_MODE = { path = 'auto_start_mode', type = 'string' },
  AUTO_START_DELAY = { path = 'auto_start_delay', type = 'number' },
  LOG_LEVEL = { path = 'log_level', type = 'string' },
  CONTAINER_RUNTIME = { path = 'container_runtime', type = 'string' },

  -- Paths
  PATH = { path = 'devcontainer_path', type = 'string' },
  DOCKERFILE_PATH = { path = 'dockerfile_path', type = 'string' },
  COMPOSE_FILE = { path = 'compose_file', type = 'string' },

  -- Workspace
  WORKSPACE_AUTO_MOUNT = { path = 'workspace.auto_mount', type = 'boolean' },
  WORKSPACE_MOUNT_POINT = { path = 'workspace.mount_point', type = 'string' },
  WORKSPACE_EXCLUDE = { path = 'workspace.exclude_patterns', type = 'array' },

  -- LSP
  LSP_AUTO_SETUP = { path = 'lsp.auto_setup', type = 'boolean' },
  LSP_TIMEOUT = { path = 'lsp.timeout', type = 'number' },
  LSP_PORT_START = { path = 'lsp.port_range[1]', type = 'number' },
  LSP_PORT_END = { path = 'lsp.port_range[2]', type = 'number' },

  -- Terminal
  TERMINAL_SHELL = { path = 'terminal.default_shell', type = 'string' },
  TERMINAL_AUTO_INSERT = { path = 'terminal.auto_insert', type = 'boolean' },
  TERMINAL_CLOSE_ON_EXIT = { path = 'terminal.close_on_exit', type = 'boolean' },
  TERMINAL_POSITION = { path = 'terminal.default_position', type = 'string' },
  TERMINAL_HISTORY = { path = 'terminal.persistent_history', type = 'boolean' },
  TERMINAL_HISTORY_MAX = { path = 'terminal.max_history_lines', type = 'number' },

  -- UI
  UI_PICKER = { path = 'ui.picker', type = 'string' },
  UI_NOTIFICATIONS = { path = 'ui.show_notifications', type = 'boolean' },
  UI_NOTIFICATION_LEVEL = { path = 'ui.notification_level', type = 'string' },
  UI_STATUSLINE = { path = 'ui.status_line', type = 'boolean' },

  -- Port forwarding
  PORT_AUTO_FORWARD = { path = 'port_forwarding.auto_forward', type = 'boolean' },
  PORT_BIND_ADDRESS = { path = 'port_forwarding.bind_address', type = 'string' },
  PORT_COMMON = { path = 'port_forwarding.common_ports', type = 'array' },
  PORT_DYNAMIC = { path = 'port_forwarding.enable_dynamic_ports', type = 'boolean' },
  PORT_RANGE_START = { path = 'port_forwarding.port_range_start', type = 'number' },
  PORT_RANGE_END = { path = 'port_forwarding.port_range_end', type = 'number' },

  -- Docker
  DOCKER_NETWORK = { path = 'docker.network_mode', type = 'string' },
  DOCKER_PRIVILEGED = { path = 'docker.privileged', type = 'boolean' },
  DOCKER_INIT = { path = 'docker.init', type = 'boolean' },

  -- Test integration
  TEST_ENABLED = { path = 'test_integration.enabled', type = 'boolean' },
  TEST_OUTPUT = { path = 'test_integration.output_mode', type = 'string' },

  -- Development
  DEV_RELOAD = { path = 'dev.reload_on_change', type = 'boolean' },
  DEV_DEBUG = { path = 'dev.debug_mode', type = 'boolean' },
}

-- Parse value based on type
local function parse_value(value, value_type)
  local converter = converters[value_type]
  if converter then
    return converter(value)
  end
  return value
end

-- Set nested value in table
local function set_nested_value(tbl, path, value)
  local keys = {}
  local array_index

  -- Parse path with array notation
  for part in path:gmatch('[^.]+') do
    local key, index = part:match('([^%[]+)%[(%d+)%]')
    if key then
      table.insert(keys, key)
      array_index = tonumber(index)
      break
    else
      table.insert(keys, part)
    end
  end

  -- Navigate to the parent
  local current = tbl
  for i = 1, #keys - 1 do
    local key = keys[i]
    if not current[key] then
      current[key] = {}
    end
    current = current[key]
  end

  -- Set the value
  local last_key = keys[#keys]
  if array_index then
    if not current[last_key] then
      current[last_key] = {}
    end
    current[last_key][array_index] = value
  else
    current[last_key] = value
  end
end

-- Get environment variable overrides
function M.get_overrides()
  local overrides = {}

  -- Use vim.env if available, otherwise fallback to os.getenv
  local get_env = function(name)
    if vim.env then
      return vim.env[name]
    else
      return os.getenv(name)
    end
  end

  for env_suffix, mapping in pairs(env_mappings) do
    local env_name = ENV_PREFIX .. env_suffix
    local env_value = get_env(env_name)

    if env_value then
      local parsed_value = parse_value(env_value, mapping.type)
      if parsed_value ~= nil then
        set_nested_value(overrides, mapping.path, parsed_value)
      end
    end
  end

  -- Special handling for array in port_range
  if overrides.lsp and overrides.lsp.port_range then
    local range = overrides.lsp.port_range
    if range[1] and range[2] then
      overrides.lsp.port_range = { range[1], range[2] }
    else
      overrides.lsp.port_range = nil
    end
  end

  return overrides
end

-- Apply environment overrides to configuration
function M.apply_overrides(config)
  local overrides = M.get_overrides()

  -- Deep merge overrides into config
  local function merge(target, source)
    for key, value in pairs(source) do
      if type(value) == 'table' and type(target[key]) == 'table' then
        merge(target[key], value)
      else
        target[key] = value
      end
    end
  end

  merge(config, overrides)
  return config
end

-- Get list of supported environment variables
function M.get_supported_vars()
  local vars = {}
  for suffix, mapping in pairs(env_mappings) do
    table.insert(vars, {
      name = ENV_PREFIX .. suffix,
      path = mapping.path,
      type = mapping.type,
    })
  end
  table.sort(vars, function(a, b)
    return a.name < b.name
  end)
  return vars
end

-- Generate environment variable documentation
function M.generate_docs()
  local lines = {
    '# Environment Variable Configuration',
    '',
    'You can override container.nvim settings using environment variables.',
    'All environment variables use the prefix `DEVCONTAINER_`.',
    '',
    '## Supported Variables',
    '',
  }

  local vars = M.get_supported_vars()
  for _, var in ipairs(vars) do
    table.insert(lines, string.format('- `%s` (%s): %s', var.name, var.type, var.path))
  end

  table.insert(lines, '')
  table.insert(lines, '## Examples')
  table.insert(lines, '')
  table.insert(lines, '```bash')
  table.insert(lines, '# Enable auto-start')
  table.insert(lines, 'export DEVCONTAINER_AUTO_START=true')
  table.insert(lines, '')
  table.insert(lines, '# Set log level to debug')
  table.insert(lines, 'export DEVCONTAINER_LOG_LEVEL=debug')
  table.insert(lines, '')
  table.insert(lines, '# Configure common ports')
  table.insert(lines, 'export DEVCONTAINER_PORT_COMMON=3000,8080,5000')
  table.insert(lines, '')
  table.insert(lines, '# Use podman instead of docker')
  table.insert(lines, 'export DEVCONTAINER_CONTAINER_RUNTIME=podman')
  table.insert(lines, '```')

  return table.concat(lines, '\n')
end

return M
