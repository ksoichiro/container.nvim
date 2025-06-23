-- lua/container/lsp/proxy/transport.lua
-- Transport layer for LSP proxy communication
-- Handles stdio and optional TCP communication with async I/O

local M = {}
local log = require('container.utils.log')

-- Transport types
M.TRANSPORT_TYPES = {
  STDIO = 'stdio',
  TCP = 'tcp',
}

-- Transport state
M.TRANSPORT_STATE = {
  CONNECTING = 'connecting',
  CONNECTED = 'connected',
  DISCONNECTED = 'disconnected',
  ERROR = 'error',
}

-- Create stdio transport for docker exec communication
-- @param read_stream userdata: readable stream (stdin)
-- @param write_stream userdata: writable stream (stdout)
-- @return table: transport object
function M.create_stdio_transport(read_stream, write_stream)
  local transport = {
    type = M.TRANSPORT_TYPES.STDIO,
    state = M.TRANSPORT_STATE.CONNECTED,
    read_stream = read_stream,
    write_stream = write_stream,
    read_buffer = '',
    write_queue = {},
    on_message = nil,
    on_error = nil,
    on_close = nil,
  }

  -- Set up async reading
  if read_stream then
    -- Check if read_stream is already a vim.loop handle or a file descriptor
    if type(read_stream) == 'userdata' and read_stream.read_start then
      -- It's already a vim.loop pipe handle with read_start method
      transport.read_handle = read_stream
      transport.read_handle:read_start(function(err, data)
        if err then
          log.error('Transport: Read error: %s', err)
          transport:_handle_error(err)
        elseif data then
          transport:_handle_incoming_data(data)
        else
          log.debug('Transport: Read stream closed')
          transport:_handle_close()
        end
      end)
    else
      -- It's a file descriptor or invalid handle, create a new pipe and open it
      transport.read_handle = vim.loop.new_pipe(false)
      if transport.read_handle and type(read_stream) == 'number' then
        transport.read_handle:open(read_stream)
        transport.read_handle:read_start(function(err, data)
          if err then
            log.error('Transport: Read error: %s', err)
            transport:_handle_error(err)
          elseif data then
            transport:_handle_incoming_data(data)
          else
            log.debug('Transport: Read stream closed')
            transport:_handle_close()
          end
        end)
      else
        log.error('Transport: Invalid read_stream type: %s', type(read_stream))
        transport.read_handle = nil
      end
    end
  end

  -- Set up async writing
  if write_stream then
    -- Check if write_stream is already a vim.loop handle or a file descriptor
    if type(write_stream) == 'userdata' and write_stream.write then
      -- It's already a vim.loop pipe handle with write method
      transport.write_handle = write_stream
    else
      -- It's a file descriptor or invalid handle, create a new pipe and open it
      transport.write_handle = vim.loop.new_pipe(false)
      if transport.write_handle and type(write_stream) == 'number' then
        transport.write_handle:open(write_stream)
      else
        log.error('Transport: Invalid write_stream type: %s', type(write_stream))
        transport.write_handle = nil
      end
    end
  end

  -- Add transport methods
  setmetatable(transport, { __index = M })

  log.debug('Transport: Created stdio transport')
  return transport
end

-- Create TCP transport (for debugging/network scenarios)
-- @param host string: target host
-- @param port number: target port
-- @return table: transport object
function M.create_tcp_transport(host, port)
  local transport = {
    type = M.TRANSPORT_TYPES.TCP,
    state = M.TRANSPORT_STATE.CONNECTING,
    host = host,
    port = port,
    socket = nil,
    read_buffer = '',
    write_queue = {},
    on_message = nil,
    on_error = nil,
    on_close = nil,
  }

  -- Set up TCP connection
  transport.socket = vim.loop.new_tcp()
  if not transport.socket then
    transport.state = M.TRANSPORT_STATE.ERROR
    return transport
  end

  -- Connect to target
  transport.socket:connect(host, port, function(err)
    if err then
      log.error('Transport: TCP connection failed: %s', err)
      transport.state = M.TRANSPORT_STATE.ERROR
      transport:_handle_error(err)
    else
      log.debug('Transport: TCP connected to %s:%d', host, port)
      transport.state = M.TRANSPORT_STATE.CONNECTED
      transport:_start_reading()
    end
  end)

  -- Add transport methods
  setmetatable(transport, { __index = M })

  log.debug('Transport: Created TCP transport to %s:%d', host, port)
  return transport
