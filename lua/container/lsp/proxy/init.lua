-- lua/container/lsp/proxy/init.lua
-- LSP Proxy System - Main Interface
-- Provides high-level API for Strategy B LSP proxy functionality

local M = {}
local log = require('container.utils.log')

-- Module dependencies
local server = require('container.lsp.proxy.server')
local transport = require('container.lsp.proxy.transport')
local jsonrpc = require('container.lsp.proxy.jsonrpc')
local transform = require('container.lsp.proxy.transform')

-- Global proxy registry
local active_proxies = {} -- { [container_id] = { [server_name] = proxy_instance } }

-- Proxy system configuration
local system_config = {
  max_proxies_per_container = 5,
  auto_cleanup_interval = 300, -- seconds
  enable_health_monitoring = true,
  default_timeout = 30000, -- ms
}

-- Initialize the proxy system
-- @param config table|nil: system configuration overrides
function M.setup(config)
  system_config = vim.tbl_deep_extend('force', system_config, config or {})

  -- Set up periodic cleanup
  if system_config.auto_cleanup_interval > 0 then
    M._setup_periodic_cleanup()
  end

  -- Set up health monitoring
  if system_config.enable_health_monitoring then
    M._setup_health_monitoring()
  end

  log.info('Proxy System: Initialized with config: %s', vim.inspect(system_config))
end

-- Create and start a new LSP proxy
-- @param container_id string: target container ID
-- @param server_name string: LSP server name (e.g., 'gopls', 'pylsp')
-- @param config table: proxy configuration
-- @return table|nil: proxy instance or nil on error
function M.create_proxy(container_id, server_name, config)
  if not container_id or not server_name then
    log.error('Proxy System: Invalid parameters for create_proxy')
    return nil
  end

  -- Check if proxy already exists
  if M.get_proxy(container_id, server_name) then
    log.warn('Proxy System: Proxy already exists for %s/%s', container_id, server_name)
    return nil
  end

  -- Check container limits
  local container_proxies = active_proxies[container_id] or {}
  if vim.tbl_count(container_proxies) >= system_config.max_proxies_per_container then
    log.error('Proxy System: Maximum proxies reached for container %s', container_id)
    return nil
  end

  -- Determine host workspace
  local host_workspace = config.host_workspace or vim.fn.getcwd()

  -- Create proxy server
  local factory = server.create_factory()
  local proxy

  if server_name == 'gopls' then
    proxy = factory.create_gopls_proxy(container_id, host_workspace)
  elseif server_name == 'pylsp' then
    proxy = factory.create_pylsp_proxy(container_id, host_workspace)
  elseif server_name == 'tsserver' then
    proxy = factory.create_tsserver_proxy(container_id, host_workspace)
  else
    -- Generic proxy
    local server_cmd = config.server_cmd or { server_name }
    proxy = factory.create_generic_proxy(container_id, host_workspace, server_cmd)
  end

  if not proxy then
    log.error('Proxy System: Failed to create proxy for %s', server_name)
    return nil
  end

  -- Set up proxy event handlers
  proxy:set_handlers({
    on_error = function(error_msg)
      log.error('Proxy System: Proxy error for %s/%s: %s', container_id, server_name, error_msg)
      M._handle_proxy_error(container_id, server_name, error_msg)
    end,
    on_close = function()
      log.info('Proxy System: Proxy closed for %s/%s', container_id, server_name)
      M._cleanup_proxy(container_id, server_name)
    end,
  })

  -- Start the proxy
  local success = proxy:start(container_id)
  if not success then
    log.error('Proxy System: Failed to start proxy for %s/%s', container_id, server_name)
    return nil
  end

  -- Register the proxy
  if not active_proxies[container_id] then
    active_proxies[container_id] = {}
  end
  active_proxies[container_id][server_name] = proxy

  log.info('Proxy System: Created and started proxy for %s/%s', container_id, server_name)
  return proxy
end

-- Get an existing proxy
-- @param container_id string: container ID
-- @param server_name string: server name
-- @return table|nil: proxy instance or nil if not found
function M.get_proxy(container_id, server_name)
  local container_proxies = active_proxies[container_id]
  if not container_proxies then
    return nil
  end
  return container_proxies[server_name]
end

