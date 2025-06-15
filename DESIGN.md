# devcontainer.nvim Plugin Design Document

A comprehensive design document for a Neovim plugin that enables devcontainer usage similar to VSCode.

## Overview

devcontainer.nvim is a plugin that provides a development experience similar to VSCode's Dev Containers extension for Neovim. It automatically sets up development environments within Docker containers and achieves integration with LSP, terminal, and filesystem.

## Architecture

### Project Structure

```
devcontainer.nvim/
├── lua/
│   └── devcontainer/
│       ├── init.lua              -- Main entry point
│       ├── config.lua            -- Configuration management
│       ├── parser.lua            -- devcontainer.json parser
│       ├── docker/
│       │   ├── init.lua          -- Docker operations abstraction
│       │   ├── compose.lua       -- Docker Compose support
│       │   └── image.lua         -- Image build/management
│       ├── container/
│       │   ├── manager.lua       -- Container lifecycle management
│       │   ├── exec.lua          -- Command execution within containers
│       │   └── filesystem.lua    -- Filesystem operations
│       ├── lsp/
│       │   ├── init.lua          -- LSP integration
│       │   └── forwarding.lua    -- LSP server port forwarding
│       ├── terminal/
│       │   ├── init.lua          -- Terminal integration
│       │   └── session.lua       -- Session management
│       ├── ui/
│       │   ├── picker.lua        -- telescope/fzf integration
│       │   ├── status.lua        -- Status display
│       │   └── notifications.lua -- Notification system
│       └── utils/
│           ├── fs.lua            -- Filesystem utilities
│           ├── log.lua           -- Logging system
│           └── async.lua         -- Asynchronous processing
├── plugin/
│   └── devcontainer.lua          -- Plugin initialization
├── doc/
│   └── devcontainer.txt          -- Documentation
└── README.md
```

## Core Features

### 1. devcontainer.json Parsing and Configuration Management

#### config.lua Design
```lua
local M = {}

M.defaults = {
  auto_start = false,
  dockerfile_path = ".devcontainer/Dockerfile",
  compose_file = ".devcontainer/docker-compose.yml",
  mount_workspace = true,
  forward_ports = true,
  post_create_command = nil,
  extensions = {},
  settings = {},
  container_runtime = 'docker', -- or 'podman'
  log_level = 'info',
}

function M.parse_devcontainer_json(path)
  -- Parse devcontainer.json
  -- Load settings compliant with VSCode specifications
  -- Return: parsed configuration table
end

function M.merge_config(user_config, devcontainer_config)
  -- Merge user settings with devcontainer settings
  -- Priority: devcontainer.json > user settings > default settings
end

function M.validate_config(config)
  -- Check configuration validity
  -- Verify existence of required fields
  -- Validate path validity
end
```

#### parser.lua Design
```lua
local M = {}

function M.find_devcontainer_json(start_path)
  -- Search parent directories from specified path
  -- Look for .devcontainer/devcontainer.json
end

function M.parse_json_with_comments(file_path)
  -- Parse JSONC files (JSON with comments)
  -- Support same specifications as VSCode
end

function M.resolve_dockerfile_path(config, base_path)
  -- Resolve relative Dockerfile paths to absolute paths
end

function M.expand_variables(config, context)
  -- Expand variables like ${localWorkspaceFolder}
end
```

### 2. Docker Integration Layer

#### docker/init.lua Design
```lua
local M = {}

function M.check_docker_availability()
  -- Check Docker availability
  -- Verify docker command exists
  -- Confirm Docker daemon is running
end

function M.build_image(config, on_progress, on_complete)
  -- Build Docker image
  -- Progress display and error handling
  -- Asynchronous execution
end

function M.create_container(config)
  -- Create container
  -- Configure volume mounts and port forwarding
  -- Set environment variables
end

function M.start_container(container_id)
  -- Start container
  -- Health check
end

function M.exec_command(container_id, command, opts)
  -- Execute command within container
  -- Asynchronous execution with streaming output
  -- Get exit code
end

function M.get_container_status(container_id)
  -- Get container status
  -- running, stopped, paused, etc.
end
```

