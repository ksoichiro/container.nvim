-- lua/devcontainer/config/validator.lua
-- Configuration validation module

local M = {}

-- Type validation functions
local validators = {}

-- Check if value is of specific type
function validators.type(expected_type)
  return function(value)
    if type(value) ~= expected_type then
      return false, string.format('Expected %s, got %s', expected_type, type(value))
    end
    return true
  end
end

-- Check if value is in a list of valid options
function validators.enum(valid_options)
  return function(value)
    -- Safe alternative to vim.tbl_contains for test environments
    local contains = vim.tbl_contains
      or function(tbl, val)
        for _, v in ipairs(tbl) do
          if v == val then
            return true
          end
        end
        return false
      end

    if not contains(valid_options, value) then
      return false, string.format('Must be one of: %s', table.concat(valid_options, ', '))
    end
    return true
  end
end

-- Check if number is within range
function validators.range(min, max)
  return function(value)
    if type(value) ~= 'number' then
      return false, 'Expected number'
    end
    if min and value < min then
      return false, string.format('Must be >= %d', min)
    end
    if max and value > max then
      return false, string.format('Must be <= %d', max)
    end
    return true
  end
end

-- Check if string matches pattern
function validators.pattern(pattern, description)
  return function(value)
    if type(value) ~= 'string' then
      return false, 'Expected string'
    end
    if not value:match(pattern) then
      return false, description or string.format('Must match pattern: %s', pattern)
    end
    return true
  end
end

-- Check if path exists
function validators.path_exists()
  return function(value)
    if type(value) ~= 'string' then
      return false, 'Expected string path'
    end
    if vim.fn.isdirectory(value) == 0 and vim.fn.filereadable(value) == 0 then
      return false, string.format('Path does not exist: %s', value)
    end
    return true
  end
end

-- Check if directory exists
function validators.directory_exists()
  return function(value)
    if type(value) ~= 'string' then
      return false, 'Expected string path'
    end
    if vim.fn.isdirectory(value) == 0 then
      return false, string.format('Directory does not exist: %s', value)
    end
    return true
  end
end

-- Check array of specific type
function validators.array_of(item_validator)
  return function(value)
    if type(value) ~= 'table' then
      return false, 'Expected array'
    end
    for i, item in ipairs(value) do
      local valid, err = item_validator(item)
      if not valid then
        return false, string.format('Item %d: %s', i, err)
      end
    end
    return true
  end
end

-- Check if function signature is valid
function validators.func(required_args)
  return function(value)
    if type(value) ~= 'function' then
      return false, 'Expected function'
    end
    -- Note: We can't check function signature in Lua
    return true
  end
end

-- Combine multiple validators
function validators.all(...)
  local validator_list = { ... }
  return function(value)
    for _, validator in ipairs(validator_list) do
      local valid, err = validator(value)
      if not valid then
        return false, err
      end
    end
    return true
  end
end

-- At least one validator must pass
function validators.any(...)
  local validator_list = { ... }
  return function(value)
    local errors = {}
    for _, validator in ipairs(validator_list) do
      local valid, err = validator(value)
      if valid then
        return true
      end
      table.insert(errors, err)
    end
    return false, table.concat(errors, ' OR ')
  end
end

-- Optional value (nil is allowed)
function validators.optional(validator)
  return function(value)
    if value == nil then
      return true
    end
    return validator(value)
  end
end

