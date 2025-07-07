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

  -- Check if path is already in container format
  if path:match('^' .. vim.pesc(path_config.container_workspace)) then
    log.debug('Interceptor: Path already in container format, skipping transformation: %s', path)
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

  -- Check if path is already in host format
  if path:match('^' .. vim.pesc(host_workspace)) then
    log.debug('Interceptor: Path already in host format, skipping transformation: %s', path)
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
  if not uri or type(uri) ~= 'string' then
    log.warn('Interceptor: Invalid URI for transformation: %s (%s)', tostring(uri), type(uri))
    return uri
  end

  -- Handle URIs without file:// scheme
  if not uri:match('^file://') then
    log.warn('Interceptor: URI missing file:// scheme: %s', uri)
    -- If it looks like an absolute path, add the scheme
    if uri:match('^/') then
      uri = 'file://' .. uri
      log.debug('Interceptor: Added file:// scheme: %s', uri)
    else
      log.warn('Interceptor: Cannot process relative path URI: %s', uri)
      return uri
    end
  end

  local path = uri:gsub('^file://', '')
  local transformed_path

  -- Prevent unnecessary transformations by checking the current format
  if direction == 'to_container' then
    -- Only transform if it's not already in container format
    if not path:match('^' .. vim.pesc(path_config.container_workspace)) then
      transformed_path = host_to_container_path(path)
    else
      log.debug('Interceptor: URI already in container format: %s', uri)
      return uri
    end
  else -- to_host
    -- Only transform if it's not already in host format
    local host_workspace = path_config.host_workspace
    if host_workspace and not path:match('^' .. vim.pesc(host_workspace)) then
      transformed_path = container_to_host_path(path)
    else
      log.debug('Interceptor: URI already in host format: %s', uri)
      return uri
    end
  end

  local result = 'file://' .. transformed_path
  if result ~= uri then
    log.debug('Interceptor: URI transformation (%s): %s -> %s', direction, uri, result)
  end

  -- Validate the result has proper scheme
  if not result:match('^file://') then
    log.error('Interceptor: Transformation resulted in invalid URI: %s', result)
    result = 'file://' .. result
  end

  return result
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
        log.debug('Interceptor: Found value for pattern %s: %s', pattern, current_value)
        local transformed_value = transform_uri(current_value, direction)
        log.debug('Interceptor: Transformed %s: %s -> %s', pattern, current_value, transformed_value)
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
  log.debug('Interceptor: Original params: %s', vim.inspect(params))

  local transformed = transform_paths_recursive(params, rule.request_paths, direction)

  if transformed ~= params then
    log.debug('Interceptor: Transformed params: %s', vim.inspect(transformed))
  else
    log.debug('Interceptor: No transformation needed for %s', method)
  end

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
  log.debug('Interceptor: Original response: %s', vim.inspect(result))

  local transformed = transform_paths_recursive(result, rule.response_paths, direction)

  if transformed ~= result then
    log.debug('Interceptor: Transformed response: %s', vim.inspect(transformed))
  else
    log.debug('Interceptor: No transformation needed for response %s', method)
  end

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

  -- Special detailed logging for publishDiagnostics
  if method == 'textDocument/publishDiagnostics' then
    log.info('Interceptor: Processing publishDiagnostics - Original URI: %s', params.uri or 'nil')
    log.debug('Interceptor: Full diagnostics payload: %s', vim.inspect(params))
  else
    log.debug('Interceptor: Original notification params: %s', vim.inspect(params))
  end

  local transformed = transform_paths_recursive(params, rule.notification_paths, direction)

  if method == 'textDocument/publishDiagnostics' then
    log.info('Interceptor: publishDiagnostics transformed URI: %s', transformed.uri or 'nil')
    if transformed ~= params then
      log.info('Interceptor: publishDiagnostics transformation successful')
    else
      log.warn('Interceptor: publishDiagnostics transformation may have failed - no changes detected')
    end
  elseif transformed ~= params then
    log.debug('Interceptor: Transformed notification params: %s', vim.inspect(transformed))
  else
    log.debug('Interceptor: No transformation needed for notification %s', method)
  end

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

    -- Special logging for textDocument/didOpen to debug path issues
    if method == 'textDocument/didOpen' and params and params.textDocument then
      log.info('Interceptor: Processing textDocument/didOpen - Original URI: %s', params.textDocument.uri or 'nil')
    end

    -- Transform notification parameters (host -> container)
    local transformed_params = M.transform_request_params(method, params, 'to_container')

    -- Log transformation result for textDocument/didOpen
    if method == 'textDocument/didOpen' and transformed_params and transformed_params.textDocument then
      log.info('Interceptor: textDocument/didOpen transformed URI: %s', transformed_params.textDocument.uri or 'nil')
    end

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
        if err then
          log.error('Interceptor: Handler received error for %s: %s', method, vim.inspect(err))
        end

        if result then
          log.debug('Interceptor: Transforming incoming notification: %s', method)
          log.debug('Interceptor: Raw result data: %s', vim.inspect(result))

          -- Special handling for publishDiagnostics to ensure URI transformation
          if method == 'textDocument/publishDiagnostics' then
            log.info('Interceptor: === DIAGNOSTICS DEBUG START ===')
            log.info('Interceptor: Original result: %s', vim.inspect(result))
            log.info('Interceptor: Original URI: %s (type: %s)', result.uri or 'nil', type(result.uri))

            -- Validate URI format before transformation
            if not result.uri or result.uri == '' then
              log.error('Interceptor: publishDiagnostics has empty or missing URI, skipping')
              log.info('Interceptor: === DIAGNOSTICS DEBUG END (SKIPPED) ===')
              return -- Skip processing invalid diagnostics
            end

            -- Store original for comparison
            local original_uri = result.uri

            -- Ensure URI has proper file:// scheme
            if not result.uri:match('^file://') then
              log.warn('Interceptor: publishDiagnostics URI missing file:// scheme: %s', result.uri)
              -- Try to fix by adding file:// prefix if it looks like an absolute path
              if result.uri:match('^/') then
                result.uri = 'file://' .. result.uri
                log.info('Interceptor: Added file:// scheme to URI: %s', result.uri)
              else
                log.error('Interceptor: Cannot fix malformed URI: %s', result.uri)
                log.info('Interceptor: === DIAGNOSTICS DEBUG END (MALFORMED) ===')
                return -- Skip processing malformed URIs
              end
            end

            log.info('Interceptor: Before transform_notification_params - URI: %s', result.uri)
            result = M.transform_notification_params(method, result, 'to_host')
            log.info('Interceptor: After transform_notification_params - URI: %s', result.uri or 'nil')

            -- Final validation after transformation
            if not result.uri then
              log.error('Interceptor: URI became nil after transformation!')
              result.uri = original_uri
              log.info('Interceptor: Restored original URI: %s', result.uri)
            elseif result.uri == '' then
              log.error('Interceptor: URI became empty after transformation!')
              result.uri = original_uri
              log.info('Interceptor: Restored original URI: %s', result.uri)
            elseif not result.uri:match('^file://') then
              log.error('Interceptor: URI lost file:// scheme after transformation: %s', result.uri)
              if result.uri:match('^/') then
                result.uri = 'file://' .. result.uri
                log.info('Interceptor: Restored file:// scheme: %s', result.uri)
              else
                log.error('Interceptor: Cannot fix URI without absolute path')
                result.uri = original_uri
                log.info('Interceptor: Restored original URI: %s', result.uri)
              end
            end

            -- Validate that the URI was properly transformed to host path
            if result.uri and result.uri:match('^file://' .. vim.pesc(path_config.container_workspace)) then
              log.warn('Interceptor: Diagnostic URI was not properly transformed: %s', result.uri)
              -- Force transformation if needed
              result.uri = transform_uri(result.uri, 'to_host')
              log.info('Interceptor: Force-transformed diagnostic URI to: %s', result.uri)
            end

            log.info('Interceptor: Final URI: %s', result.uri)
            log.info('Interceptor: === DIAGNOSTICS DEBUG END ===')
          else
            result = M.transform_notification_params(method, result, 'to_host')
          end
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

  -- CRITICAL: Setup defensive diagnostic handler to catch URI scheme errors
  -- This prevents vim.uri.uri_to_fname crashes when URIs lack schemes
  M._setup_defensive_diagnostic_handler(client)

  log.info('Interceptor: Successfully set up interception for client %s', client.name or 'unknown')
  return true
