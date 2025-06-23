-- lua/container/lsp/proxy/transform.lua
-- Path transformation engine for LSP proxy
-- Handles bidirectional path conversion between host and container

local M = {}
local log = require('container.utils.log')

-- Default path mappings
local DEFAULT_MAPPINGS = {
  host_root = '/Users', -- Will be auto-detected
  container_root = '/workspace',
}

-- LSP method-specific transformation rules
-- Defines which fields need path transformation for each LSP method
local TRANSFORM_RULES = {
  -- Initialization
  ['initialize'] = {
    request = {
      'rootUri',
      'workspaceFolders[].uri',
      'initializationOptions.rootPath',
    },
  },

  -- Document lifecycle
  ['textDocument/didOpen'] = {
    request = { 'textDocument.uri' },
  },
  ['textDocument/didChange'] = {
    request = { 'textDocument.uri' },
  },
  ['textDocument/didSave'] = {
    request = { 'textDocument.uri' },
  },
  ['textDocument/didClose'] = {
    request = { 'textDocument.uri' },
  },

  -- Document navigation
  ['textDocument/definition'] = {
    request = { 'textDocument.uri' },
    response = { 'uri', 'targetUri', '[].uri', '[].targetUri' },
  },
  ['textDocument/declaration'] = {
    request = { 'textDocument.uri' },
    response = { 'uri', 'targetUri', '[].uri', '[].targetUri' },
  },
  ['textDocument/implementation'] = {
    request = { 'textDocument.uri' },
    response = { 'uri', 'targetUri', '[].uri', '[].targetUri' },
  },
  ['textDocument/typeDefinition'] = {
    request = { 'textDocument.uri' },
    response = { 'uri', 'targetUri', '[].uri', '[].targetUri' },
  },
  ['textDocument/references'] = {
    request = { 'textDocument.uri' },
    response = { '[].uri' },
  },

  -- Document symbols
  ['textDocument/documentSymbol'] = {
    request = { 'textDocument.uri' },
    response = { '[].location.uri', '[].children[].location.uri' },
  },
  ['workspace/symbol'] = {
    response = { '[].location.uri' },
  },

  -- Code actions
  ['textDocument/codeAction'] = {
    request = { 'textDocument.uri' },
    response = { '[].edit.documentChanges[].textDocument.uri' },
  },

  -- Diagnostics
  ['textDocument/publishDiagnostics'] = {
    notification = { 'uri' },
  },

  -- Workspace operations
  ['workspace/didChangeWatchedFiles'] = {
    notification = { 'changes[].uri' },
  },
  ['workspace/didChangeWorkspaceFolders'] = {
    notification = {
      'event.added[].uri',
      'event.removed[].uri',
    },
  },

  -- File operations
  ['workspace/willCreateFiles'] = {
    request = { 'files[].uri' },
  },
  ['workspace/didCreateFiles'] = {
    notification = { 'files[].uri' },
  },
  ['workspace/willDeleteFiles'] = {
    request = { 'files[].uri' },
  },
  ['workspace/didDeleteFiles'] = {
    notification = { 'files[].uri' },
  },
  ['workspace/willRenameFiles'] = {
    request = { 'files[].oldUri', 'files[].newUri' },
  },
  ['workspace/didRenameFiles'] = {
    notification = { 'files[].oldUri', 'files[].newUri' },
  },

  -- Hover and completion
  ['textDocument/hover'] = {
    request = { 'textDocument.uri' },
  },
  ['textDocument/completion'] = {
    request = { 'textDocument.uri' },
  },
  ['textDocument/signatureHelp'] = {
    request = { 'textDocument.uri' },
  },

  -- Formatting
  ['textDocument/formatting'] = {
    request = { 'textDocument.uri' },
  },
  ['textDocument/rangeFormatting'] = {
    request = { 'textDocument.uri' },
  },
  ['textDocument/onTypeFormatting'] = {
    request = { 'textDocument.uri' },
  },

  -- Rename
  ['textDocument/rename'] = {
    request = { 'textDocument.uri' },
    response = { 'documentChanges[].textDocument.uri' },
  },
  ['textDocument/prepareRename'] = {
    request = { 'textDocument.uri' },
  },
}

-- Path transformation cache
local path_cache = {
  host_to_container = {},
  container_to_host = {},
  max_entries = 10000,
  hits = 0,
  misses = 0,
}

-- Initialize path transformer with workspace mappings
-- @param host_workspace string: host workspace root path
-- @param container_workspace string: container workspace root path
function M.setup(host_workspace, container_workspace)
  M.config = {
    host_root = host_workspace or DEFAULT_MAPPINGS.host_root,
    container_root = container_workspace or DEFAULT_MAPPINGS.container_root,
  }

  -- Clear cache when configuration changes
  M.clear_cache()

  log.debug('Transform: Initialized with mappings: %s → %s', M.config.host_root, M.config.container_root)
