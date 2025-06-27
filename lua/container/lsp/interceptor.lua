-- lua/container/lsp/interceptor.lua
-- Strategy C: Host-side LSP Message Interceptor
-- Intercepts all LSP messages and transforms paths between host and container

local M = {}
local log = require('container.utils.log')

-- Path transformation configuration
local path_config = {
  host_workspace = nil, -- Will be auto-detected
  container_workspace = '/workspace',
}

-- LSP methods that require path transformation
local TRANSFORM_RULES = {
  -- Initialization messages
  ['initialize'] = {
    request_paths = { 'rootUri', 'rootPath', 'workspaceFolders[].uri' },
    response_paths = {},
  },

  -- Document operations
  ['textDocument/didOpen'] = {
    request_paths = { 'textDocument.uri' },
    response_paths = {},
  },

  ['textDocument/didChange'] = {
    request_paths = { 'textDocument.uri' },
    response_paths = {},
  },

  ['textDocument/didSave'] = {
    request_paths = { 'textDocument.uri' },
    response_paths = {},
  },

  ['textDocument/didClose'] = {
    request_paths = { 'textDocument.uri' },
    response_paths = {},
  },

  -- Language features
  ['textDocument/definition'] = {
    request_paths = { 'textDocument.uri' },
    response_paths = { 'uri', 'targetUri', '[].uri' },
  },

  ['textDocument/references'] = {
    request_paths = { 'textDocument.uri' },
    response_paths = { '[].uri' },
  },

  ['textDocument/implementation'] = {
    request_paths = { 'textDocument.uri' },
    response_paths = { 'uri', 'targetUri', '[].uri' },
  },

  ['textDocument/typeDefinition'] = {
    request_paths = { 'textDocument.uri' },
    response_paths = { 'uri', 'targetUri', '[].uri' },
  },

  ['textDocument/declaration'] = {
    request_paths = { 'textDocument.uri' },
    response_paths = { 'uri', 'targetUri', '[].uri' },
  },

  ['textDocument/hover'] = {
    request_paths = { 'textDocument.uri' },
    response_paths = {},
  },

  ['textDocument/signatureHelp'] = {
    request_paths = { 'textDocument.uri' },
    response_paths = {},
  },

  ['textDocument/completion'] = {
    request_paths = { 'textDocument.uri' },
    response_paths = {},
  },

  -- Diagnostics
  ['textDocument/publishDiagnostics'] = {
    request_paths = {},
    notification_paths = { 'uri' },
  },

  -- Workspace operations
  ['workspace/didChangeWatchedFiles'] = {
    request_paths = { 'changes[].uri' },
    response_paths = {},
  },

  ['workspace/symbol'] = {
    request_paths = {},
    response_paths = { '[].location.uri' },
  },
}

-- Setup path configuration for interception
-- @param container_id string: target container ID
-- @param host_workspace string|nil: host workspace path (auto-detected if nil)
function M.setup_path_config(container_id, host_workspace)
  path_config.host_workspace = host_workspace or vim.fn.getcwd()
  path_config.container_id = container_id

  log.info(
    'Interceptor: Setup path config - Host: %s, Container: %s',
    path_config.host_workspace,
    path_config.container_workspace
  )
end

-- Transform path from host to container format
-- @param path string: host path
-- @return string: container path
local function host_to_container_path(path)
  if not path or type(path) ~= 'string' then
    return path
  end

  local host_workspace = path_config.host_workspace
  if not host_workspace then
    log.warn('Interceptor: Host workspace not configured, cannot transform path: %s', path)
    return path
  end

  -- Handle both absolute paths and URIs
  local transformed = path:gsub('^' .. vim.pesc(host_workspace), path_config.container_workspace)

  if transformed ~= path then
    log.debug('Interceptor: Transformed host->container: %s -> %s', path, transformed)
  end

  return transformed
end

-- Transform path from container to host format
-- @param path string: container path
-- @return string: host path
local function container_to_host_path(path)
  if not path or type(path) ~= 'string' then
    return path
  end

  local host_workspace = path_config.host_workspace
  if not host_workspace then
    log.warn('Interceptor: Host workspace not configured, cannot transform path: %s', path)
    return path
  end

  local transformed = path:gsub('^' .. vim.pesc(path_config.container_workspace), host_workspace)

  if transformed ~= path then
    log.debug('Interceptor: Transformed container->host: %s -> %s', path, transformed)
  end

  return transformed
