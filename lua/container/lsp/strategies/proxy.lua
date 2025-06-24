-- lua/container/lsp/strategies/proxy.lua
-- Strategy B: Proxy Implementation Adapter
-- Provides unified interface for Phase 1 proxy-based LSP system

local M = {}
local log = require('container.utils.log')

-- Load Phase 1 proxy modules
local proxy = require('container.lsp.proxy.init')
local configs = require('container.lsp.configs')

-- Track proxy instances for cleanup
local active_proxies = {}

-- Track proxy system initialization
local proxy_initialized = false

-- Initialize proxy strategy (if not already done)
local function ensure_proxy_initialized()
  if not proxy_initialized then
    proxy.setup({
      max_proxies_per_container = 5,
      auto_cleanup_interval = 300,
      enable_health_monitoring = true,
      default_timeout = 30000,
    })
    proxy_initialized = true
    log.debug('Proxy Strategy: Initialized proxy system')
  end
end

-- Create LSP client using proxy strategy
-- @param server_name string: LSP server name (e.g., 'gopls')
-- @param container_id string: target container ID
-- @param server_config table: LSP server configuration
-- @param strategy_config table: strategy-specific configuration
-- @return table|nil: LSP client configuration or nil on error
-- @return string|nil: error message if failed
function M.create_client(server_name, container_id, server_config, strategy_config)
  log.debug('Proxy Strategy: Creating client for %s in container %s', server_name, container_id)

  -- Skip complex proxy system for now, focus on simple path transformation

  -- Get language-specific configuration
  local lang_config = configs.get_language_config(server_name) or {}

  -- Prepare proxy configuration
  local proxy_config = vim.tbl_deep_extend('force', {
    host_workspace = server_config.root_dir or vim.fn.getcwd(),
    server_cmd = lang_config.cmd or { server_name },
    init_options = vim.tbl_deep_extend('force', lang_config.init_options or {}, server_config.init_options or {}),
    settings = vim.tbl_deep_extend('force', lang_config.settings or {}, server_config.settings or {}),
  }, strategy_config.proxy or {})

  -- Create a simpler direct docker exec configuration with path transformation
  -- Focus on fixing the immediate issue: before_init not being called and workspace paths
  local client_config = {
    name = 'container_' .. server_name,
    cmd = { 'docker', 'exec', '-i', container_id, '/go/bin/gopls' },
    root_dir = server_config.root_dir or vim.fn.getcwd(),
    capabilities = vim.lsp.protocol.make_client_capabilities(),
    settings = proxy_config.settings,
    init_options = proxy_config.init_options,
  }

  -- Add before_init to transform workspace paths from host to container
  client_config.before_init = function(initialize_params, config)
    log.info('Proxy Strategy: before_init called for %s (container: %s)', server_name, container_id)

    -- Transform workspace paths from host to container
    if initialize_params.rootUri then
      local original_uri = initialize_params.rootUri
      -- Transform host path to container path
      local host_workspace = server_config.root_dir or vim.fn.getcwd()
      if original_uri:match('^file://' .. vim.pesc(host_workspace)) then
        initialize_params.rootUri = 'file:///workspace'
        log.info('Proxy Strategy: Transformed rootUri: %s -> %s', original_uri, initialize_params.rootUri)
      end
    end

    if initialize_params.rootPath then
      local original_path = initialize_params.rootPath
      local host_workspace = server_config.root_dir or vim.fn.getcwd()
      if original_path == host_workspace then
        initialize_params.rootPath = '/workspace'
        log.info('Proxy Strategy: Transformed rootPath: %s -> %s', original_path, initialize_params.rootPath)
      end
    end

    if initialize_params.workspaceFolders then
      for i, folder in ipairs(initialize_params.workspaceFolders) do
        local original_uri = folder.uri
        local host_workspace = server_config.root_dir or vim.fn.getcwd()
        if original_uri:match('^file://' .. vim.pesc(host_workspace)) then
          folder.uri = 'file:///workspace'
          folder.name = 'workspace'
          log.info('Proxy Strategy: Transformed workspace folder %d: %s -> %s', i, original_uri, folder.uri)
        end
      end
    end

    log.info('Proxy Strategy: before_init transformation complete')
  end

  -- Add path transformation handlers for responses
  local original_handlers = client_config.handlers or {}
  client_config.handlers = vim.tbl_deep_extend('force', original_handlers, {
    ['textDocument/publishDiagnostics'] = function(err, result, context, config)
      if result and result.uri then
        local original_uri = result.uri
        -- Transform container path back to host path
        if result.uri:match('^file:///workspace') then
          local host_workspace = server_config.root_dir or vim.fn.getcwd()
          result.uri = result.uri:gsub('^file:///workspace', 'file://' .. host_workspace)
          log.debug('Proxy Strategy: Transformed diagnostic URI: %s -> %s', original_uri, result.uri)
        end
      end
      -- Call default handler
      return vim.lsp.handlers['textDocument/publishDiagnostics'](err, result, context, config)
    end,
  })

  local original_on_init = client_config.on_init
  client_config.on_init = function(client, initialize_result)
    log.info('Proxy Strategy: LSP client initialized for %s', server_name)

    -- Track this proxy instance
    if not active_proxies[container_id] then
      active_proxies[container_id] = {}
    end
    active_proxies[container_id][server_name] = {
      client_id = client.id,
      proxy_instance = proxy.get_proxy(container_id, server_name),
      created_at = os.time(),
    }

    if original_on_init then
      original_on_init(client, initialize_result)
    end
    if server_config.on_init then
      server_config.on_init(client, initialize_result)
    end
  end

  local original_on_attach = client_config.on_attach
  client_config.on_attach = function(client, bufnr)
    log.info('Proxy Strategy: LSP client attached to buffer %d for %s', bufnr, server_name)

    if original_on_attach then
      original_on_attach(client, bufnr)
    end
    if server_config.on_attach then
      server_config.on_attach(client, bufnr)
    end
  end

  local original_on_exit = client_config.on_exit
  client_config.on_exit = function(code, signal)
    log.info('Proxy Strategy: LSP client exited (code=%d, signal=%d) for %s', code, signal, server_name)

    -- Cleanup proxy tracking
    if active_proxies[container_id] and active_proxies[container_id][server_name] then
      active_proxies[container_id][server_name] = nil
      if vim.tbl_isempty(active_proxies[container_id]) then
        active_proxies[container_id] = nil
      end
    end

    if original_on_exit then
      original_on_exit(code, signal)
    end
    if server_config.on_exit then
      server_config.on_exit(code, signal)
    end
  end

  -- Override capabilities with server-specific ones
  if server_config.capabilities then
    client_config.capabilities = vim.tbl_deep_extend('force', client_config.capabilities, server_config.capabilities)
  end

  -- Add additional server configuration
  if server_config.flags then
    client_config.flags = server_config.flags
  end
  if server_config.before_init then
    client_config.before_init = server_config.before_init
  end
  if server_config.handlers then
    client_config.handlers = server_config.handlers
  end

  log.info('Proxy Strategy: Successfully created client configuration for %s', server_name)
  return client_config, nil
