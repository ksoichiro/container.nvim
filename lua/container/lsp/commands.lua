-- Container LSP Commands Module
-- Provides LSP commands that work with containerized language servers

local M = {}
local log = require('container.utils.log')
local transform = require('container.lsp.simple_transform')

-- Module state
local state = {
  registered_files = {},
  initialized = false,
}

-- Initialize the module
function M.setup(opts)
  opts = opts or {}

  -- Initialize path transformation
  transform.setup({
    host_workspace = opts.host_workspace or vim.fn.getcwd(),
    container_workspace = opts.container_workspace or '/workspace',
  })

  state.initialized = true
  log.info('Container LSP Commands: Initialized')
end

-- Get container LSP client
-- @param server_name string: LSP server name (e.g., 'gopls')
-- @return table|nil: LSP client or nil if not found
function M.get_container_client(server_name)
  local container_name = 'container_' .. server_name

  local clients = vim.lsp.get_clients and vim.lsp.get_clients() or vim.lsp.get_active_clients()
  for _, client in ipairs(clients) do
    if client.name == container_name then
      return client
    end
  end

  return nil
end

-- Validate prerequisites for LSP operations
-- @param server_name string: LSP server name
-- @return boolean, string: success status and error message
function M._validate_lsp_prerequisites(server_name)
  -- Check buffer validity
  local current_buf = vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(current_buf) or not vim.api.nvim_buf_is_loaded(current_buf) then
    return false, 'Invalid or unloaded buffer'
  end

  -- Check file type
  local filetype = vim.bo[current_buf].filetype
  if filetype == '' then
    return false, 'No filetype detected'
  end

  -- Check if initialization completed
  if not state.initialized then
    return false, 'LSP commands module not initialized'
  end

  return true, nil
end

-- Get and validate container client
-- @param server_name string: LSP server name
-- @return table|nil, string: client and error message
function M._get_validated_client(server_name)
  local client = M.get_container_client(server_name)
  if not client then
    return nil, 'No ' .. server_name .. ' client found. Try opening a Go file.'
  end

  -- Check if client is stopped
  if client.is_stopped() then
    return nil, 'Client ' .. server_name .. ' is stopped'
  end

  -- Check if client is initialized
  if not client.initialized then
    return nil, 'Client ' .. server_name .. ' is not yet initialized'
  end

  return client, nil
end

-- Register a file with the container LSP
-- @param bufnr number: buffer number (0 for current)
-- @param client table: LSP client
-- @return boolean: success status
function M.register_file(bufnr, client)
  bufnr = bufnr or 0

  if not client then
    log.error('Container LSP Commands: No client provided for file registration')
    return false
  end

  local file_path = vim.api.nvim_buf_get_name(bufnr)
  if file_path == '' then
    log.debug('Container LSP Commands: Empty file path, skipping registration')
    return false
  end

  -- Get container URI for the file
  local container_uri = transform.get_buffer_container_uri(bufnr)
  if not container_uri then
    log.error('Container LSP Commands: Failed to get container URI for %s', file_path)
    return false
  end

  -- Skip if already registered
  if state.registered_files[container_uri] then
    log.debug('Container LSP Commands: File already registered: %s', container_uri)
    return true
  end

  -- Get file content
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local text = table.concat(lines, '\n')

  -- Get language ID
  local filetype = vim.bo[bufnr].filetype

  -- Send didOpen notification
  client.notify('textDocument/didOpen', {
    textDocument = {
      uri = container_uri,
      languageId = filetype,
      version = 0,
      text = text,
    },
  })

  state.registered_files[container_uri] = true
  log.info('Container LSP Commands: Registered file %s as %s', file_path, container_uri)

  -- Setup buffer change tracking
  M._setup_buffer_tracking(bufnr, client, container_uri)

  return true
end

-- Setup buffer change tracking
function M._setup_buffer_tracking(bufnr, client, container_uri)
  local group_name = 'ContainerLSP_Buffer_' .. bufnr
  vim.api.nvim_create_augroup(group_name, { clear = true })

  -- Track changes
  vim.api.nvim_create_autocmd('TextChanged', {
    group = group_name,
    buffer = bufnr,
    callback = function()
      if vim.bo[bufnr].modified then
        local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
        local text = table.concat(lines, '\n')

        client.notify('textDocument/didChange', {
          textDocument = {
            uri = container_uri,
            version = vim.b[bufnr].changedtick or 0,
          },
          contentChanges = { {
            text = text,
          } },
        })
      end
    end,
  })

  -- Track saves
  vim.api.nvim_create_autocmd('BufWritePost', {
    group = group_name,
    buffer = bufnr,
    callback = function()
      client.notify('textDocument/didSave', {
        textDocument = {
          uri = container_uri,
        },
      })
    end,
  })

  -- Clean up on buffer delete
  vim.api.nvim_create_autocmd('BufDelete', {
    group = group_name,
    buffer = bufnr,
    callback = function()
      client.notify('textDocument/didClose', {
        textDocument = {
          uri = container_uri,
        },
      })
      state.registered_files[container_uri] = nil
      vim.api.nvim_del_augroup_by_name(group_name)
    end,
  })