#### docker/image.lua Design
```lua
local M = {}

function M.build_from_dockerfile(dockerfile_path, context_path, tag, opts)
  -- Build image from Dockerfile
  -- Configure build context
  -- Cache strategy
end

function M.pull_base_image(image_name, on_progress)
  -- Pull base image
  -- Progress display
end

function M.list_images(filter)
  -- Get local image list
  -- Filtering functionality
end

function M.remove_image(image_id, force)
  -- Remove image
  -- Check dependencies
end
```

### 3. Container Management

#### container/manager.lua Design
```lua
local M = {}

function M.create_devcontainer(config)
  -- Create devcontainer
  -- Container configuration based on settings
  -- Network configuration
end

function M.start_devcontainer(container_id, post_start_command)
  -- Start devcontainer
  -- Execute post-start command
end

function M.stop_devcontainer(container_id, timeout)
  -- Stop devcontainer
  -- Graceful shutdown
end

function M.remove_devcontainer(container_id, remove_volumes)
  -- Remove devcontainer
  -- Volume removal option
end

function M.get_container_info(container_id)
  -- Get container information
  -- IP address, ports, mount information, etc.
end
```

#### container/exec.lua Design
```lua
local M = {}

function M.exec_interactive(container_id, command, opts)
  -- Interactive command execution
  -- PTY allocation
  -- Input/output streaming
end

function M.exec_background(container_id, command, opts)
  -- Background command execution
  -- Log retrieval
end

function M.copy_to_container(container_id, local_path, container_path)
  -- Copy files from local to container
end

function M.copy_from_container(container_id, container_path, local_path)
  -- Copy files from container to local
end
```

### 4. LSP Integration

#### lsp/init.lua Design
```lua
local M = {}

function M.setup_lsp_in_container(config, container_id)
  -- Detect and configure LSP servers in container
  -- Language-specific configuration
  -- Choose port-based or stdio communication
end

function M.create_lsp_client(server_config, container_id)
  -- Create communication client with LSP server in container
  -- Integration with nvim-lspconfig
end

function M.detect_language_servers(container_id, workspace_path)
  -- Detect available LSP servers in container
  -- Auto-configuration
end

function M.forward_lsp_requests(client, request, params)
  -- Forward LSP requests to container
  -- Path transformation processing
end
```

#### lsp/forwarding.lua Design
```lua
local M = {}

function M.setup_port_forwarding(container_id, ports)
  -- Configure LSP server port forwarding
  -- Dynamic port allocation
end

function M.create_stdio_bridge(container_id, command)
  -- LSP communication bridge via stdio
  -- Process management
end

function M.transform_file_uris(uri, workspace_mapping)
  -- Transform file URIs
  -- Mapping between local paths and container paths
end
```

### 5. Terminal Integration

#### terminal/init.lua Design
```lua
local M = {}

function M.open_container_terminal(container_id, opts)
  -- Open terminal in container
  -- Integration with Neovim terminal
end

function M.create_terminal_session(container_id, shell_command)
  -- Create terminal session
  -- Session management
end

function M.attach_to_session(session_id)
  -- Attach to existing session
end

function M.list_sessions(container_id)
  -- List active sessions
end
```

### 6. User Interface

#### Command Design
```vim
" Basic operations
:DevcontainerOpen [path]         " Open devcontainer
:DevcontainerBuild               " Build image
:DevcontainerRebuild             " Rebuild image
:DevcontainerStart               " Start container
:DevcontainerStop                " Stop container
:DevcontainerRestart             " Restart container
:DevcontainerAttach              " Attach to container

" Command execution
:DevcontainerExec <command>      " Execute command in container
:DevcontainerShell [shell]       " Open shell in container

" Information display
:DevcontainerStatus              " Display container status
:DevcontainerLogs                " Display container logs
:DevcontainerConfig              " Display/edit configuration

" Port management
:DevcontainerForwardPort <port>  " Port forwarding
:DevcontainerPorts               " List forwarded ports

" Advanced operations
:DevcontainerReset               " Reset environment
:DevcontainerClone <url>         " Clone repository and open
```

