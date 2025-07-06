-- Container LSP with dynamic path transformation
-- This version uses dynamic paths instead of hardcoded ones

print('=== Container LSP Dynamic ===')

-- Load path transformation utility
local transform = require('container.lsp.simple_transform')

-- Initialize path transformation
transform.setup({
  host_workspace = vim.fn.getcwd(),
  container_workspace = '/workspace',
})

-- Get container_gopls client
local function get_container_client()
  local clients = vim.lsp.get_clients()
  for _, client in ipairs(clients) do
    if client.name == 'container_gopls' then
      return client
    end
  end
  return nil
end

local container_client = get_container_client()

if not container_client then
  print('❌ No container_gopls client found')
  return
end

print('✅ Found container_gopls (ID:', container_client.id .. ')')

-- Track registered files
local registered_files = {}

-- Register current file with container LSP
local function register_current_file()
  local bufnr = vim.api.nvim_get_current_buf()
  local file_path = vim.api.nvim_buf_get_name(bufnr)

  if file_path == '' then
    return false
  end

  -- Get container URI for current file
  local container_uri = transform.get_buffer_container_uri(bufnr)
  if not container_uri then
    return false
  end

  -- Skip if already registered
  if registered_files[container_uri] then
    return true
  end

  -- Get file content
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local text = table.concat(lines, '\n')

  -- Send didOpen notification
  container_client.notify('textDocument/didOpen', {
    textDocument = {
      uri = container_uri,
      languageId = 'go',
      version = 0,
      text = text,
    },
  })

  registered_files[container_uri] = true
  print('✅ Registered file:', container_uri)

  return true
end

-- Container hover using dynamic paths
vim.api.nvim_create_user_command('ContainerHover', function()
  if not register_current_file() then
    vim.notify('Failed to register current file', vim.log.levels.ERROR)
    return
  end

  local container_uri = transform.get_buffer_container_uri(0)
  if not container_uri then
    vim.notify('Cannot determine container path for current file', vim.log.levels.ERROR)
    return
  end

  local params = {
    textDocument = { uri = container_uri },
    position = vim.lsp.util.make_position_params(0, container_client.offset_encoding).position,
  }

  container_client.request('textDocument/hover', params, vim.lsp.handlers.hover, 0)
end, {})

-- Container definition with dynamic paths
vim.api.nvim_create_user_command('ContainerDefinition', function()
  if not register_current_file() then
    vim.notify('Failed to register current file', vim.log.levels.ERROR)
    return
  end

  local container_uri = transform.get_buffer_container_uri(0)
  if not container_uri then
    vim.notify('Cannot determine container path for current file', vim.log.levels.ERROR)
    return
  end

  local params = {
    textDocument = { uri = container_uri },
    position = vim.lsp.util.make_position_params(0, container_client.offset_encoding).position,
  }

  container_client.request('textDocument/definition', params, function(err, result, ctx)
    if err then
      vim.notify('Definition error: ' .. tostring(err), vim.log.levels.ERROR)
      return
    end

    if result then
      -- Transform container paths back to host paths
      local transformed_result = transform.transform_locations(result, 'to_host')

      -- Jump to location using vim.lsp.util
      if type(transformed_result) == 'table' then
        if transformed_result.uri then
          -- Single location
          vim.lsp.util.jump_to_location(transformed_result, container_client.offset_encoding)
        elseif #transformed_result > 0 then
          -- Multiple locations
          vim.lsp.util.jump_to_location(transformed_result[1], container_client.offset_encoding)
        else
          vim.notify('No definition found', vim.log.levels.INFO)
        end
      else
        vim.notify('No definition found', vim.log.levels.INFO)
      end
    else
      vim.notify('No definition found', vim.log.levels.INFO)
    end
  end, 0)
end, {})

-- Container references with dynamic paths
vim.api.nvim_create_user_command('ContainerReferences', function()
  if not register_current_file() then
    vim.notify('Failed to register current file', vim.log.levels.ERROR)
    return
  end

  local container_uri = transform.get_buffer_container_uri(0)
  if not container_uri then
    vim.notify('Cannot determine container path for current file', vim.log.levels.ERROR)
    return
  end

  local params = {
    textDocument = { uri = container_uri },
    position = vim.lsp.util.make_position_params(0, container_client.offset_encoding).position,
    context = { includeDeclaration = true },
  }

  container_client.request('textDocument/references', params, function(err, result, ctx)
    if err then
      vim.notify('References error: ' .. tostring(err), vim.log.levels.ERROR)
      return
    end

    if result and #result > 0 then
      -- Transform all reference locations
      local transformed_refs = transform.transform_locations(result, 'to_host')

      -- Set quickfix list
      local items = vim.lsp.util.locations_to_items(transformed_refs, container_client.offset_encoding)
      vim.fn.setqflist({}, ' ', { title = 'References', items = items })
      vim.cmd('copen')
    else
      vim.notify('No references found', vim.log.levels.INFO)
    end
  end, 0)
end, {})

-- Auto-register files on buffer enter
vim.api.nvim_create_autocmd({ 'BufEnter', 'BufNewFile' }, {
  pattern = '*.go',
  callback = function()
    -- Wait a bit to ensure container_client is available
    vim.defer_fn(function()
      local client = get_container_client()
      if client then
        container_client = client
        register_current_file()
      end
    end, 100)
  end,
})

-- Create convenient functions
_G.container_lsp = {
  hover = function()
    vim.cmd('ContainerHover')
  end,
  definition = function()
    vim.cmd('ContainerDefinition')
  end,
  references = function()
    vim.cmd('ContainerReferences')
  end,
  register_file = register_current_file,
}

-- Set up keymaps (you can customize these)
vim.keymap.set('n', '<leader>K', container_lsp.hover, {
  buffer = 0,
  desc = 'Container LSP hover',
  silent = true,
})

vim.keymap.set('n', '<leader>gd', container_lsp.definition, {
  buffer = 0,
  desc = 'Container LSP definition',
  silent = true,
})

vim.keymap.set('n', '<leader>gr', container_lsp.references, {
  buffer = 0,
  desc = 'Container LSP references',
  silent = true,
})

print('✅ Container LSP commands ready (dynamic version)')
print('\nCommands:')
print('- :ContainerHover')
print('- :ContainerDefinition')
print('- :ContainerReferences')
print('\nFeatures:')
print('- Dynamic path transformation')
print('- Automatic file registration')
print('- Multi-file support')
print('\nCurrent file:', vim.fn.expand('%:p'))
print('Container path:', transform.get_buffer_container_uri(0) or 'N/A')

-- Register current file automatically
vim.defer_fn(function()
  if vim.bo.filetype == 'go' then
    register_current_file()
  end
end, 200)