end

-- Execute hover request
-- @param opts table: options including server_name
function M.hover(opts)
  opts = opts or {}
  local server_name = opts.server_name or 'gopls'

  -- Validate prerequisites
  local valid, error_msg = M._validate_lsp_prerequisites(server_name)
  if not valid then
    vim.notify('Container LSP: ' .. error_msg, vim.log.levels.ERROR)
    return false
  end

  -- Get validated client
  local client, client_error = M._get_validated_client(server_name)
  if not client then
    vim.notify('Container LSP: ' .. client_error, vim.log.levels.WARN)
    return false
  end

  -- Register current file
  if not M.register_file(0, client) then
    vim.notify('Container LSP: Failed to register current file', vim.log.levels.ERROR)
    return false
  end

  -- Get container URI
  local container_uri = transform.get_buffer_container_uri(0)
  if not container_uri then
    vim.notify('Container LSP: Cannot determine container path for current file', vim.log.levels.ERROR)
    return false
  end

  -- Make request with error handling
  local params = {
    textDocument = { uri = container_uri },
    position = vim.lsp.util.make_position_params(0, client.offset_encoding).position,
  }

  local success, request_error = pcall(function()
    client.request('textDocument/hover', params, function(err, result, ctx)
      if err then
        vim.notify('Container LSP: Hover request failed: ' .. tostring(err), vim.log.levels.ERROR)
        return
      end

      -- Use standard handler
      vim.lsp.handlers.hover(err, result, ctx)
    end, 0)
  end)

  if not success then
    vim.notify('Container LSP: Failed to send hover request: ' .. tostring(request_error), vim.log.levels.ERROR)
    return false
  end

  return true
end

-- Execute definition request
-- @param opts table: options including server_name
function M.definition(opts)
  opts = opts or {}
  local server_name = opts.server_name or 'gopls'

  local client = M.get_container_client(server_name)
  if not client then
    vim.notify('Container LSP: No ' .. server_name .. ' client found', vim.log.levels.ERROR)
    return
  end

  -- Register current file
  if not M.register_file(0, client) then
    vim.notify('Container LSP: Failed to register current file', vim.log.levels.ERROR)
    return
  end

  -- Get container URI
  local container_uri = transform.get_buffer_container_uri(0)
  if not container_uri then
    vim.notify('Container LSP: Cannot determine container path', vim.log.levels.ERROR)
    return
  end

  -- Make request
  local params = {
    textDocument = { uri = container_uri },
    position = vim.lsp.util.make_position_params(0, client.offset_encoding).position,
  }

  client.request('textDocument/definition', params, function(err, result, ctx)
    if err then
      vim.notify('Container LSP: Definition error: ' .. tostring(err), vim.log.levels.ERROR)
      return
    end

    if result then
      -- Transform container paths back to host paths
      local transformed_result = transform.transform_locations(result, 'to_host')

      -- Jump to location
      if type(transformed_result) == 'table' then
        if transformed_result.uri then
          vim.lsp.util.jump_to_location(transformed_result, client.offset_encoding)
        elseif #transformed_result > 0 then
          vim.lsp.util.jump_to_location(transformed_result[1], client.offset_encoding)
        else
          vim.notify('Container LSP: No definition found', vim.log.levels.INFO)
        end
      end
    else
      vim.notify('Container LSP: No definition found', vim.log.levels.INFO)
    end
  end, 0)
end

-- Execute references request
-- @param opts table: options including server_name
function M.references(opts)
  opts = opts or {}
  local server_name = opts.server_name or 'gopls'

  local client = M.get_container_client(server_name)
  if not client then
    vim.notify('Container LSP: No ' .. server_name .. ' client found', vim.log.levels.ERROR)
    return
  end

  -- Register current file
  if not M.register_file(0, client) then
    vim.notify('Container LSP: Failed to register current file', vim.log.levels.ERROR)
    return
  end

  -- Get container URI
  local container_uri = transform.get_buffer_container_uri(0)
  if not container_uri then
    vim.notify('Container LSP: Cannot determine container path', vim.log.levels.ERROR)
    return
  end

  -- Make request
  local params = {
    textDocument = { uri = container_uri },
    position = vim.lsp.util.make_position_params(0, client.offset_encoding).position,
    context = { includeDeclaration = true },
  }

  client.request('textDocument/references', params, function(err, result, ctx)
    if err then
      vim.notify('Container LSP: References error: ' .. tostring(err), vim.log.levels.ERROR)
      return
    end

    if result and #result > 0 then
      -- Transform all reference locations
      local transformed_refs = transform.transform_locations(result, 'to_host')

      -- Set quickfix list
      local items = vim.lsp.util.locations_to_items(transformed_refs, client.offset_encoding)
      vim.fn.setqflist({}, ' ', { title = 'Container LSP References', items = items })
      vim.cmd('copen')
    else
      vim.notify('Container LSP: No references found', vim.log.levels.INFO)
    end
  end, 0)
end

