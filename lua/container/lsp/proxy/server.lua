-- lua/container/lsp/proxy/server.lua
-- LSP Proxy Server implementation
-- Orchestrates bidirectional communication between Neovim and containerized LSP servers

local M = {}
local log = require('container.utils.log')

-- Proxy server state
M.PROXY_STATE = {
  STOPPED = 'stopped',
  STARTING = 'starting',
  RUNNING = 'running',
  STOPPING = 'stopping',
  ERROR = 'error',
}

-- Default configuration
local DEFAULT_CONFIG = {
  -- Basic settings
  server_cmd = { 'gopls', 'serve' },
  server_args = {},

  -- Path settings
  host_workspace = nil, -- Auto-detected
  container_workspace = '/workspace',

  -- Communication settings
  transport_type = 'stdio', -- 'stdio' | 'tcp'
  tcp_port = 9999,

  -- Performance settings
  message_buffer_size = 1000,
  path_cache_size = 10000,
  transform_timeout_ms = 100,

  -- Debug settings
  debug_level = 1, -- 0=none, 1=basic, 2=verbose
  log_file = '/tmp/lsp_proxy.log',
  trace_messages = false,
}

-- Create a new LSP proxy server
-- @param config table: proxy configuration
-- @return table: proxy server object
function M.create_proxy_server(config)
  local server = {
    config = vim.tbl_deep_extend('force', DEFAULT_CONFIG, config or {}),
    state = M.PROXY_STATE.STOPPED,

    -- Transport connections
    client_transport = nil, -- Neovim → Proxy
    server_transport = nil, -- Proxy → LSP Server

    -- Message processing
    message_queue = {},
    pending_requests = {}, -- Track request/response correlation
    request_id_counter = 0,

    -- Path transformation
    transformer = nil,

    -- Statistics
    stats = {
      messages_processed = 0,
      requests_sent = 0,
      responses_received = 0,
      errors_count = 0,
      start_time = nil,
    },

    -- Event handlers
    on_message = nil,
    on_error = nil,
    on_close = nil,
  }

  -- Set up methods
  setmetatable(server, { __index = M })

  log.debug('Proxy: Created proxy server with config: %s', vim.inspect(server.config))
  return server
end

-- Start the proxy server
-- @param container_id string: target container ID
-- @return boolean: success
function M:start(container_id)
  if self.state ~= M.PROXY_STATE.STOPPED then
    log.error('Proxy: Cannot start, current state: %s', self.state)
    return false
  end

  self.state = M.PROXY_STATE.STARTING
  self.stats.start_time = os.time()

  log.info('Proxy: Starting LSP proxy server for container: %s', container_id)

  -- Initialize path transformer
  local transform = require('container.lsp.proxy.transform')
  transform.setup(self.config.host_workspace, self.config.container_workspace)
  self.transformer = transform

  -- Create server transport (to LSP server in container)
  local transport = require('container.lsp.proxy.transport')
  self.server_transport = transport.create_docker_exec_transport(container_id, self.config.server_cmd)

  if not self.server_transport then
    log.error('Proxy: Failed to create server transport')
    self.state = M.PROXY_STATE.ERROR
    return false
  end

  -- Set up server transport handlers
  self.server_transport:set_message_handler(function(message)
    self:_handle_server_message(message)
  end)

  self.server_transport:set_error_handler(function(error_msg)
    self:_handle_transport_error('server', error_msg)
  end)

  self.server_transport:set_close_handler(function()
    self:_handle_transport_close('server')
  end)

  -- Create client transport (from Neovim)
  -- This will be set up when Neovim connects via vim.lsp.start_client

  self.state = M.PROXY_STATE.RUNNING
  log.info('Proxy: LSP proxy server started successfully')

  return true
end

-- Stop the proxy server
function M:stop()
  if self.state == M.PROXY_STATE.STOPPED then
    return
  end

  log.info('Proxy: Stopping LSP proxy server')
  self.state = M.PROXY_STATE.STOPPING

  -- Close transports
  if self.client_transport then
    self.client_transport:close()
    self.client_transport = nil
  end

  if self.server_transport then
    self.server_transport:close()
    self.server_transport = nil
  end

  -- Clear state
  self.message_queue = {}
  self.pending_requests = {}

  self.state = M.PROXY_STATE.STOPPED
  log.info('Proxy: LSP proxy server stopped')
end

