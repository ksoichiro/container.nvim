-- Strategy A: Symlink-based path resolution
-- This module is simplified for Strategy A where paths are unified via symlinks
-- No path transformation is needed as host and container use identical paths

local M = {}
local log = require('container.utils.log')

-- Setup autocmd for transforming container LSP communication (disabled for Strategy A)
function M.setup()
  -- Strategy A: No autocmd setup needed
  -- Path transformation is not required with symlinks
  log.debug('LSP Transform: Strategy A - no transformation autocmds needed')
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

  -- Check client name
  if client.name and client.name:find('container_') then
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

-- Setup path transformation for a container LSP client (Strategy A: no-op)
function M.setup_path_transformation(client)
  log.info('LSP Transform: setup_path_transformation called for client %s', client.name or 'unknown')

  -- Strategy A (symlinks): Skip path transformation entirely
  -- Paths are already unified between host and container via symlinks
  log.info('LSP Transform: Strategy A active - no path transformation needed for %s', client.name or 'unknown')
end

-- Check if a method requires path transformation (Strategy A: always false)
function M.should_transform_method(method)
  -- Strategy A (symlinks): No transformation needed
  return false
end

-- Transform outgoing parameters (Strategy A: no-op)
function M.transform_outgoing_params(params)
  -- Strategy A: Return params unchanged
  return params
end

-- Transform incoming parameters (Strategy A: no-op)
function M.transform_incoming_params(params)
  -- Strategy A: Return params unchanged
  return params
end

-- Wrap response handler (Strategy A: no-op)
function M.wrap_response_handler(handler)
  -- Strategy A: Return handler unchanged
  return handler
end

-- Setup incoming handlers (Strategy A: no-op)
function M.setup_incoming_handlers(client)
  -- Strategy A: No handler setup needed
  log.debug('LSP Transform: Strategy A - no incoming handlers setup needed for %s', client.name or 'unknown')
end

return M