-- Setup user commands
function M.setup_commands()
  -- Hover command
  vim.api.nvim_create_user_command('ContainerLspHover', function(args)
    M.hover({ server_name = args.args ~= '' and args.args or 'gopls' })
  end, {
    nargs = '?',
    complete = function()
      return { 'gopls', 'pyright', 'tsserver' }
    end,
    desc = 'Show hover information using container LSP',
  })

  -- Definition command
  vim.api.nvim_create_user_command('ContainerLspDefinition', function(args)
    M.definition({ server_name = args.args ~= '' and args.args or 'gopls' })
  end, {
    nargs = '?',
    complete = function()
      return { 'gopls', 'pyright', 'tsserver' }
    end,
    desc = 'Go to definition using container LSP',
  })

  -- References command
  vim.api.nvim_create_user_command('ContainerLspReferences', function(args)
    M.references({ server_name = args.args ~= '' and args.args or 'gopls' })
  end, {
    nargs = '?',
    complete = function()
      return { 'gopls', 'pyright', 'tsserver' }
    end,
    desc = 'Find references using container LSP',
  })

  -- Command to manually setup keybindings
  vim.api.nvim_create_user_command('ContainerLspSetupKeys', function(args)
    local server_name = args.args ~= '' and args.args or 'gopls'
    local bufnr = vim.api.nvim_get_current_buf()

    local success = M.setup_keybindings({
      buffer = bufnr,
      server_name = server_name,
    })

    if success then
      vim.notify('Container LSP: Keybindings set up for ' .. server_name, vim.log.levels.INFO)
    else
      vim.notify('Container LSP: Failed to set up keybindings', vim.log.levels.ERROR)
    end
  end, {
    nargs = '?',
    complete = function()
      return { 'gopls', 'pyright', 'tsserver' }
    end,
    desc = 'Manually setup Container LSP keybindings for current buffer',
  })

  log.info('Container LSP Commands: User commands created')
end

-- Setup keybindings
-- @param opts table: keybinding options
function M.setup_keybindings(opts)
  opts = opts or {}
  local server_name = opts.server_name or 'gopls'
  local bufnr = opts.buffer or 0

  -- Validate buffer
  if not vim.api.nvim_buf_is_valid(bufnr) then
    log.error('Container LSP Commands: Invalid buffer for keybinding setup: %d', bufnr)
    return false
  end

  -- Default keybindings (can be overridden)
  local bindings = vim.tbl_extend('force', {
    hover = 'K',
    definition = 'gd',
    references = 'gr',
  }, opts.keybindings or {})

  log.debug('Container LSP Commands: Setting up keybindings for buffer %d: %s', bufnr, vim.inspect(bindings))

  -- Clear existing LSP keybindings to avoid conflicts
  M._clear_existing_lsp_keybindings(bufnr, bindings)

  -- Setup keybindings
  if bindings.hover then
    vim.keymap.set('n', bindings.hover, function()
      M.hover({ server_name = server_name })
    end, {
      buffer = bufnr,
      desc = 'Container LSP hover',
      silent = true,
      noremap = true,
    })
    log.debug('Container LSP Commands: Set %s -> hover for buffer %d', bindings.hover, bufnr)
  end

  if bindings.definition then
    vim.keymap.set('n', bindings.definition, function()
      M.definition({ server_name = server_name })
    end, {
      buffer = bufnr,
      desc = 'Container LSP go to definition',
      silent = true,
      noremap = true,
    })
    log.debug('Container LSP Commands: Set %s -> definition for buffer %d', bindings.definition, bufnr)
  end

  if bindings.references then
    vim.keymap.set('n', bindings.references, function()
      M.references({ server_name = server_name })
    end, {
      buffer = bufnr,
      desc = 'Container LSP find references',
      silent = true,
      noremap = true,
    })
    log.debug('Container LSP Commands: Set %s -> references for buffer %d', bindings.references, bufnr)
  end

  log.info('Container LSP Commands: Keybindings set up for buffer %d', bufnr)
  return true
end

-- Clear existing LSP keybindings to avoid conflicts
-- @param bufnr number: buffer number
-- @param bindings table: keybindings to clear
function M._clear_existing_lsp_keybindings(bufnr, bindings)
  local keys_to_clear = { bindings.hover, bindings.definition, bindings.references }

  for _, key in ipairs(keys_to_clear) do
    if key then
      -- Get existing keymap
      local existing_maps = vim.api.nvim_buf_get_keymap(bufnr, 'n')
      for _, map in ipairs(existing_maps) do
        if
          map.lhs == key and (map.desc and map.desc:match('LSP') or map.desc and map.desc:match('language server'))
        then
          -- Remove existing LSP mapping safely
          pcall(vim.keymap.del, 'n', key, { buffer = bufnr })
          log.debug('Container LSP Commands: Cleared existing %s mapping for buffer %d', key, bufnr)
        end
      end
    end
  end
end

-- Get module state (for debugging)
function M.get_state()
  return {
    initialized = state.initialized,
    registered_files = vim.tbl_keys(state.registered_files),
    transform_config = transform.get_config(),
  }
end

-- Clear all registered files
function M.clear_registered_files()
  state.registered_files = {}
  transform.clear_cache()
  log.info('Container LSP Commands: Cleared all registered files')
end

return M
