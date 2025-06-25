-- Alternative approach: Override vim.lsp.handlers globally for container_gopls
local M = {}
local log = require('container.utils.log')

-- Store original handlers
local original_handlers = {}

-- Helper function to transform URIs from container to host paths
local function transform_uri_container_to_host(uri, host_workspace)
  if uri and uri:match('^file:///workspace') then
    local transformed = uri:gsub('^file:///workspace', 'file://' .. host_workspace)
    log.debug('Proxy Fix: URI transformation: %s -> %s', uri, transformed)
    return transformed
  end
  return uri
end

-- Helper function to recursively transform URIs in response objects
local function transform_response_uris(obj, host_workspace)
  if type(obj) == 'table' then
    for key, value in pairs(obj) do
      if key == 'uri' and type(value) == 'string' then
        obj[key] = transform_uri_container_to_host(value, host_workspace)
      elseif key == 'targetUri' and type(value) == 'string' then
        obj[key] = transform_uri_container_to_host(value, host_workspace)
      elseif type(value) == 'table' then
        transform_response_uris(value, host_workspace)
      end
    end
  end
  return obj
end

-- Custom definition handler that definitely works
local function custom_definition_handler(host_workspace)
  return function(err, result, context, config)
    log.info('Proxy Fix: Custom definition handler called')
    log.debug('Proxy Fix: Original result: %s', vim.inspect(result))

    if err then
      log.error('Proxy Fix: Definition error: %s', tostring(err))
      vim.notify('LSP definition error: ' .. tostring(err), vim.log.levels.ERROR)
      return
    end

    if not result or vim.tbl_isempty(result) then
      log.debug('Proxy Fix: No definition found')
      vim.notify('No definition found', vim.log.levels.INFO)
      return
    end

    -- Transform URIs in result
    transform_response_uris(result, host_workspace)
    log.debug('Proxy Fix: Transformed result: %s', vim.inspect(result))

    -- Handle both single location and array of locations
    local locations = vim.tbl_islist(result) and result or { result }
    log.debug('Proxy Fix: Processing %d location(s)', #locations)

    if #locations == 1 then
      -- Single location - jump directly
      local location = locations[1]
      local uri = location.uri or location.targetUri
      local range = location.range or location.targetRange or location.targetSelectionRange

      log.debug('Proxy Fix: Single location - URI: %s, Range: %s', uri, vim.inspect(range))

      if uri and range then
        -- Convert URI to file path
        local file_path = vim.uri_to_fname(uri)
        log.info('Proxy Fix: Definition jump to file: %s', file_path)

        -- Verify file exists
        if vim.fn.filereadable(file_path) == 1 then
          log.debug('Proxy Fix: File exists, opening: %s', file_path)
          vim.cmd('edit ' .. vim.fn.fnameescape(file_path))
          if range.start then
            local line = range.start.line + 1
            local col = range.start.character + 1
            log.debug('Proxy Fix: Setting cursor to line %d, col %d', line, col)

            -- Ensure we're not setting cursor outside buffer
            local buf_lines = vim.api.nvim_buf_line_count(0)
            if line <= buf_lines then
              vim.api.nvim_win_set_cursor(0, { line, col })
            else
              log.warn('Proxy Fix: Line %d exceeds buffer size %d', line, buf_lines)
              vim.api.nvim_win_set_cursor(0, { buf_lines, 0 })
            end
          end
        else
          log.error('Proxy Fix: File does not exist: %s', file_path)
          vim.notify('File not found: ' .. file_path, vim.log.levels.ERROR)
        end
      else
        log.error('Proxy Fix: Missing URI or range in location')
      end
    else
      -- Multiple locations - use quickfix list
      log.debug('Proxy Fix: Multiple locations, creating quickfix list')
      local qf_items = {}
      for _, location in ipairs(locations) do
        local uri = location.uri or location.targetUri
        local range = location.range or location.targetRange or location.targetSelectionRange
        if uri and range then
          local file_path = vim.uri_to_fname(uri)
          table.insert(qf_items, {
            filename = file_path,
            lnum = range.start.line + 1,
            col = range.start.character + 1,
            text = 'Definition',
          })
        end
      end

      if #qf_items > 0 then
        vim.fn.setqflist(qf_items)
        vim.cmd('copen')
      end
    end
  end
end

-- Override global handlers temporarily for container_gopls
function M.enable_handler_override(host_workspace)
  log.info('Proxy Fix: Enabling global handler override for host workspace: %s', host_workspace)

  -- Store original handlers
  original_handlers['textDocument/definition'] = vim.lsp.handlers['textDocument/definition']

  -- Override global handler
  vim.lsp.handlers['textDocument/definition'] = custom_definition_handler(host_workspace)

  log.info('Proxy Fix: Global definition handler overridden')
end

-- Restore original handlers
function M.disable_handler_override()
  log.info('Proxy Fix: Restoring original handlers')

  for method, handler in pairs(original_handlers) do
    vim.lsp.handlers[method] = handler
  end

  original_handlers = {}
  log.info('Proxy Fix: Original handlers restored')
end

-- Check if we should apply the fix (only when container_gopls is active)
function M.auto_enable_if_needed()
  local clients = vim.lsp.get_clients and vim.lsp.get_clients() or vim.lsp.get_active_clients()

  for _, client in ipairs(clients) do
    if client.name == 'container_gopls' and not client.is_stopped() then
      -- Try to get host workspace from client config
      local host_workspace = client.config.root_dir or vim.fn.getcwd()
      log.info('Proxy Fix: Auto-enabling handler override for container_gopls')
      M.enable_handler_override(host_workspace)
      return true
    end
  end

  return false
end

return M
