-- lua/devcontainer/utils/port.lua
-- Port utility functions for dynamic port allocation and management

local M = {}
local log = require('devcontainer.utils.log')

-- Port range configuration
local DEFAULT_DYNAMIC_PORT_START = 10000
local DEFAULT_DYNAMIC_PORT_END = 20000
local MAX_PORT_ATTEMPTS = 1000

-- State for tracking allocated ports across projects
local allocated_ports = {}

-- Check if a port is available on the host
local function is_port_available(port)
  local sock = vim.loop.new_tcp()
  if not sock then
    return false
  end

  local success = sock:bind('127.0.0.1', port)
  sock:close()

  return success
end

-- Find an available port within a specified range
function M.find_available_port(start_port, end_port, exclude_ports)
  start_port = start_port or DEFAULT_DYNAMIC_PORT_START
  end_port = end_port or DEFAULT_DYNAMIC_PORT_END
  exclude_ports = exclude_ports or {}

  log.debug("Searching for available port in range %d-%d", start_port, end_port)

  -- Convert exclude_ports to a set for faster lookup
  local exclude_set = {}
  for _, port in ipairs(exclude_ports) do
    exclude_set[port] = true
  end

  local attempts = 0
  for port = start_port, end_port do
    attempts = attempts + 1

    -- Skip if port is in exclude list
    if not exclude_set[port] then
      -- Skip if port is already allocated by us
      if not allocated_ports[port] then
        if is_port_available(port) then
          log.debug("Found available port: %d (after %d attempts)", port, attempts)
          return port
        end
      end
    end

    -- Safety check to avoid infinite loops
    if attempts >= MAX_PORT_ATTEMPTS then
      break
    end
  end

  log.warn("No available port found in range %d-%d after %d attempts", start_port, end_port, attempts)
  return nil
end

-- Reserve a port for a specific project/container
function M.allocate_port(port, project_id, purpose)
  if allocated_ports[port] then
    log.warn("Port %d is already allocated to %s", port, allocated_ports[port].project_id)
    return false
  end

  allocated_ports[port] = {
    project_id = project_id or "unknown",
    purpose = purpose or "generic",
    allocated_at = os.time()
  }

  log.info("Allocated port %d for project '%s' (%s)", port, project_id, purpose)
  return true
end

-- Release a port allocation
function M.release_port(port)
  if allocated_ports[port] then
    local info = allocated_ports[port]
    allocated_ports[port] = nil
    log.info("Released port %d (was allocated to %s)", port, info.project_id)
    return true
  end

  log.debug("Port %d was not allocated, nothing to release", port)
  return false
end

-- Release all ports for a specific project
function M.release_project_ports(project_id)
  local released_count = 0

  for port, info in pairs(allocated_ports) do
    if info.project_id == project_id then
      allocated_ports[port] = nil
      released_count = released_count + 1
      log.debug("Released port %d for project %s", port, project_id)
    end
  end

  if released_count > 0 then
    log.info("Released %d ports for project '%s'", released_count, project_id)
  end

  return released_count
end

-- Get all allocated ports
function M.get_allocated_ports()
  return vim.deepcopy(allocated_ports)
end

-- Get allocated ports for a specific project
function M.get_project_ports(project_id)
  local project_ports = {}

  for port, info in pairs(allocated_ports) do
    if info.project_id == project_id then
      project_ports[port] = info
    end
  end

  return project_ports
end

-- Check if a specific port is allocated
function M.is_port_allocated(port)
  return allocated_ports[port] ~= nil
end

-- Parse port specification string
function M.parse_port_spec(port_spec)
  if type(port_spec) == "number" then
    return {
      type = "fixed",
      host_port = port_spec,
      container_port = port_spec
    }
  end

  if type(port_spec) ~= "string" then
    return nil, "Invalid port specification type"
  end

  -- Handle "auto:container_port" format
  local auto_match = port_spec:match("^auto:(%d+)$")
  if auto_match then
    return {
      type = "auto",
      container_port = tonumber(auto_match)
    }
  end

  -- Handle "range:start-end:container_port" format
  local range_start, range_end, container_port = port_spec:match("^range:(%d+)-(%d+):(%d+)$")
  if range_start and range_end and container_port then
    return {
      type = "range",
      range_start = tonumber(range_start),
      range_end = tonumber(range_end),
      container_port = tonumber(container_port)
    }
  end

  -- Handle "host_port:container_port" format (existing)
  local host_port, container_port_2 = port_spec:match("^(%d+):(%d+)$")
  if host_port and container_port_2 then
    return {
      type = "fixed",
      host_port = tonumber(host_port),
      container_port = tonumber(container_port_2)
    }
  end

  -- Handle single port number as string
  local single_port = tonumber(port_spec)
  if single_port then
    return {
      type = "fixed",
      host_port = single_port,
      container_port = single_port
    }
  end

  return nil, "Invalid port specification format: " .. port_spec
