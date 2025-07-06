# LSP Integration Tests

This directory contains test files for the LSP integration functionality.

## Test Files

### Integration Tests
- **`integration_test.lua`** - Comprehensive end-to-end test for LSP integration
  - Verifies container state
  - Checks LSP client status
  - Tests path transformation
  - Validates keybindings
  - Provides troubleshooting information

### Dynamic Implementation Tests
- **`test_lsp_dynamic.lua`** - Test script for dynamic path transformation
  - Tests dynamic path transformation functionality
  - Verifies file registration
  - Checks module state
  - Tests round-trip path conversion

### Legacy/Archive Tests
- **`container_lsp_dynamic.lua`** - Dynamic LSP implementation (standalone version)
- **`container_lsp_fixed.lua`** - Original fixed-path implementation (proof-of-concept)
- **`simple_diagnosis.lua`** - Simple diagnostic tool (if present)

## Running Tests

### Quick Integration Test
```vim
:source test/lsp/integration_test.lua
```

### Dynamic Functionality Test
```vim
:source test/lsp/test_lsp_dynamic.lua
```

### Manual Testing
1. Open a Go file in a container project
2. Run integration test to verify setup
3. Test LSP commands:
   - `K` - Hover
   - `gd` - Go to definition
   - `gr` - Find references

## Prerequisites

1. **Container Running**: Use `:ContainerStart` to start a container
2. **Go Files**: Open `.go` files to trigger LSP auto-setup
3. **gopls Available**: Ensure gopls is installed in the container

## Troubleshooting

If tests fail:

1. **Check Container Status**:
   ```vim
   :ContainerStatus
   ```

2. **Verify gopls Installation**:
   ```vim
   :ContainerExec which gopls
   ```

3. **Check LSP Clients**:
   ```vim
   :LspInfo
   ```

4. **Review Logs**:
   ```vim
   :ContainerLogs
   ```

## Expected Behavior

- **Automatic Setup**: LSP should start automatically when opening Go files
- **Path Transformation**: Paths should be converted between host and container
- **Standard Keybindings**: K, gd, gr should work with container LSP
- **Multi-file Support**: Multiple Go files should work seamlessly

## Implementation Notes

The current implementation uses a simplified approach:
- Direct path transformation without complex message interception
- Automatic file registration with textDocument/didOpen
- Integration with Neovim's standard LSP handlers
- Dynamic keybinding setup for Go buffers

This approach avoids the complexity of full Strategy C while providing reliable functionality.