-- Process message from Neovim client (host → container)
-- @param message table: JSON-RPC message from Neovim
function M:process_client_message(message)
  if self.state ~= M.PROXY_STATE.RUNNING then
    log.warn('Proxy: Ignoring client message, proxy not running')
    return
  end

  self.stats.messages_processed = self.stats.messages_processed + 1

  log.debug('Proxy: Processing client message: %s', message.method or 'response')

  -- Transform paths (host → container)
  local transformed_message = self.transformer.transform_request_to_container(message)

  -- Track requests for response correlation
  if transformed_message.id and transformed_message.method then
    self.pending_requests[transformed_message.id] = {
      method = transformed_message.method,
      timestamp = os.time(),
    }
    self.stats.requests_sent = self.stats.requests_sent + 1
  end

  -- Forward to LSP server
  self:_send_to_server(transformed_message)
end

-- Process message from LSP server (container → host)
-- @param message table: JSON-RPC message from LSP server
function M:_handle_server_message(message)
  if self.state ~= M.PROXY_STATE.RUNNING then
    return
  end

  log.debug('Proxy: Received server message: %s', message.method or 'response')

  -- Determine original method for responses
  local original_method = nil
  if message.id and not message.method then
    local pending = self.pending_requests[message.id]
    if pending then
      original_method = pending.method
      self.pending_requests[message.id] = nil -- Clean up
      self.stats.responses_received = self.stats.responses_received + 1
    end
  end

  -- Transform paths (container → host)
  local transformed_message = self.transformer.transform_response_to_host(message, original_method)

  -- Forward to Neovim client
  self:_send_to_client(transformed_message)
end

-- Send message to LSP server in container
-- @param message table: JSON-RPC message
function M:_send_to_server(message)
  if not self.server_transport or not self.server_transport:is_connected() then
    log.error('Proxy: Server transport not available')
    self:_handle_error('Server transport disconnected')
    return
  end

  local jsonrpc = require('container.lsp.proxy.jsonrpc')
  local serialized, err = jsonrpc.serialize_message(message)

  if not serialized then
    log.error('Proxy: Failed to serialize message for server: %s', err)
    self:_handle_error('Message serialization failed: ' .. err)
    return
  end

  if self.config.trace_messages then
    log.debug('Proxy: → Server: %s', serialized)
  end

  self.server_transport:send(serialized, function(send_err)
    if send_err then
      log.error('Proxy: Failed to send message to server: %s', send_err)
      self:_handle_error('Server send failed: ' .. send_err)
    end
  end)
end

-- Send message to Neovim client
-- @param message table: JSON-RPC message
function M:_send_to_client(message)
  if not self.client_transport or not self.client_transport:is_connected() then
    log.warn('Proxy: Client transport not available, queuing message')
    table.insert(self.message_queue, message)
    return
  end

  local jsonrpc = require('container.lsp.proxy.jsonrpc')
  local serialized, err = jsonrpc.serialize_message(message)

  if not serialized then
    log.error('Proxy: Failed to serialize message for client: %s', err)
    return
  end

  if self.config.trace_messages then
    log.debug('Proxy: → Client: %s', serialized)
  end

  self.client_transport:send(serialized, function(send_err)
    if send_err then
      log.error('Proxy: Failed to send message to client: %s', send_err)
    end
  end)
end

-- Handle transport errors
-- @param transport_name string: 'client' or 'server'
-- @param error_msg string: error message
function M:_handle_transport_error(transport_name, error_msg)
  log.error('Proxy: %s transport error: %s', transport_name, error_msg)
  self.stats.errors_count = self.stats.errors_count + 1

  if transport_name == 'server' then
    -- Server transport error is critical
    self:_handle_error('LSP server connection lost: ' .. error_msg)
  else
    -- Client transport error, try to reconnect
    log.warn('Proxy: Client transport error, will retry on next message')
  end
end

-- Handle transport close events
-- @param transport_name string: 'client' or 'server'
function M:_handle_transport_close(transport_name)
  log.info('Proxy: %s transport closed', transport_name)

  if transport_name == 'server' then
    -- Server closed, shut down proxy
    self:_handle_error('LSP server disconnected')
  end
end

-- Handle critical errors
-- @param error_msg string: error description
function M:_handle_error(error_msg)
  log.error('Proxy: Critical error: %s', error_msg)
  self.state = M.PROXY_STATE.ERROR

  if self.on_error then
    self.on_error(error_msg)
  end

  -- Attempt graceful shutdown
  vim.defer_fn(function()
    self:stop()
  end, 1000)
end

-- Set client transport (called when Neovim connects)
-- @param transport table: client transport object
function M:set_client_transport(transport)
  self.client_transport = transport

  -- Set up client transport handlers
  transport:set_message_handler(function(message)
    self:process_client_message(message)
  end)

  transport:set_error_handler(function(error_msg)
    self:_handle_transport_error('client', error_msg)
  end)

  transport:set_close_handler(function()
    self:_handle_transport_close('client')
  end)

  -- Process any queued messages
  for _, queued_message in ipairs(self.message_queue) do
    self:_send_to_client(queued_message)
  end
  self.message_queue = {}

  log.info('Proxy: Client transport connected')
