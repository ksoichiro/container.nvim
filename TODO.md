# container.nvim TODO & Improvements

This file tracks the development roadmap, completed features, and planned improvements for container.nvim.

## Current Status (v0.3.0 Complete)

✅ **Core Features Completed**
- Basic container operations (v0.1.0)
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
  - [x] container picker (select/switch between projects)
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
  - [x] Port forwarding UI improvements (visual indicators, click-to-open) ✅ **COMPLETED**
  - [x] Add confirmation dialog for destructive commands (DevcontainerTerminate, DevcontainerKill) ✅ **COMPLETED**
  - [x] Add fzf-lua as alternative to telescope for picker integration ✅ **COMPLETED**

#### Medium Priority - Configuration
- [x] **Environment-specific devcontainer.json Support** (Week 5-6) ✅ **COMPLETED**
  - [x] Custom environment variables in devcontainer.json ✅ **COMPLETED**
  - [x] Language-specific presets (go, python, node, rust) ✅ **COMPLETED**
  - [x] Remove hardcoded language paths from plugin ✅ **COMPLETED**
  - [x] Support for execution context-specific environments ✅ **COMPLETED**

- [x] **Configuration System Enhancement** (Week 7-8) ✅ **COMPLETED**
  - [x] Runtime configuration validation and error reporting
  - [x] Environment variable overrides with DEVCONTAINER_ prefix
  - [x] Project-specific configuration file (.container.nvim.lua)
  - [x] Dynamic configuration updates without restart
  - [x] Configuration save/load functionality
  - [x] Live configuration file watching

### v0.5.0 (External Plugin Integration) - 8-10 weeks

Priority: Seamless integration with popular Neovim development plugins

#### High Priority - Testing Integration  
- [x] **nvim-test Integration** (Week 1-3) ✅ **COMPLETED**
  - [x] Hook into test plugin command execution ✅ **COMPLETED**
  - [x] Automatic container-based test execution ✅ **COMPLETED**
  - [x] Support for `vim-test/vim-test`, `klen/nvim-test`, `nvim-neotest/neotest` ✅ **COMPLETED**
  - [x] Test result integration and display ✅ **COMPLETED**

#### Medium Priority - Debugging Integration
- [x] **nvim-dap Integration** (Week 4-6) ✅ **COMPLETED**
  - [x] Container-based debugger configuration ✅ **COMPLETED**
  - [x] Automatic DAP adapter setup for containers ✅ **COMPLETED**
  - [x] Debug port forwarding management ✅ **COMPLETED**
  - [x] Debugger startup within container environment ✅ **COMPLETED**
  - [x] Go debugging with delve (dlv) support ✅ **COMPLETED**
  - [x] Attach mode debugging for better container compatibility ✅ **COMPLETED**
  - [x] Path mapping between host and container for debugging ✅ **COMPLETED**
  - [x] Automatic dlv server startup on container start ✅ **COMPLETED**

#### Low Priority - General Integration
- [x] **General Command Execution API** (Week 7-8) ✅ **COMPLETED**
  - [x] Advanced command execution API with sync/async/fire-and-forget modes ✅ **COMPLETED**
  - [x] Streaming output support for real-time command monitoring ✅ **COMPLETED**
  - [x] Enhanced command building utilities and environment setup ✅ **COMPLETED**
  - [x] Comprehensive command-line interface with advanced options ✅ **COMPLETED**
  - [ ] Plugin integration framework (`container.integrate_command_plugin`)
  - [ ] Command wrapping utilities for container execution
  - [ ] Documentation for third-party plugin integration

#### Technical Improvements
- [ ] **Performance Optimization** (Week 9-10)
  - [ ] Docker operation caching and optimization
  - [ ] Parallel LSP server detection improvements
  - [ ] LSP communication improvements (connection pooling, request batching)
  - [ ] Memory usage optimization for large projects
  - [ ] Reduction of unnecessary Docker calls

- [x] **Enhanced Error Handling** (Week 10) ✅ **COMPLETED**
  - [x] Improved error messages when Docker is not running ✅ **COMPLETED**
  - [x] Recovery functionality for LSP server startup failures ✅ **COMPLETED**
  - [x] Network timeout handling and retry mechanisms ✅ **COMPLETED**
  - [x] Graceful degradation for partial failures ✅ **COMPLETED**

#### Low Priority - Compliance & Standards
- [ ] **Dev Containers Specification Compliance Review**
  - [ ] Review custom configuration items in devcontainer.json parsing
  - [ ] Evaluate non-standard settings: `languagePreset`, context-specific environments
  - [ ] Assess dynamic port allocation syntax (`"auto:3000"`, `"range:8000-8010:3000"`)
  - [ ] Consider migration to fully compliant standard settings
  - [ ] Document compatibility implications with VSCode Dev Containers

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
  - [ ] container CLI interoperability
  - [ ] Container template support

## External Plugin Integration Detailed Design

### nvim-test Integration
Currently, test plugins like `klen/nvim-test` and `vim-test/vim-test` execute commands in the local environment, but container environments require the following integration:

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
The General Command Execution API is now implemented with comprehensive command execution capabilities:

**Current Implementation (v0.5.0):**
```lua
-- Sync execution
local output, err = require('container').execute('npm test')

-- Async execution with callback
require('container').execute('npm run build', {
  mode = 'async',
  callback = function(result)
    if result.success then
      print("Build completed successfully!")
    end
  end
})

-- Streaming output
require('container').execute_stream('npm run dev', {
  on_stdout = function(line) print("[OUT] " .. line) end,
  on_stderr = function(line) print("[ERR] " .. line) end,
  on_exit = function(code) print("Exited with code: " .. code) end
})

-- Background execution
require('container').execute('npm run serve', { mode = 'fire_and_forget' })
```

**Command Interface:**
```vim
" Basic synchronous execution
:ContainerExec npm test

" Advanced execution with options
:ContainerRun --workdir /app --user node --env NODE_ENV=production npm run build
:ContainerRun --stream --timeout 300 npm run test:watch
:ContainerRun --bg npm run dev
```

**Future Plugin Integration API:**
```lua
-- API for plugin integration (planned)
container.integrate_command_plugin({
  plugin_name = "nvim-test",
  command_patterns = {"Test*"},
  wrapper_function = function(original_cmd)
    return container.wrap_command(original_cmd)
  end
})
```

This functionality provides developers with a complete development experience within containers.

## Environment-specific Configuration Design Improvements

### Current Problem
Currently, environment variables (PATH, GOPATH, etc.) for postCreateCommand execution are hardcoded in the plugin, requiring individual support for each language.

### Proposed Improvements

#### 1. Environment Variable Specification in devcontainer.json
```json
{
  "name": "Go Project",
  "image": "mcr.microsoft.com/containers/go:1-1.23-bookworm",
  "postCreateCommand": "go install golang.org/x/tools/gopls@latest",

  "customizations": {
    "container.nvim": {
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
    "container.nvim": {
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

**Last Updated**: 2025-06-21  
**Next Review Scheduled**: During v0.6.0 planning

This roadmap is regularly updated based on user feedback and development progress.