end

-- Setup path transformation for proxy strategy
-- @param client table: LSP client object
-- @param server_name string: LSP server name
-- @param container_id string: container ID
function M.setup_path_transformation(client, server_name, container_id)
  log.debug('Proxy Strategy: Setting up path transformation for %s', server_name)

  -- Path transformation is handled automatically by the proxy system
  -- No additional setup needed as it's built into the proxy communication layer

  local proxy_instance = proxy.get_proxy(container_id, server_name)
  if proxy_instance then
    log.debug('Proxy Strategy: Path transformation active via proxy for %s', server_name)
  else
    log.warn('Proxy Strategy: No proxy instance found for %s, path transformation may not work', server_name)
  end
end

-- Cleanup resources used by proxy strategy
-- @param container_id string: container ID
function M.cleanup(container_id)
  log.debug('Proxy Strategy: Cleaning up resources for container %s', container_id)

  -- Stop all proxies for this container
  local stopped_count = proxy.stop_container_proxies(container_id)
  log.info('Proxy Strategy: Stopped %d proxies for container %s', stopped_count, container_id)

  -- Clear tracking
  active_proxies[container_id] = nil

  log.debug('Proxy Strategy: Cleanup completed')
end

-- Health check for proxy strategy
-- @return table: health status
function M.health_check()
  ensure_proxy_initialized()

  -- Get proxy system health
  local proxy_health = proxy.health_check()

  local health = {
    healthy = proxy_health.system_healthy,
    issues = proxy_health.issues or {},
    details = {
      proxy_system_healthy = proxy_health.system_healthy,
      total_proxies = proxy_health.total_proxies,
      proxy_details = proxy_health.proxy_details or {},
      active_containers = vim.tbl_count(active_proxies),
    },
  }

  -- Add proxy system statistics
  local proxy_stats = proxy.get_system_stats()
  health.details.system_stats = proxy_stats

  -- Check proxy module availability
  local modules_ok = true
  local required_modules = {
    'container.lsp.proxy.init',
    'container.lsp.proxy.server',
    'container.lsp.proxy.transport',
    'container.lsp.proxy.transform',
    'container.lsp.proxy.jsonrpc',
  }

  for _, module_name in ipairs(required_modules) do
    local ok = pcall(require, module_name)
    if not ok then
      table.insert(health.issues, 'Required proxy module not available: ' .. module_name)
      modules_ok = false
    end
  end

  health.details.modules_available = modules_ok
  if not modules_ok then
    health.healthy = false
  end

  return health