end

-- Transform a single path from host to container format
-- @param path string: host path
-- @return string: container path
function M.host_to_container_path(path)
  if not path or type(path) ~= 'string' then
    return path
  end

  -- Check cache first
  local cached = path_cache.host_to_container[path]
  if cached then
    path_cache.hits = path_cache.hits + 1
    return cached
  end

  path_cache.misses = path_cache.misses + 1

  -- Ensure configuration is available
  if not M.config then
    log.warn('Transform: No configuration available, using defaults')
    M.setup()
  end

  local transformed = path

  -- Handle file:// URIs
  if path:match('^file://') then
    local file_path = path:gsub('^file://', '')
    if file_path:match('^' .. vim.pesc(M.config.host_root)) then
      local relative_path = file_path:gsub('^' .. vim.pesc(M.config.host_root), '')
      transformed = 'file://' .. M.config.container_root .. relative_path
    end
  else
    -- Handle regular file paths
    if path:match('^' .. vim.pesc(M.config.host_root)) then
      local relative_path = path:gsub('^' .. vim.pesc(M.config.host_root), '')
      transformed = M.config.container_root .. relative_path
    end
  end

  -- Cache the result
  if #vim.tbl_keys(path_cache.host_to_container) < path_cache.max_entries then
    path_cache.host_to_container[path] = transformed
  end

  if transformed ~= path then
    log.debug('Transform: %s → %s', path, transformed)
  end

  return transformed
end

-- Transform a single path from container to host format
-- @param path string: container path
-- @return string: host path
function M.container_to_host_path(path)
  if not path or type(path) ~= 'string' then
    return path
  end

  -- Check cache first
  local cached = path_cache.container_to_host[path]
  if cached then
    path_cache.hits = path_cache.hits + 1
    return cached
  end

  path_cache.misses = path_cache.misses + 1

  -- Ensure configuration is available
  if not M.config then
    log.warn('Transform: No configuration available, using defaults')
    M.setup()
  end

  local transformed = path

  -- Handle file:// URIs
  if path:match('^file://') then
    local file_path = path:gsub('^file://', '')
    if file_path:match('^' .. vim.pesc(M.config.container_root)) then
      local relative_path = file_path:gsub('^' .. vim.pesc(M.config.container_root), '')
      transformed = 'file://' .. M.config.host_root .. relative_path
    end
  else
    -- Handle regular file paths
    if path:match('^' .. vim.pesc(M.config.container_root)) then
      local relative_path = path:gsub('^' .. vim.pesc(M.config.container_root), '')
      transformed = M.config.host_root .. relative_path
    end
  end

  -- Cache the result
  if #vim.tbl_keys(path_cache.container_to_host) < path_cache.max_entries then
    path_cache.container_to_host[path] = transformed
  end

  if transformed ~= path then
    log.debug('Transform: %s → %s', path, transformed)
  end

  return transformed
end

-- Transform paths in a JSON object based on field patterns
-- @param obj any: object to transform
-- @param field_patterns table: array of field patterns to transform
-- @param transform_func function: transformation function to apply
-- @return any: transformed object
local function transform_object_fields(obj, field_patterns, transform_func)
  if not obj or not field_patterns then
    return obj
  end

  -- Deep clone to avoid modifying original
  local transformed = vim.deepcopy(obj)

  for _, pattern in ipairs(field_patterns) do
    M._apply_field_pattern(transformed, pattern, transform_func)
  end

  return transformed
end

-- Apply transformation to a specific field pattern
-- @param obj table: target object
-- @param pattern string: field pattern (e.g., "textDocument.uri", "[].location.uri")
-- @param transform_func function: transformation function
function M._apply_field_pattern(obj, pattern, transform_func)
  if not obj or type(obj) ~= 'table' then
    return
  end

  -- Handle array patterns [].field
  if pattern:match('^%[%]%.') then
    local sub_pattern = pattern:gsub('^%[%]%.', '')
    if type(obj) == 'table' then
      for i, item in ipairs(obj) do
        M._apply_field_pattern(item, sub_pattern, transform_func)
      end
    end
    return
  end

  -- Handle nested field patterns field.subfield
  local field, rest = pattern:match('^([^%.%[]+)%.(.+)')
  if field and rest then
    if obj[field] then
      M._apply_field_pattern(obj[field], rest, transform_func)
    end
    return
  end

  -- Handle array field patterns field[].subfield
  local array_field, sub_pattern = pattern:match('^([^%.%[]+)%[%]%.(.+)')
  if array_field and sub_pattern then
    if obj[array_field] and type(obj[array_field]) == 'table' then
      for i, item in ipairs(obj[array_field]) do
        M._apply_field_pattern(item, sub_pattern, transform_func)
      end
    end
    return
  end

  -- Handle simple field pattern
  if obj[pattern] then
    local transformed_value = transform_func(obj[pattern])
    if transformed_value ~= obj[pattern] then
      obj[pattern] = transformed_value
      log.debug('Transform: Applied to field %s', pattern)
    end
  end