end

-- Setup defensive diagnostic handler to prevent URI scheme crashes
-- @param client table: LSP client
function M._setup_defensive_diagnostic_handler(client)
  local client_name = client.name or 'unknown'
  log.debug('Interceptor: Setting up defensive diagnostic handler for %s', client_name)

  -- Get the current diagnostic handler
  local original_diagnostic_handler = vim.lsp.handlers['textDocument/publishDiagnostics']

  -- Create a defensive wrapper
  local defensive_handler = function(err, result, ctx, config)
    if err then
      log.debug('Interceptor: Diagnostic error: %s', vim.inspect(err))
      if original_diagnostic_handler then
        return original_diagnostic_handler(err, result, ctx, config)
      end
      return
    end

    if not result then
      log.debug('Interceptor: No diagnostic result')
      return
    end

    -- CRITICAL: Validate and fix URI before passing to original handler
    if not result.uri or result.uri == '' then
      log.error('Interceptor: Defensive handler caught empty URI in diagnostics from %s', client_name)
      -- Skip processing diagnostics with no URI
      return
    end

    -- Ensure URI has proper scheme
    if not result.uri:match('^[a-zA-Z][a-zA-Z0-9+.-]*:') then
      log.error('Interceptor: Defensive handler caught URI without scheme: %s', result.uri)

      -- Try to fix by adding file:// if it looks like an absolute path
      if result.uri:match('^/') then
        result.uri = 'file://' .. result.uri
        log.info('Interceptor: Defensive handler fixed URI: %s', result.uri)
      else
        log.error('Interceptor: Cannot fix relative path URI, skipping diagnostics: %s', result.uri)
        return
      end
    end

    -- Additional validation: ensure URI is not just a scheme
    if result.uri:match('^[a-zA-Z][a-zA-Z0-9+.-]*:$') then
      log.error('Interceptor: Defensive handler caught scheme-only URI: %s', result.uri)
      return
    end

    log.debug('Interceptor: Defensive handler validated URI: %s', result.uri)

    -- Call original handler with validated URI
    if original_diagnostic_handler then
      return original_diagnostic_handler(err, result, ctx, config)
    end
  end

  -- Replace the global diagnostic handler
  vim.lsp.handlers['textDocument/publishDiagnostics'] = defensive_handler
  log.info('Interceptor: Defensive diagnostic handler installed for %s', client_name)
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

