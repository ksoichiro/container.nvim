-- lua/container/lsp/strategies/symlink.lua
-- Strategy A: Symlink Implementation Adapter
-- Provides unified interface for existing symlink-based LSP system

local M = {}
local log = require('container.utils.log')

-- Load existing modules for Strategy A
local forwarding = require('container.lsp.forwarding')
local transform = require('container.lsp.transform')
local configs = require('container.lsp.configs')
local symlink = require('container.symlink')

-- Create LSP client using symlink strategy
-- @param server_name string: LSP server name (e.g., 'gopls')
-- @param container_id string: target container ID
-- @param server_config table: LSP server configuration
-- @param strategy_config table: strategy-specific configuration
-- @return table|nil: LSP client configuration or nil on error
-- @return string|nil: error message if failed
function M.create_client(server_name, container_id, server_config, strategy_config)
  log.debug('Symlink Strategy: Creating client for %s in container %s', server_name, container_id)

  -- Setup symlinks for path unification
  local symlink_success, symlink_err = pcall(function()
    symlink.setup_lsp_symlinks(container_id)
  end)

  if not symlink_success then
    log.error('Symlink Strategy: Failed to setup symlinks: %s', symlink_err)
    return nil, 'Failed to setup symlinks: ' .. tostring(symlink_err)
  end

  -- Get command configuration using existing forwarding system
  local cmd, cmd_err = forwarding.get_client_cmd(server_name, server_config, container_id)
  if not cmd then
    log.error('Symlink Strategy: Failed to get client command: %s', cmd_err or 'unknown error')
    return nil, 'Failed to get client command: ' .. tostring(cmd_err)
  end

  -- Get language-specific configuration
  local lang_config = configs.get_language_config(server_name) or {}

  -- Build LSP client configuration
  local client_config = {
    name = 'container_' .. server_name,
    cmd = cmd,

    -- Workspace configuration
    root_dir = server_config.root_dir or vim.fn.getcwd(),
    workspace_folders = server_config.workspace_folders,

    -- Server capabilities and settings
    capabilities = server_config.capabilities or vim.lsp.protocol.make_client_capabilities(),
    settings = vim.tbl_deep_extend('force', lang_config.settings or {}, server_config.settings or {}),
    init_options = vim.tbl_deep_extend('force', lang_config.init_options or {}, server_config.init_options or {}),

    -- Event handlers
    on_init = function(client, initialize_result)
      log.info('Symlink Strategy: LSP client initialized for %s', server_name)
      if server_config.on_init then
        server_config.on_init(client, initialize_result)
      end
    end,

    on_attach = function(client, bufnr)
      log.info('Symlink Strategy: LSP client attached to buffer %d for %s', bufnr, server_name)

      -- Setup path transformation (Strategy A: minimal transformation)
      M.setup_path_transformation(client, server_name, container_id)

      if server_config.on_attach then
        server_config.on_attach(client, bufnr)
      end
    end,

    on_exit = function(code, signal)
      log.info('Symlink Strategy: LSP client exited (code=%d, signal=%d) for %s', code, signal, server_name)

      -- Cleanup symlinks if configured
      if strategy_config.symlink and strategy_config.symlink.cleanup_on_exit then
        pcall(function()
          symlink.cleanup_lsp_symlinks(container_id)
        end)
      end

      if server_config.on_exit then
        server_config.on_exit(code, signal)
      end
    end,

    -- Additional configuration
    flags = server_config.flags or {},
    before_init = server_config.before_init,
    handlers = server_config.handlers,
  }

  log.info('Symlink Strategy: Successfully created client configuration for %s', server_name)
  return client_config, nil
end

-- Setup path transformation for symlink strategy
-- @param client table: LSP client object
-- @param server_name string: LSP server name
-- @param container_id string: container ID
function M.setup_path_transformation(client, server_name, container_id)
  log.debug('Symlink Strategy: Setting up path transformation for %s', server_name)

  -- Strategy A uses minimal path transformation since symlinks unify paths
  -- The existing transform.setup_path_transformation is mostly no-op for Strategy A
  transform.setup_path_transformation(client, server_name, container_id)

  log.debug('Symlink Strategy: Path transformation setup completed')
end

-- Cleanup resources used by symlink strategy
-- @param container_id string: container ID
function M.cleanup(container_id)
  log.debug('Symlink Strategy: Cleaning up resources for container %s', container_id)

  pcall(function()
    symlink.cleanup_lsp_symlinks(container_id)
  end)

  log.debug('Symlink Strategy: Cleanup completed')
end

-- Health check for symlink strategy
-- @return table: health status
function M.health_check()
  local health = {
    healthy = true,
    issues = {},
    details = {
      symlink_support = false,
      forwarding_available = false,
      transform_available = false,
    },
  }

  -- Check symlink module availability
  local symlink_ok = pcall(function()
    return symlink.check_symlink_support
  end)
  health.details.symlink_support = symlink_ok
  if not symlink_ok then
    table.insert(health.issues, 'Symlink module not properly loaded')
    health.healthy = false
  end

  -- Check forwarding module availability
  local forwarding_ok = pcall(function()
    return forwarding.get_client_cmd
  end)
  health.details.forwarding_available = forwarding_ok
  if not forwarding_ok then
    table.insert(health.issues, 'Forwarding module not properly loaded')
    health.healthy = false
  end

  -- Check transform module availability
  local transform_ok = pcall(function()
    return transform.setup_path_transformation
  end)
  health.details.transform_available = transform_ok
  if not transform_ok then
    table.insert(health.issues, 'Transform module not properly loaded')
    health.healthy = false
  end

  -- Check if docker is available (required for container communication)
  local docker_ok = pcall(function()
    vim.fn.system('docker --version')
    return vim.v.shell_error == 0
  end)
  health.details.docker_available = docker_ok
  if not docker_ok then
    table.insert(health.issues, 'Docker not available or not working')
    health.healthy = false
  end

  return health
end

-- Get strategy-specific diagnostic information
-- @param container_id string: container ID
-- @return table: diagnostic information
function M.get_diagnostics(container_id)
  local diagnostics = {
    strategy = 'symlink',
    container_id = container_id,
    symlinks = {},
    forwarding_status = 'unknown',
  }

  -- Check symlink status
  pcall(function()
    diagnostics.symlinks = symlink.get_symlink_status(container_id) or {}
  end)

  -- Check forwarding status
  pcall(function()
    diagnostics.forwarding_status = forwarding.check_container_connectivity(container_id) and 'connected'
      or 'disconnected'
  end)

  return diagnostics
end

-- Check if symlink strategy can be used for a specific server
-- @param server_name string: LSP server name
-- @param container_id string: container ID
-- @return boolean: true if strategy can be used
-- @return string|nil: reason if cannot be used
function M.can_use_strategy(server_name, container_id)
  -- Check if symlinks are supported
  local symlink_ok, symlink_err = pcall(function()
    return symlink.check_symlink_support()
  end)

  if not symlink_ok then
    return false, 'Symlink support not available: ' .. tostring(symlink_err)
  end

  -- Check if container is accessible
  local container_ok = pcall(function()
    return forwarding.check_container_connectivity(container_id)
  end)

  if not container_ok then
    return false, 'Container not accessible'
  end

  return true, nil
end

-- Get default configuration for symlink strategy
-- @return table: default configuration
function M.get_default_config()
  return {
    create_workspace_symlinks = true,
    cleanup_on_exit = true,
    symlink_timeout = 10000, -- 10 seconds
    verify_symlinks = true,
  }
end

return M