end

-- Get proxy server statistics
-- @return table: server statistics
function M:get_stats()
  local uptime = self.stats.start_time and (os.time() - self.stats.start_time) or 0

  return vim.tbl_extend('force', self.stats, {
    state = self.state,
    uptime_seconds = uptime,
    pending_requests = vim.tbl_count(self.pending_requests),
    queued_messages = #self.message_queue,
    transform_cache = self.transformer and self.transformer.get_cache_stats() or {},
    transport_stats = {
      client = self.client_transport and self.client_transport:get_stats() or nil,
      server = self.server_transport and self.server_transport:get_stats() or nil,
    },
  })
end

-- Health check for proxy server
-- @return table: health status
function M:health_check()
  local health = {
    status = self.state,
    healthy = self.state == M.PROXY_STATE.RUNNING,
    issues = {},
  }

  -- Check transports
  if not self.server_transport or not self.server_transport:is_connected() then
    table.insert(health.issues, 'Server transport not connected')
    health.healthy = false
  end

  if not self.client_transport or not self.client_transport:is_connected() then
    table.insert(health.issues, 'Client transport not connected')
  end

  -- Check for stale requests
  local stale_threshold = 30 -- seconds
  local current_time = os.time()
  local stale_count = 0

  for id, request in pairs(self.pending_requests) do
    if current_time - request.timestamp > stale_threshold then
      stale_count = stale_count + 1
    end
  end

  if stale_count > 0 then
    table.insert(health.issues, string.format('%d stale requests detected', stale_count))
  end

  -- Check error rate
  if self.stats.errors_count > 10 then
    table.insert(health.issues, 'High error count: ' .. self.stats.errors_count)
    health.healthy = false
  end

  return health
end

-- Clean up stale requests
function M:cleanup_stale_requests()
  local stale_threshold = 60 -- seconds
  local current_time = os.time()
  local cleaned_count = 0

  for id, request in pairs(self.pending_requests) do
    if current_time - request.timestamp > stale_threshold then
      self.pending_requests[id] = nil
      cleaned_count = cleaned_count + 1
    end
  end

  if cleaned_count > 0 then
    log.debug('Proxy: Cleaned up %d stale requests', cleaned_count)
  end
end

-- Set event handlers
-- @param handlers table: event handler functions
function M:set_handlers(handlers)
  if handlers.on_message then
    self.on_message = handlers.on_message
  end
  if handlers.on_error then
    self.on_error = handlers.on_error
  end
  if handlers.on_close then
    self.on_close = handlers.on_close
  end
end

-- Update proxy configuration
-- @param new_config table: updated configuration
function M:update_config(new_config)
  self.config = vim.tbl_deep_extend('force', self.config, new_config or {})

  -- Reinitialize transformer if path settings changed
  if new_config.host_workspace or new_config.container_workspace then
    if self.transformer then
      self.transformer.setup(self.config.host_workspace, self.config.container_workspace)
    end
  end

  log.debug('Proxy: Configuration updated')
end

-- Create a proxy server factory with common configurations
M.create_factory = function()
  return {
    -- Create proxy for Go LSP (gopls)
    create_gopls_proxy = function(container_id, host_workspace)
      return M.create_proxy_server({
        server_cmd = { 'gopls', 'serve' },
        host_workspace = host_workspace,
        container_workspace = '/workspace',
        debug_level = 1,
      })
    end,

    -- Create proxy for Python LSP (pylsp)
    create_pylsp_proxy = function(container_id, host_workspace)
      return M.create_proxy_server({
        server_cmd = { 'pylsp' },
        host_workspace = host_workspace,
        container_workspace = '/workspace',
        debug_level = 1,
      })
    end,

    -- Create proxy for TypeScript LSP
    create_tsserver_proxy = function(container_id, host_workspace)
      return M.create_proxy_server({
        server_cmd = { 'typescript-language-server', '--stdio' },
        host_workspace = host_workspace,
        container_workspace = '/workspace',
        debug_level = 1,
      })
    end,

    -- Create generic proxy
    create_generic_proxy = function(container_id, host_workspace, server_cmd)
      return M.create_proxy_server({
        server_cmd = server_cmd,
        host_workspace = host_workspace,
        container_workspace = '/workspace',
        debug_level = 1,
      })
    end,
  }
end

return M
