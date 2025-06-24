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

  -- Create proxy command
  local proxy_command = M._create_proxy_command(container_id, server_name)

  -- Return LSP client configuration
  return {
    name = 'container_' .. server_name,
    cmd = proxy_command,

    -- LSP capabilities
    capabilities = vim.lsp.protocol.make_client_capabilities(),

    -- Workspace configuration
    root_dir = (function()
      if config and config.host_workspace and type(config.host_workspace) == 'string' then
        return config.host_workspace
      end
      local cwd = vim.fn.getcwd()
      return type(cwd) == 'string' and cwd or '/tmp'
    end)(),
    workspace_folders = {
      {
        uri = (function()
          local workspace
          if config and config.host_workspace and type(config.host_workspace) == 'string' then
            workspace = config.host_workspace
          else
            local cwd = vim.fn.getcwd()
            if type(cwd) == 'string' then
              workspace = cwd
            else
              log.error('Proxy: vim.fn.getcwd() returned %s instead of string', type(cwd))
              workspace = '/tmp'
            end
          end

          if type(workspace) ~= 'string' then
            log.error('Proxy: workspace is %s instead of string: %s', type(workspace), vim.inspect(workspace))
            workspace = '/tmp'
          end

          return 'file://' .. workspace
        end)(),
        name = 'workspace',
      },
    },

    -- Initialization options
    init_options = config and config.init_options or {},
    settings = config and config.settings or {},

    -- Path transformation handlers
    handlers = M._create_path_transformation_handlers(container_id, server_name),

    -- Before init callback - transform paths in initialize request
    before_init = function(initialize_params, lsp_config)
      log.info('Proxy System: before_init called for %s/%s', container_id, server_name)

      local transform = require('container.lsp.proxy.transform')

      -- Transform workspace paths from host to container
      if initialize_params.rootUri then
        local original_uri = initialize_params.rootUri
        -- Extract path from file:// URI and transform
        local path = original_uri:gsub('^file://', '')
        local transformed_path = transform.host_to_container_path(path)
        initialize_params.rootUri = 'file://' .. transformed_path
        log.info('Proxy: Transformed rootUri: %s -> %s', original_uri, initialize_params.rootUri)
      end

      if initialize_params.rootPath then
        local original_path = initialize_params.rootPath
        initialize_params.rootPath = transform.host_to_container_path(initialize_params.rootPath)
        log.info('Proxy: Transformed rootPath: %s -> %s', original_path, initialize_params.rootPath)
      end

      if initialize_params.workspaceFolders then
        for _, folder in ipairs(initialize_params.workspaceFolders) do
          local original_uri = folder.uri
          -- Extract path from file:// URI and transform
          local path = original_uri:gsub('^file://', '')
          local transformed_path = transform.host_to_container_path(path)
          folder.uri = 'file://' .. transformed_path
          log.info('Proxy: Transformed workspace folder: %s -> %s', original_uri, folder.uri)
        end
      end
    end,

    -- Event handlers
    on_init = function(client, initialize_result)
      log.info('Proxy System: LSP client initialized for %s/%s', container_id, server_name)

      -- Set up request path transformation
      M._setup_request_transformation(client, container_id, server_name)

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

-- Private: Setup request path transformation for LSP client
-- @param client table: LSP client object
-- @param container_id string: container ID
-- @param server_name string: server name
function M._setup_request_transformation(client, container_id, server_name)
  local transform = require('container.lsp.proxy.transform')

  -- Wrap the client's request method to transform paths
  local original_request = client.request
  client.request = function(method, params, handler, bufnr)
    log.info('Proxy: Client request called with method: %s', method)

    -- Transform paths from host to container
    if transform.should_transform_method(method) then
      params = transform.transform_request(method, params, function(path)
        return transform.host_to_container_path(path)
      end)
    end

    -- Wrap the handler to transform responses
    local original_handler = handler
    if handler and transform.should_transform_method(method) then
      handler = function(err, result, ctx)
        if result then
          log.info('Proxy: Got response for %s, transforming paths', method)
          result = transform.transform_response(method, result, function(path)
            return transform.container_to_host_path(path)
          end)
        end
        return original_handler(err, result, ctx)
      end
    end

    return original_request(method, params, handler, bufnr)
  end

  -- Wrap the client's notify method to transform paths in notifications
  local original_notify = client.notify
  client.notify = function(method, params)
    log.info('Proxy: Client notify called with method: %s, params: %s', method, vim.inspect(params))

    -- Transform paths from host to container
    if transform.should_transform_method(method) then
      params = transform.transform_request(method, params, function(path)
        return transform.host_to_container_path(path)
      end)
    end

    return original_notify(method, params)
  end

  log.info('Proxy: Set up request path transformation for %s/%s', container_id, server_name)
end

-- Private: Create path transformation handlers for LSP client
-- @param container_id string: container ID
-- @param server_name string: server name
-- @return table: LSP handlers with path transformation
function M._create_path_transformation_handlers(container_id, server_name)
  local transform = require('container.lsp.proxy.transform')
  local handlers = {}

  -- List of methods that need response path transformation (server -> client)
  local response_transform_methods = {
    'textDocument/definition',
    'textDocument/references',
    'textDocument/implementation',
    'textDocument/typeDefinition',
    'textDocument/declaration',
    'workspace/symbol',
    'callHierarchy/incomingCalls',
    'callHierarchy/outgoingCalls',
    'textDocument/documentLink',
    'textDocument/publishDiagnostics', -- Add diagnostics notification
  }

  for _, method in ipairs(response_transform_methods) do
    handlers[method] = function(err, result, context, config)
      if method == 'textDocument/publishDiagnostics' then
        -- Handle publishDiagnostics notification (params structure is different)
        log.info('Proxy: publishDiagnostics handler called with err=%s, result=%s', tostring(err), vim.inspect(result))

        if result then
          -- Validate URI exists
          if not result.uri or result.uri == '' then
            log.error('Proxy: publishDiagnostics received with empty URI! Full result: %s', vim.inspect(result))
            -- Try to recover by checking context
            if context and context.params and context.params.uri then
              result.uri = context.params.uri
              log.info('Proxy: Recovered URI from context: %s', result.uri)
            else
              log.error('Proxy: Cannot recover URI, skipping diagnostics')
              return
            end
          end

          log.info('Proxy: Original diagnostics result: %s', vim.inspect(result))

          -- Transform paths from container to host
          result = transform.transform_response(method, result, function(path)
            local transformed = transform.container_to_host_path(path)
            log.debug('Proxy: Path transform %s -> %s', path, transformed)
            return transformed
          end)

          log.info('Proxy: Transformed diagnostics result: %s', vim.inspect(result))
        else
          log.warn('Proxy: publishDiagnostics called with nil result')
        end
      else
        -- Handle normal responses
        if result then
          -- Transform paths from container to host
          result = transform.transform_response(method, result, function(path)
            return transform.container_to_host_path(path)
          end)
          log.debug('Proxy: Transformed response for %s', method)
        end
      end

      -- Call the default handler
      return vim.lsp.handlers[method](err, result, context, config)
    end
  end

  log.debug('Proxy: Created %d path transformation handlers', #response_transform_methods)
  return handlers
end

-- Private: Create proxy command for LSP client
-- @param container_id string: container ID
-- @param server_name string: server name
-- @return table: command array for LSP client
function M._create_proxy_command(container_id, server_name)
  -- Create a Lua proxy script that will handle communication
  -- The script will:
  -- 1. Read JSON-RPC from stdin
  -- 2. Transform paths host->container
  -- 3. Forward to real LSP server in container
  -- 4. Transform responses container->host
  -- 5. Send back to stdout

  -- Create a temporary Lua script for this proxy
  local proxy_script_path = '/tmp/container_lsp_proxy_' .. container_id .. '_' .. server_name .. '.lua'

  -- Generate the proxy script content
  local script_content = string.format(
    [[
-- Auto-generated LSP proxy script for %s in container %s
local container_id = %q
local server_name = %q

-- Load required modules
local log_ok, log = pcall(require, 'container.utils.log')
if not log_ok then
  -- Fallback logging
  log = { debug = function() end, info = function() end, error = function() end }
end

local proxy_ok, proxy = pcall(require, 'container.lsp.proxy.init')
if not proxy_ok then
  log.error('Proxy Script: Failed to load proxy module')
  os.exit(1)
end

-- Get the proxy instance
local proxy_instance = proxy.get_proxy(container_id, server_name)
if not proxy_instance then
  log.error('Proxy Script: No proxy instance found for %%s/%%s', container_id, server_name)
  os.exit(1)
end

log.info('Proxy Script: Starting proxy communication for %%s/%%s', container_id, server_name)

-- Main communication loop
local jsonrpc = require('container.lsp.proxy.jsonrpc')
local buffer = ""

while true do
  -- Read input
  local input = io.stdin:read("*l")
  if not input then
    log.info('Proxy Script: EOF reached, exiting')
    break
  end

  buffer = buffer .. input .. "\n"

  -- Try to parse complete JSON-RPC messages
  local message, remaining = jsonrpc.parse_message(buffer)
  while message do
    log.debug('Proxy Script: Processing message: %%s', message.method or 'response')

    -- Process message through proxy
    proxy_instance:process_client_message(message)

    buffer = remaining or ""
    message, remaining = jsonrpc.parse_message(buffer)
  end
end

log.info('Proxy Script: Proxy communication ended')
]],
    server_name,
    container_id,
    container_id,
    server_name
  )

  -- Write the script to temporary file
  local script_file = io.open(proxy_script_path, 'w')
  if not script_file then
    log.error('Proxy: Failed to create proxy script at %s', proxy_script_path)
    return { 'echo', 'Failed to create proxy script' }
  end

  script_file:write(script_content)
  script_file:close()

  -- Make the script executable and return command to run it
  local proxy_cmd = { 'lua', proxy_script_path }

  log.info('Proxy: Generated proxy script command: %s', table.concat(proxy_cmd, ' '))
  return proxy_cmd
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
