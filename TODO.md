# devcontainer.nvim TODO & Improvements

This file tracks the development roadmap, completed features, and planned improvements for devcontainer.nvim.

## Current Status (v0.3.0 Complete)

✅ **Core Features Completed**
- Basic devcontainer operations (v0.1.0)
- LSP integration features (v0.2.0)
  - Automatic LSP server detection in Docker
  - Asynchronous Docker operations
  - Path conversion functionality
  - Reconnection capability
- Enhanced Terminal Integration (v0.3.0)
  - Session management with named sessions
  - Flexible positioning (split, vsplit, tab, float)
  - Persistent history with project isolation
  - Smart port forwarding with dynamic allocation

✅ **Critical Issues Resolved (v0.1.0 - v0.3.0)**

- Container naming conflicts preventing multi-project development
- LSP client integration issues (clients not visible in `:LspInfo`)
- Error logging and debug message cleanup
- Docker function duplication and startup message optimization
- LSP auto-attach functionality for new buffers
- postCreateCommand execution support with field normalization
- Go environment PATH issues for LSP detection
- Debug command cleanup and codebase maintainability
- Comprehensive Neovim help documentation system

All critical functionality-blocking issues have been resolved through v0.3.0.

## Next Milestone Planning

All critical issues and basic features have been completed through v0.3.0.
The following roadmap focuses on advanced features and ecosystem integration.

### v0.4.0 (UI & Integration) - 6-8 weeks

Priority: Focus on user experience and ecosystem integration

#### High Priority - User Interface
- [x] **Telescope Integration** (Week 1-2) ✅ **COMPLETED**
  - [x] devcontainer picker (select/switch between projects)
  - [x] Terminal session picker with session management
  - [x] Port management picker (view/manage active ports) - Uses vim.ui.select due to telescope state issues
  - [x] Command history picker for DevcontainerExec

- [x] **UI/UX Improvements** (Week 3-4) ✅ **COMPLETED**
  - [x] Status line integration (show container status) ✅ **COMPLETED**
  - [x] Enhanced notification system (progress indicators, success/error states) ✅ **COMPLETED**
  - [x] Reduce excessive notifications to essential ones only ✅ **COMPLETED**
    - [x] Add notification levels (verbose, normal, minimal, silent) ✅ **COMPLETED**
    - [x] Make routine operations silent by default ✅ **COMPLETED**
    - [x] Only show critical errors and user-requested status updates ✅ **COMPLETED**
  - [ ] Port forwarding UI improvements (visual indicators, click-to-open)
  - [x] Add confirmation dialog for destructive commands (DevcontainerTerminate, DevcontainerKill) ✅ **COMPLETED**
  - [ ] Add fzf-lua as alternative to telescope for picker integration

#### Medium Priority - Configuration
- [ ] **Environment-specific devcontainer.json Support** (Week 5-6)
  - [ ] Custom environment variables in devcontainer.json
  - [ ] Language-specific presets (go, python, node, rust)
  - [ ] Remove hardcoded language paths from plugin
  - [ ] Support for execution context-specific environments

- [ ] **Configuration System Enhancement** (Week 7-8)
  - [ ] Runtime configuration validation and error reporting
  - [ ] Configuration profiles (development, testing, production)
  - [ ] Dynamic configuration updates without restart

### v0.5.0 (External Plugin Integration) - 8-10 weeks

Priority: Seamless integration with popular Neovim development plugins

#### High Priority - Testing Integration  
- [ ] **nvim-test Integration** (Week 1-3)
  - [ ] Hook into test plugin command execution
  - [ ] Automatic container-based test execution  
  - [ ] Support for `vim-test/vim-test`, `klen/nvim-test`, `nvim-neotest/neotest`
  - [ ] Test result integration and display

#### Medium Priority - Debugging Integration
- [ ] **nvim-dap Integration** (Week 4-6)
  - [ ] Container-based debugger configuration
  - [ ] Automatic DAP adapter setup for containers
  - [ ] Debug port forwarding management
  - [ ] Debugger startup within container environment

#### Low Priority - General Integration
- [ ] **General Command Execution API** (Week 7-8)
  - [ ] Plugin integration framework (`devcontainer.integrate_command_plugin`)
  - [ ] Command wrapping utilities for container execution
  - [ ] Documentation for third-party plugin integration

#### Technical Improvements
- [ ] **Performance Optimization** (Week 9-10)
  - [ ] Docker operation caching and optimization
  - [ ] Parallel LSP server detection improvements
  - [ ] LSP communication improvements (connection pooling, request batching)
  - [ ] Memory usage optimization for large projects
  - [ ] Reduction of unnecessary Docker calls