end

-- Set message handler callback
-- @param callback function: function(message_table)
function M:set_message_handler(callback)
  self.on_message = callback
end

-- Set error handler callback
-- @param callback function: function(error_string)
function M:set_error_handler(callback)
  self.on_error = callback
end

-- Set close handler callback
-- @param callback function: function()
function M:set_close_handler(callback)
  self.on_close = callback
end

-- Send a message through the transport
-- @param message_data string: serialized LSP message
-- @param callback function|nil: optional completion callback
function M:send(message_data, callback)
  if self.state ~= M.TRANSPORT_STATE.CONNECTED then
    local err = 'Transport not connected'
    log.error('Transport: Send failed: %s', err)
    if callback then
      callback(err)
    end
    return
  end

  if not message_data or type(message_data) ~= 'string' then
    local err = 'Invalid message data'
    log.error('Transport: Send failed: %s', err)
    if callback then
      callback(err)
    end
    return
  end

  log.debug('Transport: Sending %d bytes', #message_data)

  if self.type == M.TRANSPORT_TYPES.STDIO then
    self:_send_stdio(message_data, callback)
  elseif self.type == M.TRANSPORT_TYPES.TCP then
    self:_send_tcp(message_data, callback)
  else
    local err = 'Unknown transport type'
    log.error('Transport: Send failed: %s', err)
    if callback then
      callback(err)
    end
  end
end

-- Close the transport
function M:close()
  log.debug('Transport: Closing transport')

  if self.read_handle then
    self.read_handle:close()
    self.read_handle = nil
  end

  if self.write_handle then
    self.write_handle:close()
    self.write_handle = nil
  end

  if self.socket then
    self.socket:close()
    self.socket = nil
  end

  self.state = M.TRANSPORT_STATE.DISCONNECTED
end

-- Check if transport is connected
-- @return boolean: true if connected
function M:is_connected()
  return self.state == M.TRANSPORT_STATE.CONNECTED
end

-- Get transport statistics
-- @return table: transport stats
function M:get_stats()
  return {
    type = self.type,
    state = self.state,
    buffer_size = #self.read_buffer,
    queue_size = #self.write_queue,
  }
end

-- Private: Handle incoming data
function M:_handle_incoming_data(data)
  self.read_buffer = self.read_buffer .. data
  log.debug('Transport: Received %d bytes, buffer now %d bytes', #data, #self.read_buffer)

  -- Parse complete messages from buffer
  local jsonrpc = require('container.lsp.proxy.jsonrpc')
  local messages, remaining = jsonrpc.parse_message_stream(self.read_buffer)
  self.read_buffer = remaining

  -- Forward complete messages
  for _, message in ipairs(messages) do
    if self.on_message then
      self.on_message(message)
    end
  end
end

-- Private: Handle transport error
function M:_handle_error(error_msg)
  log.error('Transport: Error occurred: %s', error_msg)
  self.state = M.TRANSPORT_STATE.ERROR

  if self.on_error then
    self.on_error(error_msg)
  end
end

-- Private: Handle transport close
function M:_handle_close()
  log.debug('Transport: Connection closed')
  self.state = M.TRANSPORT_STATE.DISCONNECTED

  if self.on_close then
    self.on_close()
  end
end

-- Private: Send data via stdio
function M:_send_stdio(data, callback)
  if not self.write_handle then
    local err = 'No write handle available'
    log.error('Transport: %s', err)
    if callback then
      callback(err)
    end
    return
  end

  self.write_handle:write(data, function(err)
    if err then
      log.error('Transport: Write error: %s', err)
      self:_handle_error(err)
    else
      log.debug('Transport: Successfully wrote %d bytes', #data)
    end

    if callback then
      callback(err)
    end
  end)
end

-- Private: Send data via TCP
function M:_send_tcp(data, callback)
  if not self.socket then
    local err = 'No socket available'
    log.error('Transport: %s', err)
    if callback then
      callback(err)
    end
    return
  end

  self.socket:write(data, function(err)
    if err then
      log.error('Transport: TCP write error: %s', err)
      self:_handle_error(err)
    else
      log.debug('Transport: Successfully wrote %d bytes via TCP', #data)
    end

    if callback then
      callback(err)
    end
  end)
end

-- Private: Start reading for TCP transport
function M:_start_reading()
  if not self.socket then
    return
  end

  self.socket:read_start(function(err, data)
    if err then
      log.error('Transport: TCP read error: %s', err)
      self:_handle_error(err)
    elseif data then
      self:_handle_incoming_data(data)
    else
      log.debug('Transport: TCP connection closed by peer')
      self:_handle_close()
    end
  end)
end

-- Create transport from docker exec command
-- @param container_id string: docker container ID
-- @param server_cmd table: LSP server command array
-- @return table|nil: transport object or nil on error
function M.create_docker_exec_transport(container_id, server_cmd)
  if not container_id or not server_cmd then
    log.error('Transport: Invalid docker exec parameters')
    return nil
  end

  -- Build docker exec command
  local docker_cmd = { 'docker', 'exec', '-i', container_id }
  for _, arg in ipairs(server_cmd) do
    table.insert(docker_cmd, arg)
  end

  log.debug('Transport: Starting docker exec: %s', table.concat(docker_cmd, ' '))

  -- Start process with pipes
  local stdin = vim.loop.new_pipe(false)
  local stdout = vim.loop.new_pipe(false)
  local stderr = vim.loop.new_pipe(false)

  local handle, pid = vim.loop.spawn(docker_cmd[1], {
    args = vim.list_slice(docker_cmd, 2),
    stdio = { stdin, stdout, stderr },
  }, function(code, signal)
    log.debug('Transport: Docker exec process ended (code=%d, signal=%d)', code, signal)
  end)

  if not handle then
    log.error('Transport: Failed to spawn docker exec process')
    return nil
  end

  -- Create transport with the pipes
  local transport = M.create_stdio_transport(stdout, stdin)
  transport.process_handle = handle
  transport.process_pid = pid
  transport.container_id = container_id
  transport.server_cmd = server_cmd

  -- Handle stderr for debugging
  if stderr then
    stderr:read_start(function(err, data)
      if data then
        log.debug('Transport: LSP server stderr: %s', vim.trim(data))
      end
    end)
  end

  return transport
end

-- Enhanced transport with message queuing and retry logic
-- @param base_transport table: base transport object
-- @return table: enhanced transport with queuing
function M.create_queued_transport(base_transport)
  local queued = {
    base = base_transport,
    send_queue = {},
    max_queue_size = 1000,
    retry_count = 3,
    retry_delay = 100, -- ms
  }

  -- Override send method with queuing
  function queued:send(message_data, callback)
    if #self.send_queue >= self.max_queue_size then
      local err = 'Send queue full'
      log.error('Transport: %s', err)
      if callback then
        callback(err)
      end
      return
    end

    table.insert(self.send_queue, {
      data = message_data,
      callback = callback,
      attempts = 0,
    })

    self:_process_queue()
  end

  -- Process send queue
  function queued:_process_queue()
    if #self.send_queue == 0 or not self.base:is_connected() then
      return
    end

    local item = self.send_queue[1]
    item.attempts = item.attempts + 1

    self.base:send(item.data, function(err)
      if not err then
        -- Success, remove from queue
        table.remove(self.send_queue, 1)
        if item.callback then
          item.callback(nil)
        end
        -- Process next item
        vim.defer_fn(function()
          self:_process_queue()
        end, 1)
      else
        -- Error, retry if attempts remaining
        if item.attempts < self.retry_count then
          log.warn('Transport: Send failed, retrying (%d/%d): %s', item.attempts, self.retry_count, err)
          vim.defer_fn(function()
            self:_process_queue()
          end, self.retry_delay)
        else
          -- Max retries exceeded, fail
          log.error('Transport: Send failed after %d retries: %s', self.retry_count, err)
          table.remove(self.send_queue, 1)
          if item.callback then
            item.callback(err)
          end
          -- Continue with next item
          self:_process_queue()
        end
      end
    end)
  end

  -- Delegate other methods to base transport
  setmetatable(queued, {
    __index = function(t, k)
      return t.base[k] or M[k]
    end,
  })

  return queued
end

return M