end

-- Resolve dynamic port specifications to actual ports
function M.resolve_dynamic_ports(port_specs, project_id, config)
  local resolved_ports = {}
  local errors = {}

  config = config or {}
  local port_range_start = config.port_range_start or DEFAULT_DYNAMIC_PORT_START
  local port_range_end = config.port_range_end or DEFAULT_DYNAMIC_PORT_END

  -- Collect already used ports to avoid conflicts
  local used_ports = {}
  for _, resolved in ipairs(resolved_ports) do
    if resolved.host_port then
      table.insert(used_ports, resolved.host_port)
    end
  end

  for i, port_spec in ipairs(port_specs) do
    local parsed, err = M.parse_port_spec(port_spec)
    if not parsed then
      table.insert(errors, string.format("Port %d: %s", i, err))
      goto continue
    end

    local resolved_port = {
      container_port = parsed.container_port,
      protocol = "tcp",
      original_spec = port_spec
    }

    if parsed.type == "fixed" then
      resolved_port.host_port = parsed.host_port
      resolved_port.type = "fixed"

    elseif parsed.type == "auto" then
      local available_port = M.find_available_port(port_range_start, port_range_end, used_ports)
      if not available_port then
        table.insert(errors, string.format("Port %d: No available port for auto allocation", i))
        goto continue
      end

      resolved_port.host_port = available_port
      resolved_port.type = "dynamic"
      table.insert(used_ports, available_port)

      -- Allocate the port
      M.allocate_port(available_port, project_id, "auto-allocated")

    elseif parsed.type == "range" then
      local available_port = M.find_available_port(parsed.range_start, parsed.range_end, used_ports)
      if not available_port then
        table.insert(errors, string.format("Port %d: No available port in range %d-%d", i, parsed.range_start, parsed.range_end))
        goto continue
      end

      resolved_port.host_port = available_port
      resolved_port.type = "dynamic"
      resolved_port.range_start = parsed.range_start
      resolved_port.range_end = parsed.range_end
      table.insert(used_ports, available_port)

      -- Allocate the port
      M.allocate_port(available_port, project_id, "range-allocated")
    end

    table.insert(resolved_ports, resolved_port)

    ::continue::
  end

  if #errors > 0 then
    return resolved_ports, errors
  end

  return resolved_ports
end

-- Get port allocation statistics
function M.get_port_statistics()
  local stats = {
    total_allocated = 0,
    by_project = {},
    by_purpose = {},
    port_range_usage = {
      start = DEFAULT_DYNAMIC_PORT_START,
      end_port = DEFAULT_DYNAMIC_PORT_END,
      allocated_in_range = 0
    }
  }

  for port, info in pairs(allocated_ports) do
    stats.total_allocated = stats.total_allocated + 1

    -- Count by project
    stats.by_project[info.project_id] = (stats.by_project[info.project_id] or 0) + 1

    -- Count by purpose
    stats.by_purpose[info.purpose] = (stats.by_purpose[info.purpose] or 0) + 1

    -- Count in default range
    if port >= DEFAULT_DYNAMIC_PORT_START and port <= DEFAULT_DYNAMIC_PORT_END then
      stats.port_range_usage.allocated_in_range = stats.port_range_usage.allocated_in_range + 1
    end
  end

  return stats
end

-- Validate port range configuration
function M.validate_port_config(config)
  local errors = {}

  if config.port_range_start and config.port_range_end then
    if config.port_range_start >= config.port_range_end then
      table.insert(errors, "port_range_start must be less than port_range_end")
    end

    if config.port_range_start < 1024 then
      table.insert(errors, "port_range_start should be >= 1024 to avoid system ports")
    end

    if config.port_range_end > 65535 then
      table.insert(errors, "port_range_end must be <= 65535")
    end
  end

  return errors
end

return M
