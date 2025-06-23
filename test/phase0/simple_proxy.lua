#!/usr/bin/env lua

-- Phase 0.5: Simple JSON-RPC Proxy Implementation
-- Basic stdin → transformation → stdout relay for LSP messages
-- This validates the core proxy concept before full implementation

-- Phase 0: Use simple string manipulation instead of JSON parsing
-- This is sufficient for validating the core proxy concept
local json = nil

-- Simple JSON-RPC message parser
local function parse_content_length(header)
  if not header then
    return nil
  end
  local length = header:match('Content%-Length:%s*(%d+)')
  return length and tonumber(length) or nil
end

-- Read a complete JSON-RPC message from stdin
local function read_message()
  -- Read the Content-Length header
  local header = io.read('*l')
  if not header then
    return nil, 'EOF on header read'
  end

  local content_length = parse_content_length(header)
  if not content_length then
    return nil, 'Invalid Content-Length header: ' .. header
  end

  -- Read the empty line separator
  local separator = io.read('*l')
  if separator ~= '' then
    return nil, 'Expected empty line after header, got: ' .. (separator or 'nil')
  end

  -- Read the JSON body
  local body = io.read(content_length)
  if not body or #body ~= content_length then
    return nil, 'Failed to read complete message body'
  end

  return body, nil
end

-- Write a complete JSON-RPC message to stdout
local function write_message(message)
  local content_length = #message
  io.write(string.format('Content-Length: %d\r\n\r\n%s', content_length, message))
  io.flush()
end

-- Simple path transformation (placeholder)
local function transform_paths(message_body, direction)
  -- Parse JSON if available
  if not json then
    -- Fallback: simple string replacement
    if direction == 'host_to_container' then
      -- More precise path replacement to avoid double replacements
      return message_body:gsub('file:///Users/[^/"]+/[^/"]+', 'file:///workspace')
    else
      return message_body:gsub('file:///workspace', 'file:///Users/testuser/project')
    end
  end

  -- Proper JSON parsing
  local parsed = json.decode(message_body)
  if not parsed then
    return message_body -- Return unchanged if parsing fails
  end

  -- Transform common path fields
  if direction == 'host_to_container' then
    -- Transform host paths to container paths
    if parsed.params then
      if parsed.params.rootUri then
        parsed.params.rootUri = parsed.params.rootUri:gsub('file:///Users/[^/]+/[^/]+', 'file:///workspace')
      end
      if parsed.params.textDocument and parsed.params.textDocument.uri then
        parsed.params.textDocument.uri =
          parsed.params.textDocument.uri:gsub('file:///Users/[^/]+/[^/]+', 'file:///workspace')
      end
    end
  else
    -- Transform container paths to host paths
    if parsed.uri then
      parsed.uri = parsed.uri:gsub('file:///workspace', 'file:///Users/testuser/project')
    end
    if parsed.result and type(parsed.result) == 'table' then
      if parsed.result.uri then
        parsed.result.uri = parsed.result.uri:gsub('file:///workspace', 'file:///Users/testuser/project')
      end
    end
  end

  return json.encode(parsed)
end

-- Main proxy loop
local function run_proxy()
  io.stderr:write('Simple LSP Proxy starting...\n')
  io.stderr:flush()

  local message_count = 0

  while true do
    -- Read message from client (Neovim)
    local message, err = read_message()
    if not message then
      if err:match('EOF') then
        io.stderr:write('Client disconnected\n')
        break
      else
        io.stderr:write('Error reading message: ' .. err .. '\n')
        break
      end
    end

    message_count = message_count + 1
    io.stderr:write(string.format('Processing message #%d\n', message_count))

    -- Transform paths (host → container)
    local transformed = transform_paths(message, 'host_to_container')

    -- Log the transformation for debugging
    if transformed ~= message then
      io.stderr:write('Path transformation applied\n')
    end

    -- Forward to LSP server (for now, just echo back)
    -- In real implementation, this would go to the actual LSP server
    write_message(transformed)

    -- Simulate a simple response for testing
    if message:match('"method":"initialize"') then
      local response = '{"jsonrpc":"2.0","id":1,"result":{"capabilities":{"textDocumentSync":1}}}'
      -- Transform paths (container → host)
      local response_transformed = transform_paths(response, 'container_to_host')
      write_message(response_transformed)
      io.stderr:write('Sent initialize response\n')
    end
  end

  io.stderr:write('Proxy shutting down\n')
end

-- Error handling wrapper
local function safe_run()
  local ok, err = pcall(run_proxy)
  if not ok then
    io.stderr:write('Proxy error: ' .. tostring(err) .. '\n')
    os.exit(1)
  end
end

-- Check if running as standalone script
if arg and arg[0] and arg[0]:match('simple_proxy%.lua$') then
  safe_run()
else
  -- Return module for testing
  return {
    parse_content_length = parse_content_length,
    read_message = read_message,
    write_message = write_message,
    transform_paths = transform_paths,
    run_proxy = safe_run,
  }
end