-- Stop and remove a proxy
-- @param container_id string: container ID
-- @param server_name string: server name
-- @return boolean: success
function M.stop_proxy(container_id, server_name)
  local proxy = M.get_proxy(container_id, server_name)
  if not proxy then
    log.warn('Proxy System: Proxy not found for %s/%s', container_id, server_name)
    return false
  end

  proxy:stop()
  M._cleanup_proxy(container_id, server_name)

  log.info('Proxy System: Stopped proxy for %s/%s', container_id, server_name)
  return true
end

-- Stop all proxies for a container
-- @param container_id string: container ID
-- @return number: number of proxies stopped
function M.stop_container_proxies(container_id)
  local container_proxies = active_proxies[container_id]
  if not container_proxies then
    return 0
  end

  local stopped_count = 0
  for server_name, proxy in pairs(container_proxies) do
    proxy:stop()
    stopped_count = stopped_count + 1
  end

  active_proxies[container_id] = nil

  log.info('Proxy System: Stopped %d proxies for container %s', stopped_count, container_id)
  return stopped_count
end

-- Stop all active proxies
-- @return number: total number of proxies stopped
function M.stop_all_proxies()
  local total_stopped = 0

  for container_id, container_proxies in pairs(active_proxies) do
    for server_name, proxy in pairs(container_proxies) do
      proxy:stop()
      total_stopped = total_stopped + 1
    end
  end

  active_proxies = {}

  log.info('Proxy System: Stopped all %d active proxies', total_stopped)
  return total_stopped
end

-- List all active proxies
-- @return table: { [container_id] = { [server_name] = proxy_stats } }
function M.list_active_proxies()
  local proxy_list = {}

  for container_id, container_proxies in pairs(active_proxies) do
    proxy_list[container_id] = {}
    for server_name, proxy in pairs(container_proxies) do
      proxy_list[container_id][server_name] = proxy:get_stats()
    end
  end

  return proxy_list
end

-- Get system-wide statistics
-- @return table: comprehensive system statistics
function M.get_system_stats()
  local stats = {
    total_containers = vim.tbl_count(active_proxies),
    total_proxies = 0,
    proxy_states = {},
    system_health = true,
    issues = {},
  }

  -- Count proxies and collect states
  for container_id, container_proxies in pairs(active_proxies) do
    for server_name, proxy in pairs(container_proxies) do
      stats.total_proxies = stats.total_proxies + 1

      local proxy_stats = proxy:get_stats()
      local state = proxy_stats.state
      stats.proxy_states[state] = (stats.proxy_states[state] or 0) + 1

      -- Check health
      local health = proxy:health_check()
      if not health.healthy then
        stats.system_health = false
        for _, issue in ipairs(health.issues) do
          table.insert(stats.issues, string.format('%s/%s: %s', container_id, server_name, issue))
        end
      end
    end
  end

  return stats
end

-- Create LSP client command for proxy connection
-- @param container_id string: container ID
-- @param server_name string: server name
-- @param config table|nil: additional configuration
-- @return table|nil: vim.lsp.start_client command configuration
function M.create_lsp_client_config(container_id, server_name, config)
  local proxy = M.get_proxy(container_id, server_name)
  if not proxy then
    -- Create proxy if it doesn't exist
    proxy = M.create_proxy(container_id, server_name, config or {})
    if not proxy then
      return nil
    end
  end

  -- Create stdio transport that connects to proxy
  local client_transport = transport.create_stdio_transport(
    io.stdin, -- Will be replaced by vim.lsp.start_client
    io.stdout -- Will be replaced by vim.lsp.start_client
  )

  -- Connect client transport to proxy
  proxy:set_client_transport(client_transport)

  -- Return LSP client configuration
  return {
    name = 'container_' .. server_name,
    cmd = function()
      -- This function will be called by vim.lsp.start_client
      -- Return a custom command that routes through our proxy
      return M._create_proxy_command(container_id, server_name)
    end,

    -- LSP capabilities
    capabilities = vim.lsp.protocol.make_client_capabilities(),

    -- Workspace configuration
    root_dir = config and config.host_workspace or vim.fn.getcwd(),
    workspace_folders = {
      {
        uri = 'file://' .. (config and config.host_workspace or vim.fn.getcwd()),
        name = 'workspace',
      },
    },

    -- Initialization options
    init_options = config and config.init_options or {},
    settings = config and config.settings or {},

    -- Event handlers
    on_init = function(client, initialize_result)
      log.info('Proxy System: LSP client initialized for %s/%s', container_id, server_name)
      if config and config.on_init then
        config.on_init(client, initialize_result)
      end
    end,

    on_attach = function(client, bufnr)
      log.info('Proxy System: LSP client attached to buffer %d for %s/%s', bufnr, container_id, server_name)
      if config and config.on_attach then
        config.on_attach(client, bufnr)
      end
    end,

    on_exit = function(code, signal)
      log.info(
        'Proxy System: LSP client exited (code=%d, signal=%d) for %s/%s',
        code,
        signal,
        container_id,
        server_name
      )
      M._cleanup_proxy(container_id, server_name)
    end,
  }
