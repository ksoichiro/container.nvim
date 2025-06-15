# LSP Integration - Quick Test Procedure

This document outlines the procedure for testing the fixed LSP integration functionality.

## Prerequisites
- Docker is running
- Neovim (0.8+) is installed
- nvim-lspconfig plugin is installed

## Step 1: Plugin Initialization Test

### Load plugin in Neovim
```lua
-- Execute within Neovim
require('devcontainer').setup({
  log_level = 'debug',
  lsp = {
    auto_setup = true,
    timeout = 10000
  }
})
```

### Initialization Confirmation
```vim
:DevcontainerDebug
```

Expected output:
```
=== DevContainer Debug Info ===
Initialized: true
Current container: none
Current config: none
```

## Step 2: LSP Status Check (No Container)

```vim
:DevcontainerLspStatus
```

Expected output:
```
=== DevContainer LSP Status ===
Container ID: none
Auto setup: true
No servers detected (container may not be running)
No active LSP clients
```

## Step 3: Testing with Python Example

### Navigate to Python example directory
```bash
cd examples/python-example
nvim main.py
```

### Start devcontainer
```vim
:DevcontainerOpen
:DevcontainerStart
```

### Re-check LSP status
```vim
:DevcontainerLspStatus
```

Expected behavior:
- Container ID is displayed
- Python-related LSP servers are detected
- Auto setup is executed

## Step 4: LSP Functionality Test

### Code Completion Test
1. Open `main.py`
2. Type `calc.` on a new line
3. Check completion candidates with `<C-x><C-o>`

### Definition Jump Test
1. Place cursor on `hello_world` in `hello_world("test")`
2. Verify you can jump to definition with `gd`

### Hover Information Test
1. Place cursor on a function name
2. Verify documentation is displayed with `K`

## Troubleshooting

### Error 1: "LSP not initialized"
**Solution:**
```vim
:lua require('devcontainer').setup({log_level = 'debug'})
:DevcontainerLspStatus
```

### Error 2: "No active container"
**Solution:**
```vim
:DevcontainerStart
:DevcontainerLspSetup
```

### Error 3: LSP server not detected
**Solution:**
```vim
:DevcontainerExec which pylsp
:DevcontainerExec python -m pip install python-lsp-server
:DevcontainerLspSetup
```

### Error 4: Path conversion issues
**Solution:**
```vim
:lua print(vim.inspect(require('devcontainer.lsp.path').get_mappings()))
```

## Debug Commands

### Check detailed logs
```vim
:messages
:DevcontainerLogs
```

### Manual LSP restart
```vim
:DevcontainerLspSetup
:LspRestart
```

### Check Docker information
```vim
:DevcontainerExec ps aux
:DevcontainerStatus
```

## Expected Final State

When everything is working correctly:

1. `:DevcontainerLspStatus` displays the following:
   ```
   === DevContainer LSP Status ===
   Container ID: <container_id>
   Auto setup: true
   Detected servers:
     pylsp: pylsp (available: true)
   Active clients:
     pylsp
   ```

2. `:LspInfo` shows the pylsp client

3. LSP features (completion, diagnostics, definition jump) work in Python files

## Minimal Test

Minimal test when time is limited:

```vim
:lua require('devcontainer').setup()
:DevcontainerDebug
:cd examples/python-example
:DevcontainerStart
:DevcontainerLspStatus
:edit main.py
```

If `K` (hover) works in main.py, the basic integration is successful.