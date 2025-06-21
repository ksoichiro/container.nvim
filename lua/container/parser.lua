-- lua/devcontainer/parser.lua
-- devcontainer.json parsing

local M = {}
local fs = require('container.utils.fs')
local log = require('container.utils.log')

-- Remove comments from JSON string
local function remove_json_comments(content)
  -- Remove line comments //
  content = content:gsub('//[^\n]*', '')
  -- Remove block comments /* */
  content = content:gsub('/%*.-*/', '')
  return content
end

-- JSON parsing
local function parse_json(content)
  content = remove_json_comments(content)

  local success, result = pcall(vim.json.decode, content)
  if not success then
    return nil, 'Invalid JSON: ' .. result
  end

  return result
end

-- Variable expansion
local function expand_variables(str, context)
  if type(str) ~= 'string' then
    return str
  end

  context = context or {}

  -- Expand ${localWorkspaceFolder}
  str = str:gsub('${localWorkspaceFolder}', context.workspace_folder or vim.fn.getcwd())

  -- Expand ${containerWorkspaceFolder}
  str = str:gsub('${containerWorkspaceFolder}', context.container_workspace or '/workspace')

  -- Expand ${localEnv:variable_name}
  str = str:gsub('${localEnv:([^}]+)}', function(var_name)
    return os.getenv(var_name) or ''
  end)

  -- Expand ${containerEnv:variable_name} (keep as placeholder)
  str = str:gsub('${containerEnv:([^}]+)}', function(var_name)
    return '${containerEnv:' .. var_name .. '}'
  end)

  return str
end

-- Generate project ID based on project path
function M.generate_project_id(project_path)
  project_path = project_path or vim.fn.getcwd()
  -- Use project directory name and path hash for uniqueness
  local project_name = fs.basename(project_path)
  local path_hash = vim.fn.sha256(project_path):sub(1, 8)
  return string.format('%s-%s', project_name, path_hash)
end