#### ui/picker.lua Design (Telescope Integration)
```lua
local M = {}

function M.pick_devcontainer()
  -- Select available devcontainer
  -- With preview functionality
end

function M.pick_container_command()
  -- Select executable command
  -- History functionality
end

function M.pick_forwarded_ports()
  -- Manage forwarded ports
  -- Add/remove ports
end

function M.pick_container_files()
  -- Container file picker
  -- File browser functionality
end
```

#### ui/status.lua Design
```lua
local M = {}

function M.show_container_status()
  -- Display container status in statusline
  -- Visual display with icons and colors
end

function M.show_build_progress(progress_info)
  -- Display build progress
  -- Progress bar
end

function M.show_port_status(ports)
  -- Display port forwarding status
end
```

### 7. Configuration System

#### Plugin Configuration Example
```lua
require('devcontainer').setup({
  -- Basic settings
  auto_start = false,
  log_level = 'info',
  container_runtime = 'docker', -- 'docker' or 'podman'
  
  -- UI settings
  ui = {
    use_telescope = true,
    show_notifications = true,
    status_line = true,
    icons = {
      container = "🐳",
      running = "✅",
      stopped = "⏹️",
      building = "🔨",
    },
  },
  
  -- LSP settings
  lsp = {
    auto_setup = true,
    timeout = 5000,
    servers = {
      -- Language-specific LSP settings
      lua = { cmd = "lua-language-server" },
      python = { cmd = "pylsp" },
      javascript = { cmd = "typescript-language-server" },
    },
  },
  
  -- Terminal settings
  terminal = {
    shell = '/bin/bash',
    height = 15,
    direction = 'horizontal', -- 'horizontal', 'vertical', 'float'
    close_on_exit = false,
  },
  
  -- Port forwarding
  port_forwarding = {
    auto_forward = true,
    notification = true,
    common_ports = {3000, 8080, 5000, 3001},
  },
  
  -- Workspace settings
  workspace = {
    auto_mount = true,
    mount_point = '/workspace',
    sync_settings = true,
  },
  
  -- Docker settings
  docker = {
    build_args = {},
    network_mode = 'bridge',
    privileged = false,
    init = true,
  },
  
  -- Development settings
  dev = {
    reload_on_change = true,
    debug_mode = false,
  },
})
```

#### devcontainer.json Support
```json
{
  "name": "My Development Environment",
  "dockerFile": "Dockerfile",
  "context": "..",
  "build": {
    "dockerfile": "Dockerfile",
    "context": "..",
    "args": {
      "NODE_VERSION": "18"
    }
  },
  "mounts": [
    "source=${localWorkspaceFolder},target=/workspace,type=bind,consistency=cached"
  ],
  "forwardPorts": [3000, 8080],
  "portsAttributes": {
    "3000": {
      "label": "Frontend",
      "onAutoForward": "notify"
    }
  },
  "postCreateCommand": "npm install && npm run setup",
  "postStartCommand": "npm run dev",
  "remoteUser": "developer",
  "workspaceFolder": "/workspace",
  "customizations": {
    "neovim": {
      "settings": {
        "editor.tabSize": 2,
        "editor.insertSpaces": true
      },
      "extensions": [
        "nvim-lspconfig",
        "nvim-treesitter"
      ],
      "commands": [
        "PlugInstall",
        "TSUpdate"
      ]
    }
  },
  "features": {
    "ghcr.io/devcontainers/features/git:1": {},
    "ghcr.io/devcontainers/features/node:1": {
      "version": "18"
    }
  }
}
```

## Implementation Phases

### Phase 1: Foundation Implementation (4-6 weeks)
1. **Core Features**
   - devcontainer.json parser
   - Basic Docker operations (build, run, exec)
   - Configuration system
   - Logging system

2. **Basic UI**
   - Command interface
   - Status display
   - Error handling

