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

  client.request('textDocument/hover', params, vim.lsp.handlers.hover, 0)
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

  log.info('Container LSP Commands: User commands created')
end

-- Setup keybindings
-- @param opts table: keybinding options
function M.setup_keybindings(opts)
  opts = opts or {}
  local server_name = opts.server_name or 'gopls'

  -- Default keybindings (can be overridden)
  local bindings = vim.tbl_extend('force', {
    hover = 'K',
    definition = 'gd',
    references = 'gr',
  }, opts.keybindings or {})

  -- Setup keybindings
  if bindings.hover then
    vim.keymap.set('n', bindings.hover, function()
      M.hover({ server_name = server_name })
    end, {
      buffer = opts.buffer,
      desc = 'Container LSP hover',
      silent = true,
    })
  end

  if bindings.definition then
    vim.keymap.set('n', bindings.definition, function()
      M.definition({ server_name = server_name })
    end, {
      buffer = opts.buffer,
      desc = 'Container LSP go to definition',
      silent = true,
    })
  end

  if bindings.references then
    vim.keymap.set('n', bindings.references, function()
      M.references({ server_name = server_name })
    end, {
      buffer = opts.buffer,
      desc = 'Container LSP find references',
      silent = true,
    })
  end

  log.info('Container LSP Commands: Keybindings set up')
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
