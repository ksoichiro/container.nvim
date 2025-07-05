-- Simple path transformation utility for container LSP
-- This module provides direct path transformation between host and container
-- without complex message interception

local M = {}
local log = require('container.utils.log')

-- Configuration for path mappings
local config = {
  -- Default container workspace path
  container_workspace = '/workspace',
  -- Host workspace will be auto-detected or set explicitly
  host_workspace = nil,
  -- Cache for transformed paths
  path_cache = {},
}

-- Initialize path configuration
-- @param opts table: configuration options
function M.setup(opts)
  opts = opts or {}

  if opts.container_workspace then
    config.container_workspace = opts.container_workspace
  end

  -- Auto-detect host workspace if not provided
  config.host_workspace = opts.host_workspace or vim.fn.getcwd()

  -- Clear cache on setup
  config.path_cache = {}

  log.debug(
    'Simple Transform: Initialized with host=%s, container=%s',
    config.host_workspace,
    config.container_workspace
  )
end

-- Convert host path to container path
-- @param host_path string: absolute host path
-- @return string: container path
function M.host_to_container(host_path)
  if not host_path then
    return nil
  end

  -- Check cache first
  local cached = config.path_cache[host_path]
  if cached then
    return cached
  end

  -- Ensure we have host workspace configured
  if not config.host_workspace then
    config.host_workspace = vim.fn.getcwd()
  end

  -- Simple string replacement
  local container_path = host_path:gsub('^' .. vim.pesc(config.host_workspace), config.container_workspace)

  -- Cache the result
  config.path_cache[host_path] = container_path

  log.debug('Simple Transform: %s -> %s', host_path, container_path)
  return container_path
end

-- Convert container path to host path
-- @param container_path string: container path
-- @return string: host path
function M.container_to_host(container_path)
  if not container_path then
    return nil
  end

  -- Simple string replacement
  local host_path = container_path:gsub('^' .. vim.pesc(config.container_workspace), config.host_workspace)

  log.debug('Simple Transform: %s -> %s', container_path, host_path)
  return host_path
end

-- Convert host URI to container URI
-- @param host_uri string: file:// URI with host path
-- @return string: file:// URI with container path
function M.host_uri_to_container(host_uri)
  if not host_uri or not host_uri:match('^file://') then
    return host_uri
  end

  -- Extract path from URI
  local host_path = host_uri:gsub('^file://', '')

  -- Transform path
  local container_path = M.host_to_container(host_path)

  -- Return as URI
  return 'file://' .. container_path
end

-- Convert container URI to host URI
-- @param container_uri string: file:// URI with container path
-- @return string: file:// URI with host path
function M.container_uri_to_host(container_uri)
  if not container_uri or not container_uri:match('^file://') then
    return container_uri
  end

  -- Extract path from URI
  local container_path = container_uri:gsub('^file://', '')

  -- Transform path
  local host_path = M.container_to_host(container_path)

  -- Return as URI
  return 'file://' .. host_path
end

-- Get current buffer's container URI
-- @param bufnr number|nil: buffer number (0 or nil for current)
-- @return string: container URI for the buffer
function M.get_buffer_container_uri(bufnr)
  bufnr = bufnr or 0

  -- Get buffer's absolute path
  local host_path = vim.api.nvim_buf_get_name(bufnr)
  if host_path == '' then
    return nil
  end

  -- Convert to absolute path if needed
  if not vim.startswith(host_path, '/') then
    host_path = vim.fn.fnamemodify(host_path, ':p')
  end

  -- Convert to container path
  local container_path = M.host_to_container(host_path)

  -- Return as URI
  return 'file://' .. container_path
end

-- Transform LSP location (single location object)
-- @param location table: LSP location with uri field
-- @param direction string: "to_host" or "to_container"
-- @return table: transformed location
function M.transform_location(location, direction)
  if not location or not location.uri then
    return location
  end

  local transformed = vim.deepcopy(location)

  if direction == 'to_host' then
    transformed.uri = M.container_uri_to_host(location.uri)
  else
    transformed.uri = M.host_uri_to_container(location.uri)
  end

  return transformed
end

-- Transform LSP locations (array or single location)
-- @param locations table|array: LSP location(s)
-- @param direction string: "to_host" or "to_container"
-- @return table|array: transformed location(s)
function M.transform_locations(locations, direction)
  if not locations then
    return locations
  end

  -- Handle single location
  if locations.uri then
    return M.transform_location(locations, direction)
  end

  -- Handle array of locations
  if type(locations) == 'table' and #locations > 0 then
    local transformed = {}
    for i, loc in ipairs(locations) do
      transformed[i] = M.transform_location(loc, direction)
    end
    return transformed
  end

  return locations
end

-- Get configuration (for debugging)
-- @return table: current configuration
function M.get_config()
  return vim.deepcopy(config)
end

-- Clear path cache
function M.clear_cache()
  config.path_cache = {}
  log.debug('Simple Transform: Path cache cleared')
end

return M
