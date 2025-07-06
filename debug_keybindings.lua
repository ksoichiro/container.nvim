-- Debug script to check keybinding status
print('=== LSP Keybinding Debug ===')

-- 1. Check current buffer
local bufnr = vim.api.nvim_get_current_buf()
local ft = vim.bo[bufnr].filetype
print('Current buffer:', bufnr)
print('File type:', ft)
print('File name:', vim.api.nvim_buf_get_name(bufnr))

-- 2. Check LSP clients for this buffer
local clients = vim.lsp.get_clients and vim.lsp.get_clients({ bufnr = bufnr }) or vim.lsp.get_active_clients()
print('\nLSP clients for buffer ' .. bufnr .. ':')
local has_container_gopls = false
for _, client in ipairs(clients) do
  print('  -', client.name, '(ID:', client.id .. ')')
  if client.name == 'container_gopls' then
    has_container_gopls = true
  end
end
print('Has container_gopls:', has_container_gopls)

-- 3. Check current keybindings
print('\nCurrent keybindings for this buffer:')
local keymaps = vim.api.nvim_buf_get_keymap(bufnr, 'n')
local lsp_keys = { 'K', 'gd', 'gr' }

for _, key in ipairs(lsp_keys) do
  local found = false
  local desc = 'none'
  for _, map in ipairs(keymaps) do
    if map.lhs == key then
      found = true
      desc = map.desc or 'no description'
      print('  ' .. key .. ':', desc)
      break
    end
  end
  if not found then
    print('  ' .. key .. ': not mapped')
  end
end

-- 4. Check LSP commands module status
local commands_ok, commands = pcall(require, 'container.lsp.commands')
if commands_ok then
  local cmd_state = commands.get_state()
  print('\nLSP commands module:')
  print('  Initialized:', cmd_state.initialized)
  print('  Registered files:', #cmd_state.registered_files)
else
  print('\nLSP commands module: not loaded')
end

-- 5. Check user commands
print('\nUser commands:')
local user_commands = { 'ContainerLspHover', 'ContainerLspDefinition', 'ContainerLspReferences' }
for _, cmd in ipairs(user_commands) do
  local exists = vim.fn.exists(':' .. cmd) == 2
  print('  :' .. cmd, exists and 'available' or 'missing')
end

-- 6. Manual keybinding test
print('\n=== Manual Setup Test ===')
if ft == 'go' and commands_ok then
  print('Attempting manual keybinding setup...')

  -- Manual setup with debugging
  local setup_success = pcall(function()
    commands.setup_keybindings({
      buffer = bufnr,
      server_name = 'gopls',
      keybindings = {
        hover = 'K',
        definition = 'gd',
        references = 'gr'
      }
    })
  end)

  print('Manual setup result:', setup_success and 'success' or 'failed')

  -- Check again
  vim.defer_fn(function()
    print('\nAfter manual setup:')
    local new_keymaps = vim.api.nvim_buf_get_keymap(bufnr, 'n')
    for _, key in ipairs(lsp_keys) do
      for _, map in ipairs(new_keymaps) do
        if map.lhs == key then
          print('  ' .. key .. ':', map.desc or 'no description')
          break
        end
      end
    end
  end, 100)
end

-- 7. Recommendations
print('\n=== Recommendations ===')
if not has_container_gopls then
  print('1. container_gopls client not found. Check if:')
  print('   - Container is running (:ContainerStatus)')
  print('   - gopls is installed in container (:ContainerExec which gopls)')
  print('   - LSP auto-setup is working (:LspInfo)')
elseif ft ~= 'go' then
  print('1. Open a Go file to test Go LSP functionality')
else
  print('1. Try manual command first: :ContainerLspHover')
  print('2. If that works, try manual keybinding setup: :ContainerLspSetupKeys')
  print('3. Check if keybindings are now working (K, gd, gr)')
  print('4. If still not working, try reloading the file: :e')
  print('5. Check Neovim LSP logs: :LspLog')
end

print('\n=== Quick Fix ===')
print('To manually setup keybindings right now:')
print('  :ContainerLspSetupKeys')
print('Then test:')
print('  K (hover), gd (definition), gr (references)')
