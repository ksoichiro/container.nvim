# devcontainer.nvim TODO & Improvements

This file records future improvements and plans after the completion of v0.2.0 LSP integration.

## Current Status (v0.2.0 Complete)

✅ **Completed**
- Basic devcontainer operations (v0.1.0)
- LSP integration features (v0.2.0)
  - Automatic LSP server detection in Docker
  - Asynchronous Docker operations
  - Path conversion functionality
  - Reconnection capability

## Critical Issues Requiring Immediate Fixes

### ✅ Fixes Completed

1. **Container Naming Conflicts** ✅
   - Fixed: Container names now include project path hash for uniqueness
   - Implementation: `name-hash-devcontainer` format using SHA256 of project path
   - Impact: Multiple projects with same devcontainer name can coexist
   - Testing: Comprehensive test suite added (test/test_container_naming.lua)

### 🔴 High Priority

2. **LSP Info Client Display Issue**
   - Current: devcontainer pylsp client not shown in `:LspInfo`
   - Impact: Difficult to verify status during debugging (though functionality works normally)
   - Priority: Medium (minimal practical impact)
   - Fix: Improve integration with lspconfig

3. **Error Log Cleanup** ✅
   - Fixed: Changed all DEBUG prints to log.debug()

4. **Docker Function Duplication Fix** ✅
   - Fixed: M.M.run_docker_command → M.run_docker_command

5. **Unnecessary Startup Messages** ✅
   - Fixed: Changed initialization messages to debug level

6. **LSP Auto-attach Feature** ✅
   - Implemented: Auto-attach to new buffers via autocommand

7. **postCreateCommand Support** ✅
   - Implemented: Automatic execution of postCreateCommand after container creation
   - Supports field name conversion by parser normalization (postCreateCommand → post_create_command)

8. **Go Environment LSP Detection Issue** ✅
   - Fixed: Added Go binary paths (/usr/local/go/bin, /go/bin) to PATH for LSP detection and execution
   - Temporary fix: Until environment-specific devcontainer.json support is implemented

### 🟡 Medium Priority

9. **Debug Commands Cleanup**
   - Review and clean up debug commands added during development
   - Remove obsolete/redundant commands and consolidate remaining ones
   - Impact: Code maintainability and plugin size reduction

10. **Neovim Help Documentation**
   - Add Neovim help documentation (doc/devcontainer.txt)
   - Update development workflow to maintain help docs alongside README
   - Impact: Better user experience following Neovim plugin conventions

11. **Performance Optimization**
   - Parallel LSP server detection
   - Docker operation caching
   - Reduction of unnecessary Docker calls

12. **Enhanced Error Handling**
   - Proper error messages when Docker is not running
   - Recovery functionality for LSP server startup failures
   - Network timeout handling

## Next Milestone Planning

### v0.2.1 (Bug Fix Release) ✅ Complete
- [x] High priority issue fixes
  - [x] postCreateCommand support implementation
  - [x] LSP auto-attach feature
  - [x] Go environment LSP detection issue fix
- [ ] Test suite improvements (deferred to next release)
- [ ] Documentation updates (deferred to next release)

### v0.3.0 (Terminal Integration) - 4-6 weeks

#### New Features
- [ ] **Enhanced Terminal Integration**
  - [ ] Improved in-container terminal
  - [ ] Session management functionality
  - [ ] Terminal history persistence

- [ ] **Port Forwarding Features**
  - [ ] Automatic port detection
  - [ ] Dynamic forwarding
  - [ ] Port management UI

- [ ] **Telescope Integration**
  - [ ] devcontainer picker
  - [ ] Command history picker
  - [ ] Port management picker

- [ ] **External Plugin Integration**
  - [ ] nvim-test integration (container-based test command execution)
  - [ ] nvim-dap integration (container-based debugger execution)
  - [ ] General command execution plugin integration

#### Technical Improvements
- [ ] **Configuration System Extension**
  - [ ] User configuration validation
  - [ ] Dynamic configuration changes
  - [ ] Profile functionality

- [ ] **Environment-specific devcontainer.json Support**
  - [ ] Configurable runtime environment variables (PATH, GOPATH, etc.)
  - [ ] Environment variable customization for postCreateCommand execution
  - [ ] Language-specific settings in devcontainer.json
  - [ ] Remove hardcoded environment settings from plugin

- [ ] **UI/UX Improvements**
  - [ ] Status line display
  - [ ] Notification system
  - [ ] Enhanced progress display

### v0.4.0 (Multi-container Support) - 6-8 weeks

- [ ] **Docker Compose Support**
  - [ ] docker-compose.yml parsing
  - [ ] Multi-container environment management
  - [ ] Inter-service communication

- [ ] **Advanced Networking Features**
  - [ ] Custom network configuration
  - [ ] Service discovery
  - [ ] Load balancing

