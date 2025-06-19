# container.nvim LSP Integration Testing Guide

This guide explains how to test the LSP integration functionality implemented in v0.2.0.

## Prerequisites

### Required Tools
- Docker or Podman
- Neovim (0.8+)
- nvim-lspconfig plugin
- Lazy.nvim or other plugin manager

### Plugin Setup
```lua
-- For Lazy.nvim
{
  dir = "/path/to/container.nvim", -- Local path
  dependencies = {
    "neovim/nvim-lspconfig",
  },
  config = function()
    require('container').setup({
      log_level = 'debug', -- For debugging
      lsp = {
        auto_setup = true,
        timeout = 10000, -- Set longer for testing
      }
    })
  end,
}
```

## Test Procedure

### 1. Basic Operation Verification

#### Step 1: Plugin Initialization Verification
```vim
:ContainerDebug
```
- Verify plugin is properly initialized
- Verify configuration is loaded correctly

#### Step 2: Docker Verification
```bash
docker --version
docker ps
```

### 2. Python LSP Test

#### Step 1: Navigate to Python Example
```bash
cd examples/python-example
nvim main.py
```

#### Step 2: Start devcontainer
```vim
:ContainerOpen
:ContainerStart
```

#### Step 3: LSP Status Check
```vim
:ContainerLspStatus
```
Expected output:
```
=== DevContainer LSP Status ===
Container ID: <container_id>
Auto setup: true
Detected servers:
  pylsp: pylsp (available: true)
Active clients:
  pylsp
```

#### Step 4: LSP Functionality Test

1. **Code Completion Test**
   - Open `main.py`
   - Type `calc.` on a new line
   - Verify completion candidates are displayed with `<C-x><C-o>` or completion plugin

2. **Definition Jump Test**
   - Place cursor on `hello_world` in `hello_world("test")`
   - Verify you can jump to definition with `gd` or `:lua vim.lsp.buf.definition()`

3. **Diagnostics Test**
   - Intentionally create a syntax error (e.g., `print("test"`)
   - Verify diagnostic messages are displayed

4. **Hover Information Test**
   - Place cursor on a function name
   - Verify documentation is displayed with `K` or `:lua vim.lsp.buf.hover()`

### 3. Node.js LSP Test

#### Step 1: Navigate to Node.js Example
```bash
cd examples/node-example
nvim index.js
```

#### Step 2: Start devcontainer
```vim
:ContainerOpen
:ContainerStart
```

#### Step 3: Run similar LSP tests
- Code completion
- Definition jump
- Diagnostics
- Hover information

### 4. Manual Test Script

You can run automated tests with the following script:

#### Test Lua Script
```lua
-- test_lsp.lua
local function test_lsp_integration()
  print("=== LSP Integration Test ===")

  -- 1. Basic functionality test
  local devcontainer = require('container')

  -- Check if plugin is initialized
  local debug_info = devcontainer.debug_info()

  -- 2. LSP status test
  local lsp_status = devcontainer.lsp_status()
  if not lsp_status then
    print("ERROR: LSP not initialized")
    return false
  end

  -- 3. Check active LSP clients
  local clients = vim.lsp.get_active_clients()
  print("Active LSP clients: " .. #clients)
  for _, client in ipairs(clients) do
    print("  - " .. client.name)
  end

  -- 4. Test path conversion
  local lsp_path = require('devcontainer.lsp.path')
  local test_path = vim.fn.expand('%:p')
  local container_path = lsp_path.to_container_path(test_path)
  local back_to_local = lsp_path.to_local_path(container_path)

  print("Path conversion test:")
  print("  Local: " .. test_path)
  print("  Container: " .. (container_path or "nil"))
  print("  Back to local: " .. (back_to_local or "nil"))

  return true
end

test_lsp_integration()
```

#### Execution Method
```vim
:luafile test_lsp.lua
```

### 5. Troubleshooting

#### Common Issues and Solutions

1. **LSP server not detected**
   ```vim
   :ContainerExec which pylsp
   :ContainerExec python -m pylsp --help
   ```

2. **Communication errors**
   ```vim
   :ContainerLogs
   :messages
   ```

3. **Path conversion issues**
   ```vim
   :lua print(require('devcontainer.lsp.path').get_mappings())
   ```

4. **Manual LSP setup**
   ```vim
   :ContainerLspSetup
   ```

#### Check logs
```vim
:ContainerLogs
:lua require('devcontainer.utils.log').show_logs()
```

### 6. Debug Commands

```vim
" Detailed debug information
:ContainerDebug

" LSP-specific status
:ContainerLspStatus

" Execute commands in container
:ContainerExec ps aux | grep lsp

" Manual LSP restart
:LspRestart

" Display LSP information
:LspInfo
```

### 7. Expected Behavior

When working correctly:
- LSP servers are automatically detected and started after `:ContainerStart`
- All standard Neovim LSP functionality works
- File paths are correctly converted between local ⇔ container
- Diagnostics, completion, definition jump, etc. all function

### 8. Performance Testing

Testing with large projects:
```bash
# Clone a large Python project
git clone https://github.com/psf/requests.git
cd requests
# Create .devcontainer/devcontainer.json
nvim
:ContainerStart
# Test LSP response speed
```

Follow this testing guide to verify the LSP integration functionality. If issues occur, check the logs and adjust configuration as needed.
