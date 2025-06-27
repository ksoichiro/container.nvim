-- lua/container/lsp/strategies/intercept.lua
-- Strategy C: Host-side Interception Implementation
-- Creates LSP clients with complete message interception for path transformation

local M = {}
local log = require('container.utils.log')

-- Load required modules
local interceptor = require('container.lsp.interceptor')
local configs = require('container.lsp.configs')

-- Create LSP client using interception strategy
-- @param server_name string: LSP server name (e.g., 'gopls')
-- @param container_id string: target container ID
-- @param server_config table: LSP server configuration
-- @param strategy_config table: strategy-specific configuration
-- @return table|nil: LSP client configuration or nil on error
-- @return string|nil: error message if failed
function M.create_client(server_name, container_id, server_config, strategy_config)
  log.info('Intercept Strategy: Creating client for %s in container %s', server_name, container_id)
  log.debug('Intercept Strategy: server_config = %s', vim.inspect(server_config))
  log.debug('Intercept Strategy: strategy_config = %s', vim.inspect(strategy_config))

  if not server_name or not container_id then
    local error_msg = 'Invalid parameters: server_name and container_id are required'
    log.error('Intercept Strategy: %s', error_msg)
    return nil, error_msg
  end

  -- Get language-specific configuration
  local lang_config = configs.get_language_config(server_name) or {}

  -- Determine server command
  local server_cmd = lang_config.cmd and lang_config.cmd[1] or server_name

  -- Prepare workspace configuration
  local host_workspace = server_config.root_dir or vim.fn.getcwd()
  if type(host_workspace) == 'function' then
    -- Call the function to get the actual root directory
    local current_file = vim.fn.expand('%:p')
    host_workspace = host_workspace(current_file) or vim.fn.getcwd()
  end

  log.info('Intercept Strategy: Using host workspace: %s', host_workspace)

  -- Create base LSP client configuration
  local client_config = {
    name = 'container_' .. server_name,
    cmd = { 'docker', 'exec', '-i', container_id, server_cmd },
    root_dir = host_workspace,
    capabilities = vim.lsp.protocol.make_client_capabilities(),

    -- Workspace configuration (will be transformed during interception)
    workspace_folders = {
      {
        uri = 'file://' .. host_workspace,
        name = 'workspace',
      },
    },

    -- Language-specific configuration
    settings = vim.tbl_deep_extend('force', lang_config.settings or {}, server_config.settings or {}),
    init_options = vim.tbl_deep_extend('force', lang_config.init_options or {}, server_config.init_options or {}),

    -- Custom initialization
    before_init = function(initialize_params, config)
      log.info('Intercept Strategy: before_init called for %s', server_name)

      -- The interceptor will handle path transformation, but we can do basic setup here
      log.debug('Intercept Strategy: Initial rootUri: %s', initialize_params.rootUri or 'nil')
      log.debug('Intercept Strategy: Initial workspaceFolders: %s', vim.inspect(initialize_params.workspaceFolders))

      -- Call original before_init if provided
      if strategy_config.before_init then
        strategy_config.before_init(initialize_params, config)
      end
    end,

    -- Setup interception after client initialization
    on_init = function(client, initialize_result)
      log.info('Intercept Strategy: on_init called for %s (client ID: %s)', server_name, client.id)

      -- Setup message interception
      local success = interceptor.setup_client_interception(client, container_id)
      if not success then
        log.error('Intercept Strategy: Failed to setup interception for %s', server_name)
      else
        log.info('Intercept Strategy: Successfully setup interception for %s', server_name)
      end

      -- Call original on_init if provided
      if strategy_config.on_init then
        strategy_config.on_init(client, initialize_result)
      end
    end,

    on_attach = function(client, bufnr)
      log.info('Intercept Strategy: on_attach called for %s (buffer: %d)', server_name, bufnr)

      -- Call original on_attach if provided
      if strategy_config.on_attach then
        strategy_config.on_attach(client, bufnr)
      end
    end,

    on_exit = function(code, signal)
      log.info('Intercept Strategy: Client exited for %s (code: %d, signal: %d)', server_name, code, signal)

      -- Call original on_exit if provided
      if strategy_config.on_exit then
        strategy_config.on_exit(code, signal)
      end
    end,

    -- Error handler
    on_error = function(err)
      log.error('Intercept Strategy: Client error for %s: %s', server_name, vim.inspect(err))

      -- Call original on_error if provided
      if strategy_config.on_error then
        strategy_config.on_error(err)
      end
    end,
  }

  -- Add any additional configuration from strategy_config
  if strategy_config.client_config then
    client_config = vim.tbl_deep_extend('force', client_config, strategy_config.client_config)
  end

  log.info(
    'Intercept Strategy: Created client config for %s with command: %s',
    server_name,
    table.concat(client_config.cmd, ' ')
  )

  return client_config, nil
end

-- Check if interception strategy is available
-- @param server_name string: LSP server name
-- @param container_id string: target container ID
-- @return boolean: true if strategy can be used
-- @return string|nil: error message if not available
function M.is_available(server_name, container_id)
  -- Check if container is running
  local docker = require('container.docker.init')
  local status = docker.get_container_status(container_id)
  local is_running = status == 'running'

  if not is_running then
    return false, 'Container is not running: ' .. container_id
  end

  -- Check if server exists in container
  local cmd_check = { 'docker', 'exec', container_id, 'which', server_name }
  local result = vim.fn.system(cmd_check)
  local exit_code = vim.v.shell_error

  if exit_code ~= 0 then
    return false, string.format('LSP server "%s" not found in container %s', server_name, container_id)
  end

  log.debug('Intercept Strategy: %s is available in container %s', server_name, container_id)
  return true, nil
end

-- Get strategy information
-- @return table: strategy metadata
function M.get_info()
  return {
    name = 'intercept',
    description = 'Host-side message interception with path transformation',
    advantages = {
      'Complete control over all LSP messages',
      'Solves textDocument/didOpen timing issues',
      'Environment independent (host-side only)',
      'Compatible with all LSP servers',
    },
    limitations = {
      'Slight performance overhead for message transformation',
      'Requires Neovim LSP client override',
    },
    requirements = {
      'Running container with LSP server',
      'Docker exec access to container',
    },
  }
end

-- Cleanup strategy resources
-- @param client table: LSP client
function M.cleanup(client)
  if client then
    log.info('Intercept Strategy: Cleaning up client %s', client.name or 'unknown')
    -- No specific cleanup needed for interception strategy
    -- The interceptor modifications are tied to the client lifecycle
  end
end

-- Debug function to test interception setup
-- @param container_id string: target container ID
-- @param server_name string: LSP server name
-- @return table: debug information
function M.debug_interception(container_id, server_name)
  local debug_info = {
    strategy = 'intercept',
    container_id = container_id,
    server_name = server_name,
    path_config = interceptor.get_path_config(),
    transform_rules = interceptor.get_transform_rules(),
    availability = nil,
  }

  local available, error_msg = M.is_available(server_name, container_id)
  debug_info.availability = {
    available = available,
    error = error_msg,
  }

  return debug_info
end

return M