### v1.0.0 (Stable Release) - 3-4 months

- [ ] **Full VSCode Compatibility**
- [ ] **Comprehensive Test Suite**
- [ ] **Complete Documentation**
- [ ] **Performance Optimization**

## External Plugin Integration Detailed Design

### nvim-test Integration
Currently, test plugins like `klen/nvim-test` and `vim-test/vim-test` execute commands in the local environment, but devcontainer environments require the following integration:

**Implementation Approach:**
- Hook/override test plugin command execution
- Automatically execute within container when container is running
- Example: `:TestNearest` → `docker exec container_id go test -run TestFunction`

**Target Plugins:**
- `klen/nvim-test`
- `vim-test/vim-test`
- `nvim-neotest/neotest`

### nvim-dap Integration
Debuggers also need to run within containers, requiring:

**Implementation Requirements:**
- Auto-modify DAP adapter configuration for container execution
- Debug port forwarding
- Debugger startup within container

### General Command Execution Integration
Other plugins can be integrated using similar patterns:

**Design Pattern:**
```lua
-- API for plugin integration
devcontainer.integrate_command_plugin({
  plugin_name = "nvim-test",
  command_patterns = {"Test*"},
  wrapper_function = function(original_cmd)
    return devcontainer.wrap_command(original_cmd)
  end
})
```

This functionality provides developers with a complete development experience within devcontainers.

## Environment-specific Configuration Design Improvements

### Current Problem
Currently, environment variables (PATH, GOPATH, etc.) for postCreateCommand execution are hardcoded in the plugin, requiring individual support for each language.

### Proposed Improvements

#### 1. Environment Variable Specification in devcontainer.json
```json
{
  "name": "Go Project",
  "image": "mcr.microsoft.com/devcontainers/go:1-1.23-bookworm",
  "postCreateCommand": "go install golang.org/x/tools/gopls@latest",

  "customizations": {
    "devcontainer.nvim": {
      "postCreateEnvironment": {
        "PATH": "/home/vscode/.local/bin:/usr/local/go/bin:/go/bin:$PATH",
        "GOPATH": "/go",
        "GOROOT": "/usr/local/go"
      },
      "execEnvironment": {
        "PATH": "/home/vscode/.local/bin:/usr/local/go/bin:/go/bin:$PATH"
      }
    }
  }
}
```

#### 2. Language-specific Presets
```json
{
  "customizations": {
    "devcontainer.nvim": {
      "languagePreset": "go",  // go, python, node, rust, etc.
      "additionalEnvironment": {
        "CUSTOM_VAR": "value"
      }
    }
  }
}
```

#### 3. Execution Context-specific Settings
- `postCreateEnvironment`: Environment for postCreateCommand execution
- `execEnvironment`: Environment for DevcontainerExec execution  
- `lspEnvironment`: Environment for LSP-related command execution

### Implementation Benefits
- Remove language-specific hardcoding from plugin
- Allow users complete control over environment
- Easy support for new languages
- Comply with standard devcontainer.json extension patterns

## Technical Debt and Improvement Plans

### Architecture Improvements

1. **Module Dependency Organization**
   - Current: Some circular dependencies exist
   - Improvement: Optimize dependency graph

2. **Unified Error Handling**
   - Current: Different error handling per module
   - Improvement: Common error handling library

3. **Configuration System Improvements**
   - Current: Insufficient configuration validation
   - Improvement: JSON Schema-based validation

### Performance Improvements

1. **Docker Operation Optimization**
   - Reduce unnecessary Docker calls
   - Result caching
   - Leverage parallel processing

2. **LSP Communication Optimization**
   - Connection pool implementation
   - Request batching
   - Response time improvements

### Development Experience Improvements

1. **Enhanced Debug Tools**
   - More detailed log output
   - Debug mode implementation
   - Profiling functionality

2. **Test Environment Setup**
   - CI/CD pipeline
   - Automated testing
   - Performance testing

## User Feedback Response

### Commonly Reported Issues

1. **Docker for Mac Performance Issues**
   - File mount optimization
   - Cache strategy improvements

2. **Windows Environment Issues**
   - Path separator handling
   - File permission issues

3. **Large Project Performance**
   - Memory usage optimization
   - Startup time improvements

## Development Process Improvements

### Quality Management
- [ ] Enhanced automated testing
- [ ] Code review guideline establishment
- [ ] Performance regression testing

### Documentation
- [ ] Automated API documentation generation
- [ ] Enhanced tutorials
- [ ] Troubleshooting guide

### Community
- [ ] Contribution guidelines
- [ ] Issue templates
- [ ] Discussion forum

---

**Last Updated**: 2025-06-15  
**Next Review Scheduled**: During v0.3.0 planning

This TODO list is regularly updated as the project progresses.