end

-- Transform URIs in the given direction
-- @param uri string: URI to transform
-- @param direction string: "to_container" or "to_host"
-- @return string: transformed URI
local function transform_uri(uri, direction)
  if not uri or type(uri) ~= 'string' or not uri:match('^file://') then
    return uri
  end

  local path = uri:gsub('^file://', '')
  local transformed_path

  if direction == 'to_container' then
    transformed_path = host_to_container_path(path)
  else
    transformed_path = container_to_host_path(path)
  end

  return 'file://' .. transformed_path
end

-- Recursively transform paths in a nested table structure
-- @param obj any: object to transform
-- @param path_patterns table: list of path patterns to match
-- @param direction string: "to_container" or "to_host"
-- @return any: transformed object
local function transform_paths_recursive(obj, path_patterns, direction)
  if not obj or not path_patterns or #path_patterns == 0 then
    return obj
  end

  -- Deep copy to avoid modifying original
  local function deep_copy(original)
    if type(original) ~= 'table' then
      return original
    end
    local copy = {}
    for key, value in pairs(original) do
      copy[key] = deep_copy(value)
    end
    return copy
  end

  local result = deep_copy(obj)

  for _, pattern in ipairs(path_patterns) do
    -- Handle array patterns like "[].uri" or "changes[].uri"
    if pattern:match('%[%]') then
      local base_path, field = pattern:match('^(.*)%[%]%.(.+)$')

      local function transform_array(current_obj, path_parts, field_name)
        if #path_parts == 0 then
          -- We're at the array level
          if type(current_obj) == 'table' and #current_obj > 0 then
            for i, item in ipairs(current_obj) do
              if type(item) == 'table' and item[field_name] then
                current_obj[i][field_name] = transform_uri(item[field_name], direction)
              end
            end
          end
          return
        end

        local next_part = table.remove(path_parts, 1)
        if current_obj and current_obj[next_part] then
          transform_array(current_obj[next_part], path_parts, field_name)
        end
      end

      if base_path and base_path ~= '' then
        local path_parts = vim.split(base_path, '.', { plain = true })
        transform_array(result, path_parts, field)
      else
        -- Direct array pattern like "[].uri"
        transform_array(result, {}, field)
      end
    else
      -- Handle simple dot notation patterns like "textDocument.uri" or "rootUri"
      local path_parts = vim.split(pattern, '.', { plain = true })

      local function set_nested_value(current_obj, parts, value)
        if #parts == 1 then
          if current_obj and current_obj[parts[1]] then
            current_obj[parts[1]] = value
          end
          return
        end

        local next_part = table.remove(parts, 1)
        if current_obj and current_obj[next_part] then
          set_nested_value(current_obj[next_part], parts, value)
        end
      end

      local function get_nested_value(current_obj, parts)
        if #parts == 1 then
          return current_obj and current_obj[parts[1]]
        end

        local next_part = table.remove(parts, 1)
        if current_obj and current_obj[next_part] then
          return get_nested_value(current_obj[next_part], parts)
        end
        return nil
      end

      local current_value = get_nested_value(result, vim.split(pattern, '.', { plain = true }))
      if current_value then
        local transformed_value = transform_uri(current_value, direction)
        set_nested_value(result, vim.split(pattern, '.', { plain = true }), transformed_value)
      end
    end
  end

  return result
end

-- Transform request parameters
-- @param method string: LSP method name
-- @param params table: request parameters
-- @param direction string: "to_container" or "to_host"
-- @return table: transformed parameters
function M.transform_request_params(method, params, direction)
  local rule = TRANSFORM_RULES[method]
  if not rule or not rule.request_paths then
    return params
  end

  log.debug('Interceptor: Transforming request params for %s (%s)', method, direction)

  local transformed = transform_paths_recursive(params, rule.request_paths, direction)

  return transformed
end