-- Configuration schema definition
M.schema = {
  -- Basic settings
  auto_open = validators.enum({ 'immediate', 'off' }),
  auto_open_delay = validators.all(validators.type('number'), validators.range(0, 60000)),
  log_level = validators.enum({ 'debug', 'info', 'warn', 'error' }),
  container_runtime = validators.enum({ 'docker', 'podman' }),

  -- Paths
  devcontainer_path = validators.type('string'),
  dockerfile_path = validators.type('string'),
  compose_file = validators.type('string'),

  -- Workspace settings
  workspace = {
    auto_mount = validators.type('boolean'),
    mount_point = validators.all(validators.type('string'), validators.pattern('^/', 'Must be an absolute path')),
    exclude_patterns = validators.array_of(validators.type('string')),
  },

  -- LSP settings
  lsp = {
    auto_setup = validators.type('boolean'),
    timeout = validators.all(validators.type('number'), validators.range(0, 30000)),
    port_range = validators.all(validators.array_of(validators.type('number')), function(value)
      if #value ~= 2 then
        return false, 'Must be array of exactly 2 numbers'
      end
      if value[1] >= value[2] then
        return false, 'First port must be less than second port'
      end
      if value[1] < 1024 or value[2] > 65535 then
        return false, 'Ports must be between 1024 and 65535'
      end
      return true
    end),
    servers = validators.type('table'),
    on_attach = validators.optional(validators.func()),
  },

  -- DAP settings
  dap = {
    auto_setup = validators.type('boolean'),
    auto_start_debugger = validators.type('boolean'),
    ports = {
      go = validators.all(validators.type('number'), validators.range(1024, 65535)),
      python = validators.all(validators.type('number'), validators.range(1024, 65535)),
      node = validators.all(validators.type('number'), validators.range(1024, 65535)),
      java = validators.all(validators.type('number'), validators.range(1024, 65535)),
    },
    path_mappings = {
      container_workspace = validators.all(
        validators.type('string'),
        validators.pattern('^/', 'Must be an absolute path')
      ),
      auto_detect_workspace = validators.type('boolean'),
    },
  },

  -- Terminal settings
  terminal = {
    default_shell = validators.type('string'),
    auto_insert = validators.type('boolean'),
    close_on_exit = validators.type('boolean'),
    close_on_container_stop = validators.type('boolean'),
    persistent_history = validators.type('boolean'),
    max_history_lines = validators.all(validators.type('number'), validators.range(0, 100000)),
    history_dir = validators.type('string'),
    default_position = validators.enum({ 'split', 'tab', 'float' }),
    split_command = validators.type('string'),
    float = {
      width = validators.all(validators.type('number'), validators.range(0.1, 1.0)),
      height = validators.all(validators.type('number'), validators.range(0.1, 1.0)),
      border = validators.enum({ 'single', 'double', 'rounded', 'solid', 'shadow', 'none' }),
      title = validators.type('string'),
      title_pos = validators.enum({ 'left', 'center', 'right' }),
    },
    environment = validators.array_of(validators.pattern('^[^=]+=.*', 'Must be in KEY=value format')),
    keymaps = validators.type('table'),
  },

  -- UI settings
  ui = {
    picker = validators.enum({ 'telescope', 'fzf-lua', 'vim.ui.select' }),
    show_notifications = validators.type('boolean'),
    notification_level = validators.enum({ 'verbose', 'normal', 'minimal', 'silent' }),
    status_line = validators.type('boolean'),
    icons = validators.type('table'),
    statusline = {
      format = validators.type('table'),
      labels = validators.type('table'),
      show_container_name = validators.type('boolean'),
      default_format = validators.type('string'),
    },
  },

  -- Port forwarding
  port_forwarding = {
    auto_forward = validators.type('boolean'),
    notification = validators.type('boolean'),
    bind_address = validators.pattern('^%d+%.%d+%.%d+%.%d+$', 'Must be valid IP address'),
    common_ports = validators.array_of(validators.all(validators.type('number'), validators.range(1, 65535))),
    enable_dynamic_ports = validators.type('boolean'),
    port_range_start = validators.all(validators.type('number'), validators.range(1024, 65534)),
    port_range_end = validators.all(validators.type('number'), validators.range(1025, 65535)),
    conflict_resolution = validators.enum({ 'auto', 'prompt', 'error' }),
  },

  -- Docker settings
  docker = {
    build_args = validators.type('table'),
    network_mode = validators.enum({ 'bridge', 'host', 'none' }),
    privileged = validators.type('boolean'),
    init = validators.type('boolean'),
    remove_orphans = validators.type('boolean'),
  },

  -- Test integration
  test_integration = {
    enabled = validators.type('boolean'),
    auto_setup = validators.type('boolean'),
    output_mode = validators.enum({ 'buffer', 'terminal', 'quickfix' }),
  },

  -- Development settings
  dev = {
    reload_on_change = validators.type('boolean'),
    debug_mode = validators.type('boolean'),
  },
}

-- Validate a value against a schema
local function validate_value(value, schema, path)
  path = path or ''

  if type(schema) == 'function' then
    -- Direct validator function
    local valid, err = schema(value)
    if not valid then
      return false, string.format('%s: %s', path, err)
    end
    return true
  elseif type(schema) == 'table' and type(value) == 'table' then
    -- Nested schema
    for key, sub_schema in pairs(schema) do
      local sub_path = path == '' and key or path .. '.' .. key
      local sub_value = value[key]

      if sub_value ~= nil then
        local valid, err = validate_value(sub_value, sub_schema, sub_path)
        if not valid then
          return false, err
        end
      end
    end
    return true
  end

  return true
end

-- Validate entire configuration
function M.validate(config)
  local errors = {}

  -- Validate against schema
  local valid, err = validate_value(config, M.schema)
  if not valid then
    table.insert(errors, err)
  end

  -- Additional cross-field validations
  if config.port_forwarding then
    local pf = config.port_forwarding
    if pf.port_range_start and pf.port_range_end and pf.port_range_start >= pf.port_range_end then
      table.insert(errors, 'port_forwarding: port_range_start must be less than port_range_end')
    end
  end

  -- Validate that required executables exist (skip in test environments)
  if config.container_runtime and vim.fn and vim.fn.executable then
    if vim.fn.executable(config.container_runtime) == 0 then
      table.insert(errors, string.format('container_runtime: %s executable not found', config.container_runtime))
    end
  end

  return #errors == 0, errors
end

-- Export validators for external use
M.validators = validators

return M