3. **Test Environment**
   - Unit tests
   - Integration tests
   - Sample projects

### Phase 2: Integration Features (6-8 weeks)
1. **LSP Integration**
   - Detection of LSP servers in containers
   - Integration with nvim-lspconfig
   - File path transformation

2. **Terminal Integration**
   - Container terminal
   - Session management
   - Command history

3. **Port Forwarding**
   - Automatic port detection
   - Dynamic forwarding
   - Port management UI

### Phase 3: Advanced Features (4-6 weeks)
1. **Docker Compose Support**
   - Multi-container environments
   - Inter-service communication
   - Dependency management

2. **Telescope Integration**
   - File picker
   - Command picker
   - Container picker

3. **Extensions**
   - Plugin ecosystem
   - Custom actions
   - Hook functionality

### Phase 4: Optimization & Enhancement (2-4 weeks)
1. **Performance Optimization**
   - Asynchronous processing optimization
   - Memory usage reduction
   - Caching functionality

2. **Enhanced Error Handling**
   - Detailed error messages
   - Recovery functionality
   - Debug support

3. **Documentation**
   - User guide
   - API documentation
   - Tutorials

## Technical Considerations

### Asynchronous Processing
- Non-blocking operations using `vim.loop` (libuv)
- Asynchronous Docker API calls
- Progress display and cancellation functionality
- Proper cleanup on errors

### Error Handling
- Appropriate error messages when Docker is not installed
- Network error and timeout handling
- Recovery functionality for partial failures
- User-friendly error display

### Security
- Access permission checks to Docker socket
- File access restrictions within containers
- Proper handling of sensitive information
- Prevention of privilege escalation

### Performance
- Parallelization of image builds
- LSP communication optimization
- Efficient filesystem operations
- Memory usage monitoring

### Compatibility
- Support for multiple Docker versions
- Compatibility with Podman
- Operation on different OS (Linux, macOS, Windows)
- Compatibility with VSCode devcontainer

## Dependencies

### Required Dependencies
- Neovim 0.8+
- Docker or Podman
- plenary.nvim (asynchronous processing)

### Optional Dependencies
- telescope.nvim (UI extensions)
- nvim-lspconfig (LSP integration)
- nvim-treesitter (syntax highlighting)
- which-key.nvim (keybinding display)

## Testing Strategy

### Unit Tests
- Individual testing of each module
- Docker operation tests using mocks
- Configuration parsing tests

### Integration Tests
- Tests using actual Docker containers
- LSP integration tests
- End-to-end workflow tests

### Performance Tests
- Operation verification with large projects
- Memory usage measurement
- Response time measurement

## Release Plan

### v0.1.0 (MVP)
- Basic devcontainer operations
- Docker integration
- Basic commands

### v0.2.0 (LSP Integration)
- LSP server integration
- Terminal integration
- Port forwarding

### v0.3.0 (UI Enhancement)
- Telescope integration
- Enhanced status display
- Configuration UI

### v1.0.0 (Stable Release)
- Complete feature implementation
- Comprehensive testing
- Complete documentation

This design enables a development experience equivalent to or better than VSCode's devcontainer functionality in Neovim. Through incremental implementation, it's possible to sequentially add features from basic functionality to advanced features.

## Plugin Integration Architecture

### Architecture Choice

To achieve deep plugin integration implementation in devcontainer.nvim, after considering multiple approaches, we adopt a **hybrid approach**.

#### Approaches Considered

1. **VSCode-type Approach (Container-internal Server)**
   - Deploy Neovim server inside container
   - Host Neovim operates as client
   - Advantages: Complete isolation, full VSCode compatibility
   - Disadvantages: Implementation complexity, performance overhead

2. **Command Forwarding (Current Extension)**
   - Keep Neovim on host side
   - Forward specific commands to container
   - Advantages: Simple implementation, compatibility with existing plugins
   - Disadvantages: Integration limitations, requires per-plugin adaptation