-- Transform response data
-- @param method string: LSP method name
-- @param result any: response result
-- @param direction string: "to_container" or "to_host"
-- @return any: transformed result
function M.transform_response(method, result, direction)
  local rule = TRANSFORM_RULES[method]
  if not rule or not rule.response_paths then
    return result
  end

  log.debug('Interceptor: Transforming response for %s (%s)', method, direction)

  local transformed = transform_paths_recursive(result, rule.response_paths, direction)

  return transformed
end

-- Transform notification parameters
-- @param method string: LSP method name
-- @param params table: notification parameters
-- @param direction string: "to_container" or "to_host"
-- @return table: transformed parameters
function M.transform_notification_params(method, params, direction)
  local rule = TRANSFORM_RULES[method]
  if not rule or not rule.notification_paths then
    return params
  end

  log.debug('Interceptor: Transforming notification params for %s (%s)', method, direction)

  local transformed = transform_paths_recursive(params, rule.notification_paths, direction)

  return transformed
end

-- Check if method requires response transformation
-- @param method string: LSP method name
-- @return boolean: true if response should be transformed
function M.should_transform_response(method)
  local rule = TRANSFORM_RULES[method]
  return rule and rule.response_paths and #rule.response_paths > 0
end

-- Setup LSP client message interception
-- @param client table: LSP client object
-- @param container_id string: target container ID
function M.setup_client_interception(client, container_id)
  if not client then
    log.error('Interceptor: Invalid client provided for interception setup')
    return false
  end

  -- Setup path configuration
  M.setup_path_config(container_id)

  log.info(
    'Interceptor: Setting up message interception for client %s (container: %s)',
    client.name or 'unknown',
    container_id
  )

  -- Store original methods
  local original_request = client.request
  local original_notify = client.notify

  if not original_request or not original_notify then
    log.error('Interceptor: Client missing request or notify methods')
    return false
  end

  -- Intercept request method
  client.request = function(method, params, handler, bufnr)
    log.debug('Interceptor: Intercepting request: %s', method)

    -- Transform request parameters (host -> container)
    local transformed_params = M.transform_request_params(method, params, 'to_container')

    -- Wrap handler to transform response (container -> host)
    local wrapped_handler = handler
    if handler and M.should_transform_response(method) then
      wrapped_handler = function(err, result, ctx)
        if result then
          log.debug('Interceptor: Transforming response for: %s', method)
          result = M.transform_response(method, result, 'to_host')
        end
        return handler(err, result, ctx)
      end
    end

    return original_request(method, transformed_params, wrapped_handler, bufnr)
  end

  -- Intercept notify method
  client.notify = function(method, params)
    log.debug('Interceptor: Intercepting notification: %s', method)

    -- Transform notification parameters (host -> container)
    local transformed_params = M.transform_request_params(method, params, 'to_container')

    return original_notify(method, transformed_params)
  end

  -- Setup handler for incoming notifications (server -> client)
  local original_handlers = client.config.handlers or {}
  local new_handlers = {}

  -- Add transformation to publishDiagnostics and other notifications
  for method, rule in pairs(TRANSFORM_RULES) do
    if rule.notification_paths and #rule.notification_paths > 0 then
      local original_handler = original_handlers[method] or vim.lsp.handlers[method]

      new_handlers[method] = function(err, result, ctx, config)
        if result then
          log.debug('Interceptor: Transforming incoming notification: %s', method)
          result = M.transform_notification_params(method, result, 'to_host')
        end

        if original_handler then
          return original_handler(err, result, ctx, config)
        end
      end
    end
  end

  -- Update client handlers
  if client.config then
    client.config.handlers = vim.tbl_extend('force', original_handlers, new_handlers)
  end

  log.info('Interceptor: Successfully set up interception for client %s', client.name or 'unknown')
  return true
end

-- Get current path configuration (for debugging)
-- @return table: current path configuration
function M.get_path_config()
  return vim.tbl_deep_extend('force', {}, path_config)
end

-- Get transformation rules (for debugging)
-- @return table: transformation rules
function M.get_transform_rules()
  return vim.tbl_deep_extend('force', {}, TRANSFORM_RULES)
end

return M