end

-- Private: Create proxy command for vim.lsp.start_client
-- @param container_id string: container ID
-- @param server_name string: server name
-- @return table: command array for LSP client
function M._create_proxy_command(container_id, server_name)
  -- Return a command that will route through our proxy system
  -- This is a placeholder - the actual implementation would use
  -- a custom stdio handler that communicates with our proxy
  return { 'container-lsp-proxy', container_id, server_name }
end

-- Private: Handle proxy errors
-- @param container_id string: container ID
-- @param server_name string: server name
-- @param error_msg string: error message
function M._handle_proxy_error(container_id, server_name, error_msg)
  -- Log error
  log.error('Proxy System: Proxy error for %s/%s: %s', container_id, server_name, error_msg)

  -- Attempt restart if configured
  local proxy = M.get_proxy(container_id, server_name)
  if proxy and proxy.config.auto_restart then
    log.info('Proxy System: Attempting to restart proxy for %s/%s', container_id, server_name)
    vim.defer_fn(function()
      M.stop_proxy(container_id, server_name)
      M.create_proxy(container_id, server_name, proxy.config)
    end, 5000)
  end
end

-- Private: Clean up proxy registration
-- @param container_id string: container ID
-- @param server_name string: server name
function M._cleanup_proxy(container_id, server_name)
  local container_proxies = active_proxies[container_id]
  if container_proxies then
    container_proxies[server_name] = nil

    -- Remove container entry if no proxies remain
    if vim.tbl_isempty(container_proxies) then
      active_proxies[container_id] = nil
    end
  end
end

-- Private: Set up periodic cleanup
function M._setup_periodic_cleanup()
  local function cleanup_task()
    -- Clean up stale requests in all proxies
    for container_id, container_proxies in pairs(active_proxies) do
      for server_name, proxy in pairs(container_proxies) do
        proxy:cleanup_stale_requests()
      end
    end

    -- Schedule next cleanup
    vim.defer_fn(cleanup_task, system_config.auto_cleanup_interval * 1000)
  end

  -- Start cleanup task
  vim.defer_fn(cleanup_task, system_config.auto_cleanup_interval * 1000)
  log.debug('Proxy System: Periodic cleanup scheduled every %d seconds', system_config.auto_cleanup_interval)
end

-- Private: Set up health monitoring
function M._setup_health_monitoring()
  local function health_check_task()
    local stats = M.get_system_stats()

    if not stats.system_health then
      log.warn('Proxy System: Health issues detected: %s', table.concat(stats.issues, ', '))
    end

    -- Log statistics periodically
    log.debug(
      'Proxy System: Stats - Containers: %d, Proxies: %d, Health: %s',
      stats.total_containers,
      stats.total_proxies,
      stats.system_health and 'OK' or 'ISSUES'
    )

    -- Schedule next health check
    vim.defer_fn(health_check_task, 60 * 1000) -- Every minute
  end

  -- Start health monitoring
  vim.defer_fn(health_check_task, 60 * 1000)
  log.debug('Proxy System: Health monitoring enabled')
end

-- Health check command for debugging
-- @return table: detailed health report
function M.health_check()
  local health = {
    system_healthy = true,
    total_proxies = 0,
    issues = {},
    proxy_details = {},
  }

  for container_id, container_proxies in pairs(active_proxies) do
    for server_name, proxy in pairs(container_proxies) do
      health.total_proxies = health.total_proxies + 1

      local proxy_health = proxy:health_check()
      health.proxy_details[container_id .. '/' .. server_name] = proxy_health

      if not proxy_health.healthy then
        health.system_healthy = false
        for _, issue in ipairs(proxy_health.issues) do
          table.insert(health.issues, string.format('%s/%s: %s', container_id, server_name, issue))
        end
      end
    end
  end

  return health
end

-- Export modules for advanced usage
M.modules = {
  server = server,
  transport = transport,
  jsonrpc = jsonrpc,
  transform = transform,
}

return M
