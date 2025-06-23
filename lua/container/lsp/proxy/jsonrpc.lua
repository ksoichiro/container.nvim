-- lua/container/lsp/proxy/jsonrpc.lua
-- JSON-RPC message processing module for LSP proxy
-- Handles Content-Length parsing, message serialization, and LSP protocol compliance

local M = {}
local log = require('container.utils.log')

-- LSP protocol constants
local CONTENT_LENGTH_HEADER = 'Content-Length'
local HEADER_SEPARATOR = '\r\n\r\n'
local LINE_SEPARATOR = '\r\n'

-- JSON-RPC message types
M.MESSAGE_TYPES = {
  REQUEST = 'request',
  RESPONSE = 'response',
  NOTIFICATION = 'notification',
  ERROR = 'error',
}

-- Parse Content-Length header from LSP message
-- @param header_line string: "Content-Length: 123"
-- @return number|nil: content length in bytes
function M.parse_content_length(header_line)
  if not header_line or type(header_line) ~= 'string' then
    return nil
  end

  local length = header_line:match('Content%-Length:%s*(%d+)')
  local parsed_length = length and tonumber(length)

  if parsed_length and parsed_length >= 0 then
    log.debug('JSON-RPC: Parsed content length: %d bytes', parsed_length)
    return parsed_length
  end

  log.warn('JSON-RPC: Invalid Content-Length header: %s', header_line)
  return nil
end

