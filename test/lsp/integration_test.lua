-- Integration test for LSP commands in container environment
-- This script verifies that the LSP integration works end-to-end

print('=== Container LSP Integration Test ===')

-- Step 1: Check if container.nvim is loaded
local container_ok, container = pcall(require, 'container')
if not container_ok then
  print('❌ container.nvim not loaded:', container)
  return
end

-- Step 2: Check container state
local state = container.get_state()
print('Container ID:', state.current_container or 'none')
print('Container Status:', state.container_status or 'unknown')

if not state.current_container then
  print('⚠️  No container running. Starting container setup...')
  print('   Run :ContainerStart to start a container')
  return
end

-- Step 3: Check LSP module
local lsp_ok, lsp = pcall(require, 'container.lsp.init')
if not lsp_ok then
  print('❌ LSP module not loaded:', lsp)
  return
end

print('✅ LSP module loaded')

-- Step 4: Check LSP commands module
local commands_ok, commands = pcall(require, 'container.lsp.commands')
if not commands_ok then
  print('❌ LSP commands module not loaded:', commands)
  return
end

print('✅ LSP commands module loaded')

-- Step 5: Check LSP clients
local clients = vim.lsp.get_clients and vim.lsp.get_clients() or vim.lsp.get_active_clients()
local container_gopls = nil

for _, client in ipairs(clients) do
  if client.name == 'container_gopls' then
    container_gopls = client
    break
  end
end

if container_gopls then
  print('✅ container_gopls found (ID:', container_gopls.id .. ')')
  print('   Initialized:', container_gopls.initialized)
  print('   Stopped:', container_gopls.is_stopped())
else
  print('⚠️  container_gopls not found')
  print('   Available clients:')
  for _, client in ipairs(clients) do
    print('   -', client.name, '(ID:', client.id .. ')')
  end
  print('   Note: container_gopls may start automatically when you open a Go file')
end

-- Step 6: Check current file
local current_file = vim.fn.expand('%:p')
local current_ft = vim.bo.filetype

print('\nCurrent file:', current_file)
print('File type:', current_ft)

if current_ft == 'go' and container_gopls then
  -- Step 7: Check file registration
  local cmd_state = commands.get_state()
  print('\nLSP commands state:')
  print('  Initialized:', cmd_state.initialized)
  print('  Registered files:', #cmd_state.registered_files)

  -- Step 8: Test path transformation
  local transform = require('container.lsp.simple_transform')
  local container_uri = transform.get_buffer_container_uri(0)
  print('  Current file container URI:', container_uri or 'N/A')

  -- Step 9: Check keybindings
  print('\nChecking keybindings:')
  local keymaps = vim.api.nvim_buf_get_keymap(0, 'n')
  local lsp_keys = {
    ['K'] = 'hover',
    ['gd'] = 'definition',
    ['gr'] = 'references',
  }

  for key, action in pairs(lsp_keys) do
    local found = false
    for _, map in ipairs(keymaps) do
      if map.lhs == key and map.desc and map.desc:match('Container LSP') then
        found = true
        break
      end
    end
    print('  ' .. key .. ' (' .. action .. '):', found and '✅ mapped' or '⚠️  not mapped')
  end

  -- Step 10: Test basic functionality
  print('\n=== Functionality Test ===')

  -- Test file registration
  local registration_success = commands.register_file(0, container_gopls)
  print('File registration:', registration_success and '✅ success' or '❌ failed')

  if registration_success then
    print('\n🎉 Integration test passed!')
    print('\nNext steps:')
    print('1. Position cursor on a Go symbol')
    print('2. Test hover: K or :ContainerLspHover')
    print('3. Test definition: gd or :ContainerLspDefinition')
    print('4. Test references: gr or :ContainerLspReferences')
  end
elseif current_ft ~= 'go' then
  print('⚠️  Open a Go file to test LSP functionality')
else
  print('⚠️  container_gopls not available for testing')
end

-- Step 11: Check user commands
print('\n=== User Commands Test ===')
local user_commands = {
  'ContainerLspHover',
  'ContainerLspDefinition',
  'ContainerLspReferences',
}

for _, cmd in ipairs(user_commands) do
  local exists = vim.fn.exists(':' .. cmd) == 2
  print(':' .. cmd, exists and '✅ available' or '❌ missing')
end

print('\n=== Integration Test Complete ===')

-- Step 12: Provide troubleshooting info
if not container_gopls or current_ft ~= 'go' then
  print('\n=== Troubleshooting ===')
  print('If LSP is not working:')
  print('1. Ensure container is running: :ContainerStatus')
  print('2. Check if gopls is installed in container:')
  print('   :ContainerExec which gopls')
  print('3. Open a Go file and wait a moment for auto-setup')
  print('4. Check LSP status: :LspInfo')
  print('5. Force restart LSP: :LspRestart')
end