-- Resolve dynamic ports to actual port numbers
function M.resolve_dynamic_ports(config, plugin_config)
  if not config.normalized_ports or #config.normalized_ports == 0 then
    return config
  end

  local port_utils = require('container.utils.port')
  local project_id = config.project_id

  -- Check if dynamic ports are enabled
  if not plugin_config.port_forwarding.enable_dynamic_ports then
    log.debug('Dynamic ports disabled, using only fixed ports')
    return config
  end

  local port_specs = {}
  for _, port_entry in ipairs(config.normalized_ports) do
    if port_entry.type == 'auto' then
      table.insert(port_specs, string.format('auto:%d', port_entry.container_port))
    elseif port_entry.type == 'range' then
      table.insert(
        port_specs,
        string.format('range:%d-%d:%d', port_entry.range_start, port_entry.range_end, port_entry.container_port)
      )
    else
      -- Fixed ports remain as-is
      table.insert(port_specs, port_entry.original_spec)
    end
  end

  local resolved_ports, errors = port_utils.resolve_dynamic_ports(port_specs, project_id, {
    port_range_start = plugin_config.port_forwarding.port_range_start,
    port_range_end = plugin_config.port_forwarding.port_range_end,
  })

  if errors and #errors > 0 then
    log.warn('Port resolution errors for project %s:', project_id)
    for _, error in ipairs(errors) do
      log.warn('  %s', error)
    end

    if plugin_config.port_forwarding.conflict_resolution == 'error' then
      return nil, 'Port resolution failed: ' .. table.concat(errors, '; ')
    end
  end

  -- Replace normalized_ports with resolved ports
  config.normalized_ports = resolved_ports or {}
  config.port_resolution_errors = errors or {}

  log.info('Resolved %d ports for project %s', #config.normalized_ports, project_id)

  return config
end

-- Variable expansion for all string fields in configuration
local function expand_config_variables(config, context)
  if type(config) ~= 'table' then
    return config
  end

  local result = {}

  for key, value in pairs(config) do
    if type(value) == 'string' then
      result[key] = expand_variables(value, context)
    elseif type(value) == 'table' then
      result[key] = expand_config_variables(value, context)
    else
      result[key] = value
    end
  end

  return result
end

-- Search for devcontainer.json file
function M.find_devcontainer_json(start_path)
  start_path = start_path or vim.fn.getcwd()

  -- Search for .devcontainer/devcontainer.json
  local devcontainer_path = fs.find_file_upward(start_path, '.devcontainer/devcontainer.json')
  if devcontainer_path then
    return devcontainer_path
  end

  -- Search for devcontainer.json
  devcontainer_path = fs.find_file_upward(start_path, 'devcontainer.json')
  if devcontainer_path then
    return devcontainer_path
  end

  return nil
end

-- Resolve Dockerfile path
local function resolve_dockerfile_path(config, base_path)
  if not config.dockerFile then
    return nil
  end

  local dockerfile_path = config.dockerFile
  if not fs.is_absolute_path(dockerfile_path) then
    dockerfile_path = fs.join_path(base_path, dockerfile_path)
  end

  return fs.resolve_path(dockerfile_path)
end

-- Resolve docker-compose.yml path
local function resolve_compose_file_path(config, base_path)
  if not config.dockerComposeFile then
    return nil
  end

  local compose_path = config.dockerComposeFile
  if not fs.is_absolute_path(compose_path) then
    compose_path = fs.join_path(base_path, compose_path)
  end

  return fs.resolve_path(compose_path)
end

-- Normalize port settings with dynamic port support
local function normalize_ports(ports)
  if not ports then
    return {}
  end

  local normalized = {}

  for i, port in ipairs(ports) do
    local port_entry = {
      protocol = 'tcp',
      original_spec = port,
      index = i,
    }

    if type(port) == 'number' then
      port_entry.type = 'fixed'
      port_entry.host_port = port
      port_entry.container_port = port
    elseif type(port) == 'string' then
      -- Check for auto allocation: "auto:3000"
      local auto_container_port = port:match('^auto:(%d+)$')
      if auto_container_port then
        port_entry.type = 'auto'
        port_entry.container_port = tonumber(auto_container_port)
        -- host_port will be assigned during resolution
      else
        -- Check for range allocation: "range:8000-8010:3000"
        local range_start, range_end, container_port = port:match('^range:(%d+)-(%d+):(%d+)$')
        if range_start and range_end and container_port then
          port_entry.type = 'range'
          port_entry.range_start = tonumber(range_start)
          port_entry.range_end = tonumber(range_end)
          port_entry.container_port = tonumber(container_port)
          -- host_port will be assigned during resolution
        else
          -- Check for host:container mapping: "8080:3000"
          local host_port, container_port_2 = port:match('(%d+):(%d+)')
          if host_port and container_port_2 then
            port_entry.type = 'fixed'
            port_entry.host_port = tonumber(host_port)
            port_entry.container_port = tonumber(container_port_2)
          else
            -- Single port as string: "3000"
            local single_port = tonumber(port)
            if single_port then
              port_entry.type = 'fixed'
              port_entry.host_port = single_port
              port_entry.container_port = single_port
            else
              log.warn('Invalid port specification at index %d: %s', i, tostring(port))
              goto continue
            end
          end
        end
      end
    elseif type(port) == 'table' then
      port_entry.type = 'fixed'
      port_entry.host_port = port.hostPort or port.containerPort
      port_entry.container_port = port.containerPort
      port_entry.protocol = port.protocol or 'tcp'
    else
      log.warn('Unsupported port specification type at index %d: %s', i, type(port))
      goto continue
    end

    table.insert(normalized, port_entry)
    ::continue::
  end

  return normalized
end

-- Normalize mount settings
local function normalize_mounts(mounts, context)
  if not mounts then
    return {}
  end

  local normalized = {}

  for _, mount in ipairs(mounts) do
    if type(mount) == 'string' then
      -- Parse "source=...,target=...,type=..." format string
      local mount_config = {}
      for pair in mount:gmatch('[^,]+') do
        local key, value = pair:match('([^=]+)=(.+)')
        if key and value then
          mount_config[key:match('^%s*(.-)%s*$')] = expand_variables(value:match('^%s*(.-)%s*$'), context)
        end
      end

      if mount_config.source and mount_config.target then
        table.insert(normalized, {
          type = mount_config.type or 'bind',
          source = mount_config.source,
          target = mount_config.target,
          readonly = mount_config.readonly == 'true',
          consistency = mount_config.consistency,
        })
      end
    elseif type(mount) == 'table' then
      table.insert(normalized, {
        type = mount.type or 'bind',
        source = expand_variables(mount.source, context),
        target = expand_variables(mount.target, context),
        readonly = mount.readonly or false,
        consistency = mount.consistency,
      })
    end
  end

  return normalized
end

-- Parse devcontainer.json
function M.parse(file_path, context)
  context = context or {}

  if not fs.is_file(file_path) then
    return nil, 'File not found: ' .. file_path
  end

  log.debug('Parsing devcontainer.json: %s', file_path)

  -- Read file
  local content, err = fs.read_file(file_path)
  if not content then
    return nil, 'Failed to read file: ' .. err
  end

  -- Parse JSON
  local config, parse_err = parse_json(content)
  if not config then
    return nil, parse_err
  end

  -- Debug: postCreateCommand after parsing
  log.debug('Raw config postCreateCommand: %s', tostring(config.postCreateCommand))

  -- Set base path
  local base_path = fs.dirname(file_path)
  -- Set workspace_folder to parent directory of .devcontainer (project root)
  context.workspace_folder = context.workspace_folder or fs.dirname(base_path)
  context.devcontainer_folder = base_path

  -- Set context for variable expansion
  context.container_workspace = config.workspaceFolder or '/workspace'

  -- Expand configuration
  config = expand_config_variables(config, context)

  -- Resolve paths
  config.resolved_dockerfile = resolve_dockerfile_path(config, base_path)
  config.resolved_compose_file = resolve_compose_file_path(config, base_path)

  -- Normalize port settings
  config.normalized_ports = normalize_ports(config.forwardPorts)

  -- Generate project ID for port allocation
  config.project_id = M.generate_project_id(context.workspace_folder or vim.fn.getcwd())

  -- Normalize mount settings
  config.normalized_mounts = normalize_mounts(config.mounts, context)

  -- Set default values
  config.name = config.name or 'devcontainer'
  config.workspaceFolder = config.workspaceFolder or '/workspace'
  config.remoteUser = config.remoteUser or 'root'

  -- Debug: final postCreateCommand
  log.debug('Final config postCreateCommand: %s', tostring(config.postCreateCommand))

  log.info('Successfully parsed devcontainer.json: %s', config.name)
  return config
end

-- Check existence and parse devcontainer.json
function M.find_and_parse(start_path, context)
  local devcontainer_path = M.find_devcontainer_json(start_path)
  if not devcontainer_path then
    return nil, 'No devcontainer.json found'
  end

  return M.parse(devcontainer_path, context)
end

-- Validate configuration
function M.validate(config)
  local errors = {}

  -- Check required fields
  if not config.name then
    table.insert(errors, 'Missing required field: name')
  end

  -- Check Dockerfile or image specification
  if not config.dockerFile and not config.image and not config.dockerComposeFile then
    table.insert(errors, 'Must specify one of: dockerFile, image, or dockerComposeFile')
  end

  -- Validate port settings
  if config.normalized_ports then
    for _, port in ipairs(config.normalized_ports) do
      if not port.container_port or port.container_port <= 0 or port.container_port > 65535 then
        table.insert(errors, 'Invalid container port: ' .. tostring(port.container_port))
      end

      -- Only validate host_port for fixed ports (auto/range ports don't have host_port yet)
      if port.type == 'fixed' then
        if not port.host_port or port.host_port <= 0 or port.host_port > 65535 then
          table.insert(errors, 'Invalid host port: ' .. tostring(port.host_port))
        end
      elseif port.type == 'range' then
        -- Validate range boundaries
        if not port.range_start or not port.range_end then
          table.insert(errors, 'Range port missing start or end boundary')
        elseif port.range_start >= port.range_end then
          table.insert(errors, 'Range port start must be less than end')
        elseif port.range_start <= 0 or port.range_end > 65535 then
          table.insert(errors, 'Range port boundaries must be 1-65535')
        end
      end
    end
  end

  -- Validate mount settings
  if config.normalized_mounts then
    for _, mount in ipairs(config.normalized_mounts) do
      if not mount.source or mount.source == '' then
        table.insert(errors, 'Mount source cannot be empty')
      end
      if not mount.target or mount.target == '' then
        table.insert(errors, 'Mount target cannot be empty')
      end
    end
  end

  -- Validate environment customizations
  if config.customizations then
    local environment = require('container.environment')
    local env_errors = environment.validate_environment(config)
    for _, err in ipairs(env_errors) do
      table.insert(errors, err)
    end
  end

  return errors
end

-- Validate resolved port configuration (after dynamic port resolution)
function M.validate_resolved_ports(config)
  local errors = {}

  if config.normalized_ports then
    for _, port in ipairs(config.normalized_ports) do
      if not port.container_port or port.container_port <= 0 or port.container_port > 65535 then
        table.insert(errors, 'Invalid container port: ' .. tostring(port.container_port))
      end

      -- All ports should have host_port after resolution
      if not port.host_port or port.host_port <= 0 or port.host_port > 65535 then
        table.insert(errors, 'Invalid or missing host port after resolution: ' .. tostring(port.host_port))
      end
    end
  end

  return errors
end

-- Normalize configuration for plugin use
function M.normalize_for_plugin(config)
  local normalized = {}

  -- Basic settings
  normalized.name = config.name or 'devcontainer'
  normalized.image = config.image
  normalized.dockerfile = config.resolved_dockerfile
  normalized.context = config.build and config.build.context or '.'
  normalized.build_args = config.build and config.build.args or {}
  normalized.workspace_folder = config.workspaceFolder or '/workspace'
  normalized.remote_user = config.remoteUser

  -- Environment variables
  normalized.environment = config.remoteEnv or {}

  -- Port settings
  normalized.ports = config.normalized_ports or {}

  -- Mount settings
  normalized.mounts = config.normalized_mounts or {}

  -- Feature settings
  normalized.features = config.features or {}

  -- Customizations
  normalized.customizations = config.customizations or {}

  -- Lifecycle commands
  normalized.post_create_command = config.postCreateCommand
  normalized.post_start_command = config.postStartCommand
  normalized.post_attach_command = config.postAttachCommand

  -- Security settings
  normalized.privileged = config.privileged or false
  normalized.cap_add = config.capAdd or {}
  normalized.security_opt = config.securityOpt or {}
  normalized.init = config.init

  -- Other Docker settings
  normalized.run_args = config.runArgs or {}
  normalized.override_command = config.overrideCommand
  normalized.shutdown_action = config.shutdownAction

  -- Force rebuild flag
  normalized.force_rebuild = false

  -- Port attributes
  normalized.port_attributes = config.portsAttributes or {}

  return normalized
end

-- Merge with plugin configuration
function M.merge_with_plugin_config(devcontainer_config, plugin_config)
  -- Items that can be overridden by plugin configuration
  if plugin_config.container_runtime then
    devcontainer_config.container_runtime = plugin_config.container_runtime
  end

  if plugin_config.log_level then
    devcontainer_config.log_level = plugin_config.log_level
  end

  -- Merge plugin-specific settings
  devcontainer_config.plugin_config = plugin_config

  return devcontainer_config
end

-- Find all devcontainer projects in a directory tree
function M.find_devcontainer_projects(root_path, max_depth)
  root_path = root_path or vim.fn.getcwd()
  max_depth = max_depth or 3

  local projects = {}
  local visited = {}

  local function scan_directory(path, depth)
    if depth > max_depth then
      return
    end

    -- Skip if already visited
    local real_path = vim.fn.resolve(path)
    if visited[real_path] then
      return
    end
    visited[real_path] = true

    -- Check for devcontainer.json in this directory
    local devcontainer_paths = {
      fs.join_path(path, '.devcontainer', 'devcontainer.json'),
      fs.join_path(path, 'devcontainer.json'),
    }

    for _, devcontainer_path in ipairs(devcontainer_paths) do
      if fs.is_file(devcontainer_path) then
        local config, err = M.parse(devcontainer_path)
        if config then
          table.insert(projects, {
            path = path,
            name = fs.basename(path),
            config = config,
            devcontainer_path = devcontainer_path,
          })
        else
          log.warn('Failed to parse %s: %s', devcontainer_path, err)
        end
        -- Don't scan subdirectories if we found a devcontainer here
        return
      end
    end

    -- Scan subdirectories
    local entries = vim.fn.readdir(path)
    if entries then
      for _, entry in ipairs(entries) do
        local entry_path = fs.join_path(path, entry)
        -- Skip hidden directories, node_modules, etc.
        if
          not entry:match('^%.')
          and entry ~= 'node_modules'
          and entry ~= '__pycache__'
          and entry ~= 'target'
          and entry ~= 'build'
          and entry ~= 'dist'
          and fs.is_directory(entry_path)
        then
          scan_directory(entry_path, depth + 1)
        end
      end
    end
  end

  scan_directory(root_path, 0)

  return projects
end

-- Expose normalize_ports for testing
M.normalize_ports = normalize_ports

return M
