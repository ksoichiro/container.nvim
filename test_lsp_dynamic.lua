-- Test script for dynamic LSP path transformation
-- This script tests the integrated LSP commands module

print("=== Testing Dynamic Container LSP ===")

-- Get current container state
local container = require('container')
local state = container.get_state()

print("Container ID:", state.current_container or "none")
print("Container status:", state.container_status or "unknown")

if not state.current_container then
  print("❌ No container running. Please start a container first.")
  print("   Run: :ContainerStart")
  return
end

-- Check if container_gopls is running
local clients = vim.lsp.get_clients and vim.lsp.get_clients() or vim.lsp.get_active_clients()
local container_gopls = nil

for _, client in ipairs(clients) do
  if client.name == 'container_gopls' then
    container_gopls = client
    break
  end
end

if not container_gopls then
  print("❌ container_gopls not found. LSP auto-setup may have failed.")
  print("   Try reopening a Go file or run :LspInfo")
  return
end

print("✅ Found container_gopls (ID:", container_gopls.id .. ")")
print("   Initialized:", container_gopls.initialized)

-- Load LSP commands module
local commands_ok, commands = pcall(require, 'container.lsp.commands')
if not commands_ok then
  print("❌ Failed to load LSP commands module:", commands)
  return
end

print("✅ LSP commands module loaded")

-- Get module state
local cmd_state = commands.get_state()
print("\nModule state:")
print("  Initialized:", cmd_state.initialized)
print("  Registered files:", #cmd_state.registered_files)
for i, file in ipairs(cmd_state.registered_files) do
  print("    " .. i .. ":", file)
end

-- Test with current file
local current_file = vim.fn.expand('%:p')
local current_ft = vim.bo.filetype

print("\nCurrent file:", current_file)
print("File type:", current_ft)

if current_ft ~= 'go' then
  print("⚠️  Current file is not a Go file. Open a Go file to test LSP commands.")
  return
end

-- Get path transformation info
local transform = require('container.lsp.simple_transform')
local transform_config = transform.get_config()
print("\nPath transformation config:")
print("  Host workspace:", transform_config.host_workspace)
print("  Container workspace:", transform_config.container_workspace)

local container_uri = transform.get_buffer_container_uri(0)
print("  Current file container URI:", container_uri or "N/A")

-- Test commands availability
print("\n=== Testing LSP Commands ===")

-- Check if commands are defined
print("\nAvailable user commands:")
local user_commands = {
  'ContainerLspHover',
  'ContainerLspDefinition',
  'ContainerLspReferences'
}

for _, cmd in ipairs(user_commands) do
  local exists = vim.fn.exists(':' .. cmd) == 2
  print("  :" .. cmd, exists and "✅" or "❌")
end

-- Test keybindings
print("\nChecking keybindings:")
local keymaps = vim.api.nvim_buf_get_keymap(0, 'n')
local lsp_keys = {
  ['K'] = 'hover',
  ['gd'] = 'definition',
  ['gr'] = 'references'
}

for key, action in pairs(lsp_keys) do
  local found = false
  for _, map in ipairs(keymaps) do
    if map.lhs == key and map.desc and map.desc:match('Container LSP') then
      found = true
      break
    end
  end
  print("  " .. key .. " (" .. action .. "):", found and "✅ mapped" or "⚠️  not mapped")
end

-- Instructions for manual testing
print("\n=== Manual Test Instructions ===")
print("1. Position cursor on a Go symbol (e.g., 'fmt' in 'fmt.Println')")
print("2. Test hover:")
print("   - Press K (if mapped) or run :ContainerLspHover")
print("   - You should see hover information")
print("3. Test go to definition:")
print("   - Press gd (if mapped) or run :ContainerLspDefinition")
print("   - Should jump to symbol definition")
print("4. Test find references:")
print("   - Press gr (if mapped) or run :ContainerLspReferences")
print("   - Should open quickfix with references")
print("\n5. Test with multiple files:")
print("   - Open another Go file in the same project")
print("   - Commands should work automatically")
print("\n6. Check registered files:")
print("   :lua require('container.lsp.commands').get_state()")

-- Quick function test
print("\n=== Quick Function Test ===")
vim.defer_fn(function()
  local test_file = "/workspace/main.go"
  print("Testing path transformation for:", test_file)

  local host_path = transform.container_to_host(test_file)
  print("  Container -> Host:", host_path)

  local back_to_container = transform.host_to_container(host_path)
  print("  Host -> Container:", back_to_container)

  print("  Round-trip success:", test_file == back_to_container and "✅" or "❌")
end, 100)

print("\n✅ Test setup complete. Follow the manual test instructions above.")