end

-- Transform JSON-RPC message paths (host → container)
-- @param message table: JSON-RPC message object
-- @return table: message with transformed paths
function M.transform_request_to_container(message)
  if not message or type(message) ~= 'table' then
    return message
  end

  local method = message.method
  if not method then
    return message
  end

  local rules = TRANSFORM_RULES[method]
  if not rules then
    log.debug('Transform: No transformation rules for method: %s', method)
    return message
  end

  local transformed = vim.deepcopy(message)

  -- Transform request parameters
  if rules.request and transformed.params then
    transformed.params = transform_object_fields(transformed.params, rules.request, M.host_to_container_path)
  end

  -- Transform notification parameters
  if rules.notification and transformed.params then
    transformed.params = transform_object_fields(transformed.params, rules.notification, M.host_to_container_path)
  end

  return transformed
end

-- Transform JSON-RPC message paths (container → host)
-- @param message table: JSON-RPC message object
-- @param original_method string|nil: original request method for responses
-- @return table: message with transformed paths
function M.transform_response_to_host(message, original_method)
  if not message or type(message) ~= 'table' then
    return message
  end

  local method = message.method or original_method
  if not method then
    return message
  end

  local rules = TRANSFORM_RULES[method]
  if not rules then
    return message
  end

  local transformed = vim.deepcopy(message)

  -- Transform response result
  if rules.response and transformed.result then
    transformed.result = transform_object_fields(transformed.result, rules.response, M.container_to_host_path)
  end

  -- Transform notification parameters
  if rules.notification and transformed.params then
    transformed.params = transform_object_fields(transformed.params, rules.notification, M.container_to_host_path)
  end

  return transformed
end

-- Clear path transformation cache
function M.clear_cache()
  path_cache.host_to_container = {}
  path_cache.container_to_host = {}
  path_cache.hits = 0
  path_cache.misses = 0
  log.debug('Transform: Cache cleared')
end

-- Get cache statistics
-- @return table: cache statistics
function M.get_cache_stats()
  return {
    hits = path_cache.hits,
    misses = path_cache.misses,
    hit_rate = path_cache.hits / math.max(1, path_cache.hits + path_cache.misses),
    entries = {
      host_to_container = #vim.tbl_keys(path_cache.host_to_container),
      container_to_host = #vim.tbl_keys(path_cache.container_to_host),
    },
  }
end

-- Validate transformation configuration
-- @return boolean, string|nil: is_valid, error_message
function M.validate_config()
  if not M.config then
    return false, 'No transformation configuration found'
  end

  if not M.config.host_root or not M.config.container_root then
    return false, 'Missing host_root or container_root configuration'
  end

  if type(M.config.host_root) ~= 'string' or type(M.config.container_root) ~= 'string' then
    return false, 'Configuration paths must be strings'
  end

  return true, nil
end

-- Add custom transformation rule for a specific LSP method
-- @param method string: LSP method name
-- @param rule table: transformation rule specification
function M.add_transformation_rule(method, rule)
  if not method or not rule then
    log.error('Transform: Invalid rule parameters')
    return
  end

  TRANSFORM_RULES[method] = rule
  log.debug('Transform: Added custom rule for method: %s', method)
end

-- Remove transformation rule for a specific LSP method
-- @param method string: LSP method name
function M.remove_transformation_rule(method)
  if TRANSFORM_RULES[method] then
    TRANSFORM_RULES[method] = nil
    log.debug('Transform: Removed rule for method: %s', method)
  end
end

-- Get all available transformation rules
-- @return table: copy of transformation rules
function M.get_transformation_rules()
  return vim.deepcopy(TRANSFORM_RULES)
end

-- Test path transformation with sample data
-- @param test_cases table: array of test cases
-- @return table: test results
function M.run_transformation_tests(test_cases)
  local results = {}

  for i, test_case in ipairs(test_cases) do
    local input = test_case.input
    local expected = test_case.expected
    local direction = test_case.direction or 'host_to_container'

    local actual
    if direction == 'host_to_container' then
      actual = M.host_to_container_path(input)
    else
      actual = M.container_to_host_path(input)
    end

    table.insert(results, {
      index = i,
      input = input,
      expected = expected,
      actual = actual,
      passed = actual == expected,
      direction = direction,
    })
  end

  return results
end

return M