-- Parse a complete JSON-RPC message from raw input
-- @param raw_message string: "Content-Length: 123\r\n\r\n{json}"
-- @return table|nil, string|nil: parsed message, error
function M.parse_message(raw_message)
  if not raw_message or type(raw_message) ~= 'string' then
    return nil, 'Invalid raw message input'
  end

  -- Find header separator
  local separator_pos = raw_message:find(HEADER_SEPARATOR, 1, true)
  if not separator_pos then
    return nil, 'No header separator found'
  end

  -- Extract headers and body
  local headers_part = raw_message:sub(1, separator_pos - 1)
  local body_part = raw_message:sub(separator_pos + #HEADER_SEPARATOR)

  -- Parse Content-Length from headers
  local content_length = nil
  for header_line in headers_part:gmatch('[^\r\n]+') do
    content_length = M.parse_content_length(header_line)
    if content_length then
      break
    end
  end

  if not content_length then
    return nil, 'No valid Content-Length header found'
  end

  -- Validate body length
  if #body_part ~= content_length then
    return nil, string.format('Body length mismatch: expected %d, got %d', content_length, #body_part)
  end

  -- Parse JSON body
  local ok, parsed_json = pcall(vim.json.decode, body_part)
  if not ok then
    return nil, 'Failed to parse JSON body: ' .. tostring(parsed_json)
  end

  -- Validate JSON-RPC structure
  if not parsed_json.jsonrpc or parsed_json.jsonrpc ~= '2.0' then
    return nil, 'Invalid JSON-RPC version'
  end

  log.debug('JSON-RPC: Successfully parsed message: %s', parsed_json.method or 'response')
  return parsed_json, nil
end

-- Serialize a JSON-RPC message to LSP wire format
-- @param message table: JSON-RPC message object
-- @return string|nil, string|nil: serialized message, error
function M.serialize_message(message)
  if not message or type(message) ~= 'table' then
    return nil, 'Invalid message object'
  end

  -- Ensure JSON-RPC 2.0 version
  if not message.jsonrpc then
    message.jsonrpc = '2.0'
  end

  -- Serialize JSON body
  local ok, json_body = pcall(vim.json.encode, message)
  if not ok then
    return nil, 'Failed to encode JSON: ' .. tostring(json_body)
  end

  -- Calculate content length
  local content_length = #json_body

  -- Construct LSP message with headers
  local lsp_message = string.format('%s: %d%s%s', CONTENT_LENGTH_HEADER, content_length, HEADER_SEPARATOR, json_body)

  log.debug('JSON-RPC: Serialized message: %d bytes', content_length)
  return lsp_message, nil
end

-- Determine message type from JSON-RPC message
-- @param message table: parsed JSON-RPC message
-- @return string: message type
function M.get_message_type(message)
  if not message or type(message) ~= 'table' then
    return M.MESSAGE_TYPES.ERROR
  end

  -- Request: has method and id
  if message.method and message.id then
    return M.MESSAGE_TYPES.REQUEST
  end

  -- Notification: has method but no id
  if message.method and not message.id then
    return M.MESSAGE_TYPES.NOTIFICATION
  end

  -- Response: has id and result/error but no method
  if message.id and not message.method then
    if message.result ~= nil then
      return M.MESSAGE_TYPES.RESPONSE
    elseif message.error then
      return M.MESSAGE_TYPES.ERROR
    end
  end

  return M.MESSAGE_TYPES.ERROR
end

-- Extract method name from JSON-RPC message
-- @param message table: parsed JSON-RPC message
-- @return string|nil: method name or nil for responses
function M.get_method(message)
  if not message or type(message) ~= 'table' then
    return nil
  end
  return message.method
end

-- Extract request/response ID from JSON-RPC message
-- @param message table: parsed JSON-RPC message
-- @return number|string|nil: message ID
function M.get_id(message)
  if not message or type(message) ~= 'table' then
    return nil
  end
  return message.id
end

-- Create a JSON-RPC request message
-- @param id number|string: request ID
-- @param method string: LSP method name
-- @param params table|nil: request parameters
-- @return table: JSON-RPC request message
function M.create_request(id, method, params)
  return {
    jsonrpc = '2.0',
    id = id,
    method = method,
    params = params or {},
  }
end

-- Create a JSON-RPC notification message
-- @param method string: LSP method name
-- @param params table|nil: notification parameters
-- @return table: JSON-RPC notification message
function M.create_notification(method, params)
  return {
    jsonrpc = '2.0',
    method = method,
    params = params or {},
  }
end

-- Create a JSON-RPC response message
-- @param id number|string: request ID
-- @param result any: response result
-- @return table: JSON-RPC response message
function M.create_response(id, result)
  return {
    jsonrpc = '2.0',
    id = id,
    result = result,
  }
end

-- Create a JSON-RPC error response message
-- @param id number|string|nil: request ID (nil for parse errors)
-- @param code number: error code
-- @param message string: error message
-- @param data any|nil: additional error data
-- @return table: JSON-RPC error response message
function M.create_error_response(id, code, message, data)
  return {
    jsonrpc = '2.0',
    id = id,
    error = {
      code = code,
      message = message,
      data = data,
    },
  }
end

-- LSP error codes (from LSP specification)
M.ERROR_CODES = {
  PARSE_ERROR = -32700,
  INVALID_REQUEST = -32600,
  METHOD_NOT_FOUND = -32601,
  INVALID_PARAMS = -32602,
  INTERNAL_ERROR = -32603,
  -- LSP specific error codes
  REQUEST_CANCELLED = -32800,
  CONTENT_MODIFIED = -32801,
}

-- Validate JSON-RPC message structure
-- @param message table: parsed JSON-RPC message
-- @return boolean, string|nil: is_valid, error_message
function M.validate_message(message)
  if not message or type(message) ~= 'table' then
    return false, 'Message must be a table'
  end

  -- Check JSON-RPC version
  if not message.jsonrpc or message.jsonrpc ~= '2.0' then
    return false, 'Invalid or missing JSON-RPC version'
  end

  local msg_type = M.get_message_type(message)

  -- Validate based on message type
  if msg_type == M.MESSAGE_TYPES.REQUEST then
    if not message.method or type(message.method) ~= 'string' then
      return false, 'Request must have a method string'
    end
    if not message.id then
      return false, 'Request must have an id'
    end
  elseif msg_type == M.MESSAGE_TYPES.NOTIFICATION then
    if not message.method or type(message.method) ~= 'string' then
      return false, 'Notification must have a method string'
    end
  elseif msg_type == M.MESSAGE_TYPES.RESPONSE then
    if not message.id then
      return false, 'Response must have an id'
    end
    if message.result == nil and not message.error then
      return false, 'Response must have either result or error'
    end
  elseif msg_type == M.MESSAGE_TYPES.ERROR then
    if not message.error then
      return false, 'Error response must have error object'
    end
    if not message.error.code or not message.error.message then
      return false, 'Error object must have code and message'
    end
  else
    return false, 'Unknown message type'
  end

  return true, nil
end

-- Parse stream of LSP messages (handles partial messages)
-- @param stream_buffer string: accumulated stream data
-- @return table, string: {messages, remaining_buffer}
function M.parse_message_stream(stream_buffer)
  local messages = {}
  local remaining = stream_buffer
  local pos = 1

  while pos <= #remaining do
    -- Look for header separator
    local separator_pos = remaining:find(HEADER_SEPARATOR, pos, true)
    if not separator_pos then
      -- No complete header found, need more data
      break
    end

    -- Extract headers
    local headers_part = remaining:sub(pos, separator_pos - 1)
    local content_length = nil

    for header_line in headers_part:gmatch('[^\r\n]+') do
      content_length = M.parse_content_length(header_line)
      if content_length then
        break
      end
    end

    if content_length then
      -- Check if we have complete body
      local body_start = separator_pos + #HEADER_SEPARATOR
      local body_end = body_start + content_length - 1

      if body_end > #remaining then
        -- Incomplete message, need more data
        break
      end

      -- Extract complete message
      local message_text = remaining:sub(pos, body_end)
      local parsed_message, parse_error = M.parse_message(message_text)

      if parsed_message then
        table.insert(messages, parsed_message)
        log.debug('JSON-RPC: Parsed complete message from stream')
      else
        log.warn('JSON-RPC: Failed to parse message from stream: %s', parse_error)
      end

      -- Move to next message
      pos = body_end + 1
    else
      -- Invalid header, skip this message
      pos = separator_pos + #HEADER_SEPARATOR
      log.warn('JSON-RPC: Skipping message with invalid headers')
    end
  end

  -- Return parsed messages and remaining buffer
  local remaining_buffer = pos <= #remaining and remaining:sub(pos) or ''
  return messages, remaining_buffer
end

-- Create a batch of JSON-RPC messages
-- @param messages table: array of JSON-RPC message objects
-- @return string|nil, string|nil: serialized batch, error
function M.serialize_batch(messages)
  if not messages or type(messages) ~= 'table' or #messages == 0 then
    return nil, 'Invalid or empty message batch'
  end

  local batch_parts = {}
  for i, message in ipairs(messages) do
    local serialized, err = M.serialize_message(message)
    if not serialized then
      return nil, string.format('Failed to serialize message %d: %s', i, err)
    end
    table.insert(batch_parts, serialized)
  end

  log.debug('JSON-RPC: Serialized batch of %d messages', #messages)
  return table.concat(batch_parts), nil
end

return M