-- Debug function to trace path transformations
-- @param uri string: URI to analyze
-- @return table: detailed transformation analysis
function M.debug_path_transformation(uri)
  local analysis = {
    original_uri = uri,
    is_file_uri = uri and uri:match('^file://') ~= nil,
    path_config = M.get_path_config(),
    transformations = {},
  }

  if not analysis.is_file_uri then
    analysis.error = 'Not a file URI'
    return analysis
  end

  local path = uri:gsub('^file://', '')
  analysis.original_path = path

  -- Test host-to-container transformation
  local to_container = transform_uri(uri, 'to_container')
  analysis.transformations.to_container = {
    result = to_container,
    changed = to_container ~= uri,
  }

  -- Test container-to-host transformation
  local to_host = transform_uri(uri, 'to_host')
  analysis.transformations.to_host = {
    result = to_host,
    changed = to_host ~= uri,
  }

  -- Analyze path patterns
  analysis.path_analysis = {
    matches_host_workspace = path_config.host_workspace
      and path:match('^' .. vim.pesc(path_config.host_workspace)) ~= nil,
    matches_container_workspace = path:match('^' .. vim.pesc(path_config.container_workspace)) ~= nil,
  }

  return analysis
end

-- Debug function to monitor diagnostics transformation
-- @param client table: LSP client to monitor
function M.debug_diagnostics_monitoring(client)
  if not client then
    log.error('Interceptor Debug: No client provided for diagnostics monitoring')
    return
  end

  local client_name = client.name or 'unknown'
  log.info('Interceptor Debug: Setting up diagnostics monitoring for client %s', client_name)

  -- Store original handler if it exists
  local original_handler = client.config.handlers and client.config.handlers['textDocument/publishDiagnostics']

  if not original_handler then
    original_handler = vim.lsp.handlers['textDocument/publishDiagnostics']
  end

  -- Wrap the handler with detailed diagnostics logging
  local debug_handler = function(err, result, ctx, config)
    log.info('Interceptor Debug: Diagnostics received for client %s', client_name)

    if err then
      log.error('Interceptor Debug: Diagnostics error: %s', vim.inspect(err))
    elseif result then
      local uri_analysis = M.debug_path_transformation(result.uri)
      log.info('Interceptor Debug: Diagnostics URI analysis: %s', vim.inspect(uri_analysis))

      if result.diagnostics and #result.diagnostics > 0 then
        log.info('Interceptor Debug: Received %d diagnostics for %s', #result.diagnostics, result.uri)
        for i, diagnostic in ipairs(result.diagnostics) do
          log.debug(
            'Interceptor Debug: Diagnostic %d: %s at line %d',
            i,
            diagnostic.message,
            diagnostic.range.start.line + 1
          )
        end
      else
        log.info('Interceptor Debug: No diagnostics in payload for %s', result.uri)
      end
    end

    -- Call original handler
    if original_handler then
      return original_handler(err, result, ctx, config)
    end
  end

  -- Update client handler
  if not client.config.handlers then
    client.config.handlers = {}
  end
  client.config.handlers['textDocument/publishDiagnostics'] = debug_handler

  log.info('Interceptor Debug: Diagnostics monitoring enabled for client %s', client_name)
end

return M
