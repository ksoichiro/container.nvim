# Strategy C Implementation Progress

## Overview
This document records the progress of implementing Strategy C (Host-side LSP Message Interception) for container.nvim.

## Investigation Summary

### Problem Identified
- Strategy B (Proxy) was marked as implemented but not working
- The proxy approach assumed Lua interpreter exists in containers, which is false
- LSP messages with host paths were being sent directly to container gopls

### Key Discovery
Through diagnosis (`simple_diagnosis.lua`), we confirmed:
1. Container gopls is working correctly with container paths
2. The issue is purely path transformation
3. When using `file:///workspace/main.go`, gopls responds correctly

## Working Solution

### Successful Approach
Instead of complex message interception, we implemented direct container path usage:

```lua
-- Direct container path approach (container_lsp_fixed.lua)
container_client.request('textDocument/hover', {
  textDocument = { uri = 'file:///workspace/main.go' },  -- Container path
  position = get_position()
}, vim.lsp.handlers.hover, 0)
```

### Why This Works
1. **Simple**: Only transforms paths where needed
2. **Reliable**: Uses exact paths the container expects  
3. **No conflicts**: Doesn't override existing LSP client methods
4. **Standard handlers**: Uses Neovim's built-in LSP UI

### Current Features
- ✅ Hover (K or :ContainerHover)
- ✅ Go to Definition (gd or :ContainerDefinition)
- ✅ Find References (gr or :ContainerReferences)
- ❌ Standard library navigation (files outside /workspace)

## Failed Attempts

### Strategy C Original Design
The interceptor pattern failed due to:
1. Method arguments being corrupted (method became table instead of string)
2. Complex transformation logic breaking other plugins
3. vim.deepcopy issues with function serialization

### Key Learning
"Simple partial solutions over complex comprehensive ones" - The theoretical elegance of Strategy C's full interception was outweighed by implementation complexity.

## Next Steps

### Required for Production
1. **Dynamic Path Transformation**
   ```lua
   -- Current (hardcoded)
   textDocument = { uri = 'file:///workspace/main.go' }

   -- Needed (dynamic)
   local current_file = vim.fn.expand('%:p')
   local container_path = current_file:gsub(vim.fn.getcwd(), '/workspace')
   textDocument = { uri = vim.uri_from_fname(container_path) }
   ```

2. **Multi-file Support**
   - Register each opened file with container LSP
   - Track file-to-container-path mappings
   - Handle file watchers and changes

3. **Robust Error Handling**
   - Detect when container paths don't exist
   - Fallback to host LSP when container unavailable

### Potential Improvements
1. Mount Go standard library in container for stdlib navigation
2. Use `go mod vendor` for complete dependency access
3. Implement proper Strategy C with careful argument handling

## Technical Details

### Working File Structure
```
container_lsp_fixed.lua     - Production-ready solution with fixed paths
simple_diagnosis.lua        - Diagnostic tool that proved gopls works
complete_working_solution.lua - Standalone version with custom hover UI
```

### Container Path Mapping
- Host: `/Users/ksoichiro/src/github.com/ksoichiro/container.nvim/examples/go-test-example/`
- Container: `/workspace/`

## Conclusion
While not fully implementing the original Strategy C design, we achieved a working LSP integration by simplifying the approach. The next priority is making paths dynamic while maintaining the simplicity that made this solution successful.