3. **Remote Plugin Architecture**
   - Utilize Neovim's remote plugin functionality
   - Run plugins as remote plugins inside container
   - Advantages: Leverage existing Neovim architecture
   - Disadvantages: Not all plugins support remote execution

4. **Hybrid Approach (Adopted)**
   - Use command forwarding as foundation
   - Use remote plugin architecture for complex plugins
   - Choose optimal integration method per plugin
   - Advantages: Flexibility, incremental implementation, good performance
   - Disadvantages: Moderate implementation complexity

### Hybrid Architecture Design

#### 1. Plugin Integration Framework

```lua
-- lua/devcontainer/plugin_integration/init.lua
local M = {}

-- Plugin integration registry
local integrations = {}

-- Definition of integration methods
M.integration_types = {
  COMMAND_FORWARD = "command_forward",    -- Forward commands to container
  REMOTE_PLUGIN = "remote_plugin",        -- Execute as remote plugin
  HYBRID = "hybrid",                      -- Combination of both
  NATIVE = "native"                       -- Execute on host side (no integration needed)
}

-- Register plugin integration
function M.register_integration(plugin_name, config)
  integrations[plugin_name] = {
    type = config.type or M.integration_types.COMMAND_FORWARD,
    patterns = config.patterns or {},
    setup = config.setup,
    teardown = config.teardown,
    handlers = config.handlers or {}
  }
end

-- Auto-detect integrations
function M.auto_detect_integrations()
  -- Detect installed plugins
  -- Set up automatic integration for known plugins
  local known_integrations = require('devcontainer.plugin_integration.registry')
  
  for plugin_name, integration_config in pairs(known_integrations) do
    if M.is_plugin_available(plugin_name) then
      M.register_integration(plugin_name, integration_config)
    end
  end
end
```

#### 2. Command Forwarding Extension

```lua
-- lua/devcontainer/plugin_integration/command_forward.lua
local M = {}

-- Create command wrapper
function M.create_wrapper(original_cmd, container_id)
  return function(...)
    local args = {...}
    local docker = require('devcontainer.docker')
    
    -- Transform command to execute within container
    local container_cmd = M.transform_command(original_cmd, args)
    
    -- Execute and get results
    local result = docker.exec_command(container_id, container_cmd)
    
    -- Transform results to Neovim format
    return M.transform_result(result)
  end
end

-- Generic command transformation
function M.wrap_plugin_commands(plugin_name, command_patterns)
  local original_commands = {}
  
  for _, pattern in ipairs(command_patterns) do
    -- Save original command
    original_commands[pattern] = vim.api.nvim_get_commands({})[pattern]
    
    -- Replace with wrapper
    vim.api.nvim_create_user_command(pattern, function(opts)
      M.execute_in_container(pattern, opts)
    end, { nargs = '*', complete = 'file' })
  end
  
  return original_commands
end
```

#### 3. Remote Plugin Host

```lua
-- lua/devcontainer/plugin_integration/remote_host.lua
local M = {}

-- Start remote plugin host in container
function M.start_remote_host(container_id)
  local docker = require('devcontainer.docker')
  
  -- Remote plugin host setup script
  local setup_script = [[
    # Neovim remote plugin host setup
    pip install pynvim
    npm install -g neovim
    
    # Start the remote plugin host
    nvim --headless --cmd "let g:devcontainer_mode='remote'" \
         --cmd "call remote#host#Start()" &
  ]]
  
  docker.exec_command(container_id, setup_script, { detach = true })
  
  -- Establish RPC channel
  local channel = M.establish_rpc_channel(container_id)
  
  return channel
end

-- Remote execution of plugins
function M.register_remote_plugin(plugin_path, channel)
  -- Register as remote plugin
  vim.fn.remote#host#RegisterPlugin(
    'devcontainer_' .. plugin_path,
    channel
  )
end
```

#### 4. Integration Templates

##### vim-test Integration Example

