# LSP Dynamic Path Transformation Implementation

## Overview
This document describes the implementation of dynamic path transformation for container LSP integration in container.nvim.

## Implementation Summary

### Approach
We implemented a simplified version of Strategy C that focuses on practical functionality over theoretical elegance:
- Direct path transformation without complex message interception
- Automatic file registration and change tracking
- Seamless integration with Neovim's built-in LSP handlers

### Key Components

#### 1. Simple Transform Module (`lua/container/lsp/simple_transform.lua`)
- Provides bidirectional path transformation (host ↔ container)
- Caches transformed paths for performance
- Handles both file paths and URIs
- Supports transformation of LSP location objects

#### 2. LSP Commands Module (`lua/container/lsp/commands.lua`)
- Implements container-aware LSP commands (hover, definition, references)
- Automatic file registration with textDocument/didOpen
- Change tracking with textDocument/didChange and didSave
- Manages keybinding setup for Go buffers
- Provides both user commands and programmatic API

#### 3. Integration (`lua/container/lsp/init.lua`)
- Initializes commands module during LSP setup
- Automatically configures keybindings when gopls is detected
- Handles buffer attachment and lifecycle management

## Usage

### Automatic Setup
When container.nvim detects a container with gopls:
1. Automatically starts container_gopls client
2. Maps standard LSP keys for Go files:
   - `K` → Container hover
   - `gd` → Container go to definition
   - `gr` → Container find references

### Manual Commands
- `:ContainerLspHover [server]` - Show hover information
- `:ContainerLspDefinition [server]` - Go to definition
- `:ContainerLspReferences [server]` - Find references

### Path Transformation Example
```
Host:      /Users/ksoichiro/project/main.go
Container: /workspace/main.go
URI:       file:///workspace/main.go
```

## Technical Details

### File Registration Flow
1. User opens Go file
2. Plugin detects container_gopls client
3. Transforms host path to container path
4. Sends textDocument/didOpen notification
5. Tracks file in registered_files table

### Request Flow
1. User triggers LSP action (e.g., hover)
2. Command gets current buffer's container URI
3. Sends request with container path
4. Receives response with container paths
5. Transforms paths back to host format
6. Displays result using standard handlers

### Change Tracking
- TextChanged autocmd → textDocument/didChange
- BufWritePost autocmd → textDocument/didSave
- BufDelete autocmd → textDocument/didClose

## Advantages Over Complex Interception

1. **Simplicity**: No need to override LSP client methods
2. **Reliability**: Uses standard Neovim APIs
3. **Compatibility**: Works with other plugins
4. **Performance**: Minimal overhead
5. **Maintainability**: Easy to debug and extend

## Limitations

1. **Standard Library Navigation**: Cannot navigate to files outside container workspace
   - Workaround: Mount Go installation or use vendored dependencies

2. **Server Support**: Currently focused on gopls
   - Extension to other servers is straightforward

## Future Enhancements

1. Support for more language servers (pyright, tsserver, etc.)
2. Workspace symbol search across container boundaries
3. Integration with container file watchers
4. Multi-root workspace support

## Testing

Use `test_lsp_dynamic.lua` to verify:
- Path transformation correctness
- File registration status
- Command availability
- Keybinding setup

## Conclusion

This implementation proves that effective container LSP integration doesn't require complex message interception. By focusing on practical needs and leveraging Neovim's existing infrastructure, we achieved a robust solution that works reliably in production use.
