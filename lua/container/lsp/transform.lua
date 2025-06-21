local M = {}
local log = require('container.utils.log')

-- Setup autocmd for transforming container LSP communication
function M.setup()
  -- Create autocmd group for LSP transformation
  local group = vim.api.nvim_create_augroup('ContainerLspTransform', { clear = true })

  -- Setup path transformation for container-managed LSP clients
  vim.api.nvim_create_autocmd('LspAttach', {
    group = group,
    callback = function(args)
      local client = vim.lsp.get_client_by_id(args.data.client_id)

      -- Check if this is a container-managed LSP client
      if M.is_container_lsp_client(client) then
        log.info('LSP Transform: Setting up path transformation for %s (client ID: %s)', client.name, client.id)
        M.setup_path_transformation(client)
      end
    end,
  })

  log.debug('LSP Transform: Autocmd system initialized')
end

-- Check if an LSP client is managed by container.nvim
function M.is_container_lsp_client(client)
  if not client or not client.config then
    return false
  end

  -- Check for container_managed flag
  if client.config.container_managed == true then
    return true
  end

  -- Fallback: check if command contains docker
  if client.config.cmd then
    local cmd_str = table.concat(client.config.cmd, ' ')
    if cmd_str:find('docker') or cmd_str:find('container') then
      return true
    end
  end

  return false
end

-- Setup path transformation for a container LSP client
function M.setup_path_transformation(client)
  if not client.config.container_id then
    log.warn('LSP Transform: No container_id found for client %s', client.name)
    return
  end

  local path_utils = require('container.lsp.path')
  local container_id = client.config.container_id

  log.debug('LSP Transform: Setting up transformation for container %s', container_id)

  -- Override client.notify for outgoing notifications
  local original_notify = client.notify
  client.notify = function(self, method, params)
    if M.should_transform_method(method) then
      log.debug('LSP Transform: Transforming outgoing %s', method)
      params = M.transform_outgoing_params(params)
    end
    return original_notify(self, method, params)
  end

  -- Override client.request for outgoing requests
  local original_request = client.request
  client.request = function(self, method, params, handler, bufnr)
    if M.should_transform_method(method) then
      log.debug('LSP Transform: Transforming outgoing %s', method)
      params = M.transform_outgoing_params(params)
    end

    -- Wrap response handler to transform incoming data
    local wrapped_handler = M.wrap_response_handler(handler)
    return original_request(self, method, params, wrapped_handler, bufnr)
  end

  -- Setup handlers for incoming notifications and responses
  M.setup_incoming_handlers(client)

  log.info('LSP Transform: Path transformation setup complete for %s', client.name)
end

-- Check if a method requires path transformation
function M.should_transform_method(method)
  local transform_methods = {
    -- Text document methods
    '^textDocument/',
    -- Workspace methods
    '^workspace/',
    -- Initialization
    '^initialize$',
    -- File events
    '^workspace/didChangeWatchedFiles$',
  }

  for _, pattern in ipairs(transform_methods) do
    if method:match(pattern) then
      return true
    end
  end

  return false
end

-- Transform outgoing parameters (local paths -> container paths)
function M.transform_outgoing_params(params)
  if not params then
    return params
  end

  local path_utils = require('container.lsp.path')
  local transformed = vim.deepcopy(params)

  -- Transform textDocument.uri
  if transformed.textDocument and transformed.textDocument.uri then
    local fname = vim.uri_to_fname(transformed.textDocument.uri)
    local container_path = path_utils.to_container_path(fname)
    if container_path then
      transformed.textDocument.uri = vim.uri_from_fname(container_path)
      log.debug('LSP Transform: %s -> %s', fname, container_path)
    end
  end

  -- Transform rootUri
  if transformed.rootUri then
    transformed.rootUri = vim.uri_from_fname('/workspace')
  end

  -- Transform workspaceFolders
  if transformed.workspaceFolders then
    transformed.workspaceFolders = {
      {
        uri = vim.uri_from_fname('/workspace'),
        name = 'container-workspace',
      },
    }
  end

  -- Transform file URIs in changes (didChangeWatchedFiles)
  if transformed.changes then
    for i, change in ipairs(transformed.changes) do
      if change.uri then
        local fname = vim.uri_to_fname(change.uri)
        local container_path = path_utils.to_container_path(fname)
        if container_path then
          transformed.changes[i].uri = vim.uri_from_fname(container_path)
        end
      end
    end
  end

  return transformed