```lua
-- lua/devcontainer/plugin_integration/plugins/vim_test.lua
local M = {}

M.config = {
  type = "command_forward",
  patterns = {
    "Test*",
    "VimTest*"
  },
  
  setup = function(container_id)
    -- Configure vim-test custom strategy
    vim.g['test#custom_strategies'] = {
      devcontainer = function(cmd)
        local docker = require('devcontainer.docker')
        return docker.exec_command(container_id, cmd, {
          interactive = true,
          stream = true
        })
      end
    }
    
    -- Set default strategy to devcontainer
    vim.g['test#strategy'] = 'devcontainer'
  end,
  
  teardown = function()
    -- Cleanup
    vim.g['test#strategy'] = nil
    vim.g['test#custom_strategies'] = nil
  end
}

return M
```

##### nvim-dap Integration Example

```lua
-- lua/devcontainer/plugin_integration/plugins/nvim_dap.lua
local M = {}

M.config = {
  type = "hybrid",  -- Combination of command forwarding and port forwarding
  
  setup = function(container_id)
    local dap = require('dap')
    local docker = require('devcontainer.docker')
    
    -- Modify debug adapter configuration
    for lang, configs in pairs(dap.configurations) do
      for i, config in ipairs(configs) do
        -- Start debugger in container
        if config.type == "executable" then
          config.program = M.wrap_debugger_command(config.program, container_id)
        end
        
        -- Configure port forwarding
        if config.port then
          config.port = M.forward_debug_port(config.port, container_id)
        end
      end
    end
  end,
  
  handlers = {
    -- Processing when debug session starts
    before_start = function(config, container_id)
      -- Forward necessary ports
      M.setup_debug_ports(config, container_id)
    end,
    
    -- Path mapping
    resolve_path = function(path, container_id)
      return M.map_path_to_container(path, container_id)
    end
  }
}

return M
```

### Implementation Roadmap

#### Phase 1: Extended Command Forwarding (2-3 weeks)

1. **Plugin Integration Framework Foundation Implementation**
   - Integration registry
   - Auto-detection system
   - Basic command wrapper

2. **Integration Template Creation for Major Plugins**
   - vim-test / nvim-test
   - vim-fugitive (Git operations)
   - telescope.nvim (file search)

3. **Integration API Publication**
   - API for third-party plugin developers
   - Integration guideline documentation

#### Phase 2: Remote Plugin Support (3-4 weeks)

1. **Remote Plugin Host Implementation**
   - Host startup within container
   - RPC channel management
   - Error handling

2. **Integration of Complex Plugins**
   - nvim-dap (debugger)
   - nvim-lspconfig (existing improvements)
   - nvim-treesitter (syntax parsing)

3. **Performance Optimization**
   - Communication efficiency
   - Caching strategy
   - Lazy loading

#### Phase 3: Smart Integration System (2-3 weeks)

1. **Automatic Selection of Integration Methods**
   - Analyze plugin characteristics
   - Automatically select optimal integration method
   - Fallback mechanisms

2. **Integration Customization**
   - User-defined integration rules
   - Plugin-specific settings
   - Enable/disable integration toggle

3. **Developer Tools**
   - Integration debugging tools
   - Performance profiling
   - Integration test framework

### Performance and Security Considerations

#### Performance Optimization

1. **Communication Minimization**
   - Batch processing
   - Result caching
   - Asynchronous execution

2. **Resource Management**
   - Connection pooling
   - Memory usage monitoring
   - Automatic termination of unnecessary processes

#### Security

1. **Permission Management**
   - Permission restrictions for container execution
   - File access control
   - Network access monitoring

2. **Data Protection**
   - Filtering of sensitive information
   - Communication encryption (as needed)
   - Log sanitization

### Summary

This hybrid architecture achieves the following:

1. **Incremental Implementation** - Gradually add advanced integration without breaking existing functionality
2. **Flexibility** - Choose optimal integration method for each plugin
3. **Performance** - Use optimal communication methods as needed
4. **Compatibility** - High compatibility with existing plugin ecosystem
5. **Extensibility** - Easy addition of new plugins and integration methods

This design enables functionality equivalent to VSCode's Remote Development extension in a form suited to Neovim's ecosystem.