- [ ] **Enhanced Error Handling** (Week 10)
  - [ ] Improved error messages when Docker is not running
  - [ ] Recovery functionality for LSP server startup failures
  - [ ] Network timeout handling and retry mechanisms
  - [ ] Graceful degradation for partial failures

### v0.6.0 (Multi-container & Advanced Features) - 10-12 weeks

Priority: Complex multi-service development environments

- [ ] **Docker Compose Support**
  - [ ] docker-compose.yml parsing and validation
  - [ ] Multi-container environment management
  - [ ] Service-to-service communication setup
  - [ ] Compose service selection and management

- [ ] **Advanced Networking Features**
  - [ ] Custom network configuration
  - [ ] Service discovery between containers
  - [ ] Load balancing configuration
  - [ ] Network isolation and security

### v1.0.0 (Stable Release) - 12-16 weeks

Priority: Production-ready plugin with full ecosystem compatibility

#### Stability & Quality
- [ ] **Comprehensive Test Suite**
  - [ ] Integration tests with real containers
  - [ ] Performance benchmarking and regression tests
  - [ ] Cross-platform compatibility testing (Linux, macOS, Windows)
  - [ ] CI/CD pipeline with automated testing

- [ ] **Complete Documentation & Guides**
  - [ ] Comprehensive user manual and tutorials
  - [ ] API documentation for plugin developers
  - [ ] Migration guides and troubleshooting
  - [ ] Video tutorials and example configurations

#### Production Features
- [ ] **Advanced Error Handling & Recovery**
  - [ ] Comprehensive error recovery workflows
  - [ ] Automatic service health monitoring and recovery
  - [ ] Advanced retry strategies with exponential backoff
  - [ ] Context-aware error messages and automated suggestions

- [ ] **Performance & Optimization**
  - [ ] Lazy loading optimization
  - [ ] Memory usage monitoring and optimization  
  - [ ] Docker operation caching and batching
  - [ ] Startup time optimization

#### Ecosystem Integration
- [ ] **Full VSCode devcontainer.json Compatibility**
  - [ ] Support for all standard devcontainer.json features
  - [ ] Feature and lifecycle script compatibility
  - [ ] devcontainer CLI interoperability
  - [ ] Container template support

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

## Long-term Technical Improvements

These items will be integrated into appropriate version milestones based on priority and dependencies.

### Architecture Improvements (Target: v0.4.0 - v0.6.0)
- **Module Dependency Organization**: Optimize dependency graph and eliminate circular dependencies
- **Unified Error Handling**: Implement common error handling library across modules  
- **Advanced Logging**: Enhanced debug tools with profiling and detailed output

### Performance Optimizations (Target: v1.0.0)
- **Advanced Caching Strategies**: Intelligent cache invalidation and persistence
- **Startup Performance**: Lazy loading and initialization optimization
- **Large Project Optimization**: Memory management for complex multi-service projects

### Platform Compatibility (Target: v0.6.0 - v1.0.0)
- **Docker for Mac Optimization**: File mount optimization and cache strategy improvements
- **Windows Support**: Path separator handling and file permission resolution
- **Cross-platform Testing**: Automated testing on Linux, macOS, and Windows

### Development Infrastructure (Target: v1.0.0)
- **CI/CD Pipeline**: Automated testing, performance regression testing, and quality gates
- **Documentation Automation**: API documentation generation and tutorial maintenance
- **Community Infrastructure**: Contribution guidelines, issue templates, and discussion forums

---

## Development Roadmap Summary

### ✅ **Completed (v0.1.0 - v0.3.0)**
Core functionality with enhanced terminal integration and smart port forwarding

### 🎯 **Next Priority (v0.4.0 - 6-8 weeks)**
User interface improvements with Telescope integration and configuration enhancements

### 🔮 **Future Development (v0.5.0 - v1.0.0)**
- **v0.5.0**: External plugin integration (nvim-test, nvim-dap)
- **v0.6.0**: Multi-container and Docker Compose support  
- **v1.0.0**: Production-ready release with full ecosystem compatibility

### 📊 **Priority Matrix**
1. **High**: User experience and ecosystem integration (v0.4.0-v0.5.0)
2. **Medium**: Advanced features and multi-container support (v0.6.0)
3. **Low**: Platform optimization and infrastructure (v1.0.0)

**Last Updated**: 2025-06-16  
**Next Review Scheduled**: During v0.4.0 planning

This roadmap is regularly updated based on user feedback and development progress.