end

-- Transform incoming results (container paths -> local paths)
function M.transform_incoming_result(result)
  if not result then
    return result
  end

  local path_utils = require('container.lsp.path')
  local transformed = vim.deepcopy(result)

  -- Transform single location
  if transformed.uri then
    local fname = vim.uri_to_fname(transformed.uri)
    if fname and vim.startswith(fname, '/workspace') then
      local local_path = path_utils.to_local_path(fname)
      if local_path then
        transformed.uri = vim.uri_from_fname(local_path)
        log.debug('LSP Transform: %s -> %s', fname, local_path)
      end
    end
  end

  -- Transform array of locations
  if vim.tbl_islist(transformed) then
    for i, item in ipairs(transformed) do
      if item.uri then
        local fname = vim.uri_to_fname(item.uri)
        if fname and vim.startswith(fname, '/workspace') then
          local local_path = path_utils.to_local_path(fname)
          if local_path then
            transformed[i].uri = vim.uri_from_fname(local_path)
          end
        end
      end
      -- Handle nested location structures
      if item.location and item.location.uri then
        local fname = vim.uri_to_fname(item.location.uri)
        if fname and vim.startswith(fname, '/workspace') then
          local local_path = path_utils.to_local_path(fname)
          if local_path then
            transformed[i].location.uri = vim.uri_from_fname(local_path)
          end
        end
      end
    end
  end

  -- Transform diagnostics
  if transformed.diagnostics then
    for i, diagnostic in ipairs(transformed.diagnostics) do
      if diagnostic.relatedInformation then
        for j, info in ipairs(diagnostic.relatedInformation) do
          if info.location and info.location.uri then
            local fname = vim.uri_to_fname(info.location.uri)
            if fname and vim.startswith(fname, '/workspace') then
              local local_path = path_utils.to_local_path(fname)
              if local_path then
                transformed.diagnostics[i].relatedInformation[j].location.uri = vim.uri_from_fname(local_path)
              end
            end
          end
        end
      end
    end
  end

  return transformed
end

-- Wrap response handler to transform incoming data
function M.wrap_response_handler(original_handler)
  if not original_handler then
    return nil
  end

  return function(err, result, ctx, config)
    if not err and result then
      result = M.transform_incoming_result(result)
    end
    return original_handler(err, result, ctx, config)
  end
end

-- Setup handlers for incoming notifications and responses
function M.setup_incoming_handlers(client)
  -- Store original handlers
  local original_handlers = client.handlers or {}
  client.handlers = client.handlers or {}

  -- Common handlers that need path transformation
  local handlers_to_transform = {
    'textDocument/publishDiagnostics',
    'textDocument/definition',
    'textDocument/references',
    'textDocument/implementation',
    'textDocument/typeDefinition',
    'textDocument/declaration',
    'textDocument/documentSymbol',
    'workspace/symbol',
  }

  for _, method in ipairs(handlers_to_transform) do
    -- Get the default handler or existing custom handler
    local default_handler = vim.lsp.handlers[method]
    local existing_handler = original_handlers[method] or default_handler

    if existing_handler then
      client.handlers[method] = function(err, result, ctx, config)
        if not err and result then
          result = M.transform_incoming_result(result)
        end
        return existing_handler(err, result, ctx, config)
      end
      log.debug('LSP Transform: Set up incoming handler for %s', method)
    end
  end
end

return M
