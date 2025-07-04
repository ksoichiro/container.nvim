-- Container LSP with fixed handlers

print("=== Container LSP Fixed ===")

-- Get container_gopls client
local clients = vim.lsp.get_clients()
local container_client = nil

for _, client in ipairs(clients) do
  if client.name == 'container_gopls' then
    container_client = client
    break
  end
end

if not container_client then
  print("❌ No container_gopls client found")
  return
end

print("✅ Found container_gopls (ID:", container_client.id .. ")")

-- Register file with container path
container_client.notify('textDocument/didOpen', {
  textDocument = {
    uri = 'file:///workspace/main.go',
    languageId = 'go',
    version = 0,
    text = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n')
  }
})

-- Container hover using standard handler
vim.api.nvim_create_user_command('ContainerHover', function()
  local params = {
    textDocument = { uri = 'file:///workspace/main.go' },
    position = vim.lsp.util.make_position_params(0, container_client.offset_encoding).position
  }

  container_client.request('textDocument/hover', params, vim.lsp.handlers.hover, 0)
end, {})

-- Container definition with proper handling
vim.api.nvim_create_user_command('ContainerDefinition', function()
  local params = {
    textDocument = { uri = 'file:///workspace/main.go' },
    position = vim.lsp.util.make_position_params(0, container_client.offset_encoding).position
  }

  container_client.request('textDocument/definition', params, function(err, result, ctx)
    if err then
      vim.notify("Definition error: " .. tostring(err), vim.log.levels.ERROR)
      return
    end

    if result then
      -- Transform container paths back to host paths
      local locations = {}

      if type(result) == 'table' then
        if result.uri then
          -- Single location
          result.uri = result.uri:gsub('file:///workspace', 'file://' .. vim.fn.getcwd())
          locations = { result }
        elseif #result > 0 then
          -- Array of locations
          for _, loc in ipairs(result) do
            if loc.uri then
              loc.uri = loc.uri:gsub('file:///workspace', 'file://' .. vim.fn.getcwd())
            end
          end
          locations = result
        end
      end

      -- Jump to location using vim.lsp.util
      if #locations > 0 then
        vim.lsp.util.jump_to_location(locations[1], container_client.offset_encoding)
      else
        vim.notify("No definition found", vim.log.levels.INFO)
      end
    else
      vim.notify("No definition found", vim.log.levels.INFO)
    end
  end, 0)
end, {})

-- Container references with proper handling
vim.api.nvim_create_user_command('ContainerReferences', function()
  local params = {
    textDocument = { uri = 'file:///workspace/main.go' },
    position = vim.lsp.util.make_position_params(0, container_client.offset_encoding).position,
    context = { includeDeclaration = true }
  }

  container_client.request('textDocument/references', params, function(err, result, ctx)
    if err then
      vim.notify("References error: " .. tostring(err), vim.log.levels.ERROR)
      return
    end

    if result and #result > 0 then
      -- Transform paths
      for _, ref in ipairs(result) do
        if ref.uri then
          ref.uri = ref.uri:gsub('file:///workspace', 'file://' .. vim.fn.getcwd())
        end
      end

      -- Set quickfix list
      local items = vim.lsp.util.locations_to_items(result, container_client.offset_encoding)
      vim.fn.setqflist({}, ' ', { title = 'References', items = items })
      vim.cmd('copen')
    else
      vim.notify("No references found", vim.log.levels.INFO)
    end
  end, 0)
end, {})

-- Create convenient functions
_G.container_lsp = {
  hover = function() vim.cmd('ContainerHover') end,
  definition = function() vim.cmd('ContainerDefinition') end,
  references = function() vim.cmd('ContainerReferences') end,
}

-- Set up keymaps (you can customize these)
vim.keymap.set('n', '<leader>K', container_lsp.hover, {
  buffer = 0,
  desc = 'Container LSP hover',
  silent = true
})

vim.keymap.set('n', '<leader>gd', container_lsp.definition, {
  buffer = 0,
  desc = 'Container LSP definition',
  silent = true
})

vim.keymap.set('n', '<leader>gr', container_lsp.references, {
  buffer = 0,
  desc = 'Container LSP references',
  silent = true
})

print("✅ Container LSP commands ready")
print("\nCommands:")
print("- :ContainerHover")
print("- :ContainerDefinition")
print("- :ContainerReferences")
print("\nKeybindings:")
print("- <leader>K  : Hover")
print("- <leader>gd : Go to definition")
print("- <leader>gr : Find references")
print("\nOr override default keys in your config:")
print("vim.keymap.set('n', 'K', container_lsp.hover)")
print("vim.keymap.set('n', 'gd', container_lsp.definition)")

-- Test
vim.defer_fn(function()
  print("\nTesting hover on 'NewCalculator'...")
  vim.api.nvim_win_set_cursor(0, { 11, 5 })
  container_lsp.hover()
end, 500)