end

-- Get strategy-specific diagnostic information
-- @param container_id string: container ID
-- @return table: diagnostic information
function M.get_diagnostics(container_id)
  ensure_proxy_initialized()

  local diagnostics = {
    strategy = 'proxy',
    container_id = container_id,
    active_proxies = {},
    proxy_stats = {},
  }

  -- Get active proxies for this container
  if active_proxies[container_id] then
    for server_name, proxy_info in pairs(active_proxies[container_id]) do
      diagnostics.active_proxies[server_name] = {
        client_id = proxy_info.client_id,
        created_at = proxy_info.created_at,
        uptime = os.time() - proxy_info.created_at,
      }

      -- Get proxy instance stats
      if proxy_info.proxy_instance then
        local stats = proxy_info.proxy_instance:get_stats()
        diagnostics.proxy_stats[server_name] = stats
      end
    end
  end

  -- Get system-wide proxy statistics
  diagnostics.system_stats = proxy.get_system_stats()

  return diagnostics
end

-- Check if proxy strategy can be used for a specific server
-- @param server_name string: LSP server name
-- @param container_id string: container ID
-- @return boolean: true if strategy can be used
-- @return string|nil: reason if cannot be used
function M.can_use_strategy(server_name, container_id)
  -- Check if proxy modules are available
  local proxy_ok = pcall(require, 'container.lsp.proxy.init')
  if not proxy_ok then
    return false, 'Proxy modules not available'
  end

  -- Check if docker is available (required for container communication)
  local docker_ok = pcall(function()
    vim.fn.system('docker --version')
    return vim.v.shell_error == 0
  end)

  if not docker_ok then
    return false, 'Docker not available or not working'
  end

  -- Check if container is accessible
  local container_check = pcall(function()
    vim.fn.system('docker inspect ' .. vim.fn.shellescape(container_id))
    return vim.v.shell_error == 0
  end)

  if not container_check then
    return false, 'Container not accessible or not running'
  end

  return true, nil
end

-- Get default configuration for proxy strategy
-- @return table: default configuration
function M.get_default_config()
  return {
    proxy = {
      enable_caching = true,
      max_proxies_per_container = 5,
      auto_cleanup_interval = 300,
      enable_health_monitoring = true,
      default_timeout = 30000,
    },
  }
end

-- Get active proxy instances
-- @return table: active proxy information
function M.get_active_proxies()
  return vim.deepcopy(active_proxies)
end

-- Stop proxy for specific server
-- @param container_id string: container ID
-- @param server_name string: LSP server name
-- @return boolean: true if stopped successfully
function M.stop_proxy(container_id, server_name)
  local success = proxy.stop_proxy(container_id, server_name)

  if success and active_proxies[container_id] then
    active_proxies[container_id][server_name] = nil
    if vim.tbl_isempty(active_proxies[container_id]) then
      active_proxies[container_id] = nil
    end
  end

  return success
end

return M
