# container.nvim

A Neovim plugin that provides VSCode Dev Containers-like development experience.

> **⚠️ Development Status**: This plugin is under active development. Breaking changes may occur in future updates. Please check the documentation and release notes when upgrading.

## Features

- **devcontainer.json Support**: Fully compatible with VSCode configuration files
- **Automatic Image Building**: Automatic Docker image building and management
- **Enhanced Terminal Integration**: Advanced in-container terminal with session management
- **LSP Integration**: Automatic detection and configuration of LSP servers in containers with dynamic path transformation
- **DAP Integration**: Container-based debugging with nvim-dap support for multiple languages
- **Smart Port Forwarding**: Dynamic port allocation to prevent conflicts between projects
- **Test Integration**: Run tests in containers with vim-test, nvim-test, and neotest. Supports both buffer and terminal output modes
- **Asynchronous Operations**: All Docker operations executed asynchronously

## Requirements

- Neovim 0.8+
- Docker or Podman
- Git

## Installation

### lazy.nvim

```lua
{
  'ksoichiro/container.nvim',
  dependencies = {
    'nvim-lua/plenary.nvim', -- For async operations (future feature expansion)
  },
  config = function()
    require('container').setup({
      -- Configuration options
      log_level = 'info',
      container_runtime = 'docker', -- 'docker' or 'podman'
      auto_open = 'immediate', -- 'immediate' or 'off'
    })
  end,
}
```

#### With Test Plugin Integration

Test plugins can be installed independently and will be automatically detected:

```lua
{
  'ksoichiro/container.nvim',
  dependencies = { 'nvim-lua/plenary.nvim' },
  config = function()
    require('container').setup({
      test_integration = { enabled = true },
    })
  end,
},
{
  'vim-test/vim-test',
  lazy = true, -- Works with lazy loading
},
{
  'nvim-neotest/neotest',
  lazy = true, -- Deferred integration for lazy loading
  dependencies = {
    'nvim-neotest/neotest-go', -- Add adapters as needed
  },
}
```

### packer.nvim

```lua
use {
  'ksoichiro/container.nvim',
  requires = {
    'nvim-lua/plenary.nvim',
  },
  config = function()
    require('container').setup()
  end,
}
```

## Basic Usage

### 1. Create devcontainer.json

Create a `.devcontainer/devcontainer.json` file in your project root:

```json
{
  "name": "Node.js Development Environment",
  "dockerFile": "Dockerfile",
  "workspaceFolder": "/workspace",
  "mounts": [
    "source=${localWorkspaceFolder},target=/workspace,type=bind"
  ],
  "forwardPorts": [3000, 8080],
  "postCreateCommand": "npm install",
  "postStartCommand": "npm run dev",
  "remoteUser": "node"
}
```

### 2. Create Dockerfile

`.devcontainer/Dockerfile`:

```dockerfile
FROM node:18

# Install necessary tools
RUN apt-get update && apt-get install -y \
    git \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /workspace

# Create user
RUN useradd -m -s /bin/bash node
USER node
```

### 3. Start devcontainer

By default, container.nvim automatically detects `devcontainer.json` and opens the container when you start Neovim. If you want to control this manually:

```vim
:ContainerOpen    " Parse devcontainer.json and prepare container
:ContainerBuild   " Build the container image  
:ContainerStart   " Start the container
```

To disable automatic opening:
```vim
:ContainerAutoOpen off
```

## Commands

For detailed command documentation, use `:help container-commands` in Neovim.

### Basic Operations

| Command | Description |
|---------|-------------|
| `:ContainerOpen [path]` | Open devcontainer |
| `:ContainerBuild` | Build image |
| `:ContainerStart` | Start container |
| `:ContainerStop` | Stop container |
| `:ContainerKill[!]` | Kill container (immediate termination, requires confirmation unless `!` is used) |
| `:ContainerTerminate[!]` | Terminate container (immediate termination, requires confirmation unless `!` is used) |
| `:ContainerRemove[!]` | Remove stopped container (requires confirmation unless `!` is used) |
| `:ContainerStopRemove[!]` | Stop and remove container (requires confirmation unless `!` is used) |
| `:ContainerRestart` | Restart container |

### Execution & Access

| Command | Description |
|---------|-------------|
| `:ContainerExec <command>` | Execute command in container |

### Enhanced Terminal Integration

| Command | Description |
|---------|-------------|
| `:ContainerTerminal [options]` | Open enhanced terminal with session management |
| `:ContainerTerminalNew [name]` | Create new terminal session |
| `:ContainerTerminalList` | List all terminal sessions |
| `:ContainerTerminalClose [name]` | Close terminal session |
| `:ContainerTerminalCloseAll` | Close all terminal sessions |
| `:ContainerTerminalRename <old> <new>` | Rename terminal session |
| `:ContainerTerminalNext` | Switch to next terminal session |
| `:ContainerTerminalPrev` | Switch to previous terminal session |
| `:ContainerTerminalStatus` | Show terminal system status |
| `:ContainerTerminalCleanup [days]` | Clean up old terminal history files |

### Information Display

| Command | Description |
|---------|-------------|
| `:ContainerStatus` | Show container status |
| `:ContainerLogs` | Show container logs |
| `:ContainerConfig` | Show configuration |

### LSP Integration

| Command | Description |
|---------|-------------|
| `:ContainerLspHover [server]` | Show hover information using container LSP |
| `:ContainerLspDefinition [server]` | Go to definition using container LSP |
| `:ContainerLspReferences [server]` | Find references using container LSP |
| `:ContainerLspSetupKeys [server]` | Manually setup LSP keybindings for current buffer |

**Note**: LSP commands automatically handle path transformation between host and container. When gopls is detected in a container, the plugin attempts to automatically map standard LSP keybindings (K, gd, gr) to container-aware commands for Go files. If automatic setup doesn't work, use `:ContainerLspSetupKeys` to manually configure keybindings.

### Configuration Management

| Command | Description |
|---------|-------------|
| `:ContainerAutoOpen [mode]` | Configure auto-open behavior (`immediate` or `off`) |

### LSP Integration

| Command | Description |
|---------|-------------|
| `:ContainerLspStatus` | Show LSP server status |
| `:ContainerLspSetup` | Setup LSP servers in container |

### Port Management

| Command | Description |
|---------|-------------|
| `:ContainerPorts` | Show detailed port forwarding information |
| `:ContainerPortStats` | Show port allocation statistics |

### Picker Integration

| Command | Description |
|---------|-------------|
| `:ContainerPicker` | Open devcontainer picker (supports telescope, fzf-lua, vim.ui.select) |
| `:ContainerSessionPicker` | Open terminal session picker |
| `:ContainerPortPicker` | Open port management picker |
| `:ContainerHistoryPicker` | Open command history picker |

### Test Integration

container.nvim supports running tests in containers with two output modes:

#### Buffer Mode (Default Commands)
| Command | Description |
|---------|-------------|
| `:ContainerTestNearest` | Run nearest test in container (output in buffer) |
| `:ContainerTestFile` | Run all tests in current file in container (output in buffer) |
| `:ContainerTestSuite` | Run entire test suite in container (output in buffer) |

#### Terminal Mode (Interactive Commands)
| Command | Description |
|---------|-------------|
| `:ContainerTestNearestTerminal` | Run nearest test in container terminal |
| `:ContainerTestFileTerminal` | Run all tests in current file in container terminal |
| `:ContainerTestSuiteTerminal` | Run entire test suite in container terminal |

#### Setup & Integration
| Command | Description |
|---------|-------------|
| `:ContainerTestSetup` | Setup test plugin integrations |

**Output Modes:**
- **Buffer Mode**: Tests run asynchronously with output displayed in Neovim's message area. Shows container indicators (🐳) and completion status.
- **Terminal Mode**: Tests run interactively in a dedicated terminal window. Silent execution with all output appearing in the terminal. Reuses the same terminal session for repeated runs.

**Plugin Detection:**
container.nvim automatically detects installed test plugins without requiring them to be loaded:
- **vim-test/nvim-test**: Only installation required - integration works with lazy loading
- **neotest**: Requires loading for full integration, but provides deferred setup for lazy loading
- **Fallback**: Manual test commands work independently of any test plugin

### DAP Integration

container.nvim provides seamless debugging integration with nvim-dap for running debuggers in containers.

#### Commands
| Command | Description |
|---------|-------------|
| `:ContainerDapStart [language]` | Start debugging in container (auto-detects language if not specified) |
| `:ContainerDapStop` | Stop active debugging session |
| `:ContainerDapStatus` | Show current debugging status |
| `:ContainerDapSessions` | List all active debug sessions |

#### Supported Languages
- **Python**: Uses debugpy with automatic port forwarding
- **JavaScript/TypeScript**: Node.js debugging with inspect protocol
- **Go**: Delve debugger integration
- **Rust**: rust-lldb integration
- **C/C++**: GDB/LLDB support
- **Java**: JDB integration

#### Features
- **Automatic Configuration**: DAP adapters are automatically configured when containers start
- **Configurable Debug Ports**: Customizable ports for different languages to avoid conflicts
- **Port Forwarding**: Debug ports are automatically forwarded from container to host
- **Language Detection**: Automatically detects project language for appropriate debugger setup
- **Session Management**: Multiple concurrent debug sessions with different containers
- **Path Mapping**: Automatic path mapping between host and container for breakpoints

#### Configuration

The DAP integration can be customized with various options:

```lua
require('container').setup({
  dap = {
    auto_setup = true,           -- Auto-setup DAP adapters on container start
    auto_start_debugger = true,  -- Auto-start debugger servers (e.g., dlv for Go)
    ports = {
      go = 2345,      -- Port for Go/delve debugger
      python = 5678,  -- Port for Python debugger  
      node = 9229,    -- Port for Node.js debugger
      java = 5005,    -- Port for Java debugger
    },
    path_mappings = {
      container_workspace = '/workspace',  -- Fallback workspace path  
      auto_detect_workspace = true,        -- Auto-detect from devcontainer.json
    },
  },
})
```

**Important**: Add debug ports to your `.devcontainer/devcontainer.json` file:

```json
{
  "forwardPorts": [8080, 2345],  // 2345 for Go debugging
  // ... other settings
}
```

#### Example Usage
```vim
" Start debugging (auto-detect language)
:ContainerDapStart

" Start debugging with specific language
:ContainerDapStart python

" Check debugging status
:ContainerDapStatus

" List active sessions
:ContainerDapSessions
```

#### Go Debugging Example

For Go projects, delve is automatically configured:

1. **Install delve in your container**:
   ```bash
   go install github.com/go-delve/delve/cmd/dlv@latest
   ```

2. **Configure port forwarding** in `.devcontainer/devcontainer.json`:
   ```json
   {
     "forwardPorts": [2345],
     // ... other settings
   }
   ```

3. **Start debugging**:
   ```vim
   :ContainerDapStart go
   " Or use :DapNew and select "Container: Attach to dlv"
   ```

#### Port Conflicts

If default ports conflict with your services, customize them:

```lua
require('container').setup({
  dap = {
    ports = { go = 3456 }  -- Use different port
  }
})
```

Update your devcontainer.json accordingly:
```json
{ "forwardPorts": [8080, 3456] }
```

#### Requirements
- nvim-dap plugin must be installed
- Appropriate debugger tools must be available in the container (e.g., debugpy for Python, dlv for Go)
- Debug ports must be forwarded in devcontainer.json

### Management

| Command | Description |
|---------|-------------|
| `:ContainerAutoOpen [mode]` | Configure auto-open behavior (`immediate` or `off`) |
| `:ContainerReset` | Reset plugin state |
| `:ContainerDebug` | Show comprehensive debug information |
| `:ContainerReconnect` | Reconnect to existing devcontainer |

## Configuration

### Default Configuration

```lua
require('container').setup({
  -- Basic settings
  auto_open = 'immediate', -- 'immediate', 'off' - behavior when devcontainer.json is detected
  auto_open_delay = 2000,  -- milliseconds to wait before auto-open
  log_level = 'info',
  container_runtime = 'docker', -- 'docker' or 'podman'

  -- UI settings
  ui = {
    picker = 'telescope', -- 'telescope', 'fzf-lua', 'vim.ui.select'
    show_notifications = true,
    notification_level = 'normal', -- 'verbose', 'normal', 'minimal', 'silent'
    status_line = true,
    icons = {
      container = "🐳",
      running = "✅",
      stopped = "⏹️",
      building = "🔨",
      error = "❌",
    },
  },

  -- Enhanced terminal settings
  terminal = {
    default_shell = '/bin/bash',
    auto_insert = true,              -- Auto enter insert mode
    close_on_exit = false,          -- Keep buffer after process exit
    persistent_history = true,       -- Save history across sessions
    max_history_lines = 10000,      -- Max lines in history

    -- Terminal positioning
    default_position = 'split',      -- 'split', 'tab', 'float'

    -- Split command for positioning and sizing
    -- Controls both horizontal/vertical positioning and window size
    split_command = 'belowright',    -- Default: open splits below current window

    -- Common examples:
    -- 'botright 20'               - Bottom right with 20 lines height
    -- 'topleft 15'                - Top left with 15 lines height  
    -- 'vertical rightbelow 80'    - Vertical split right with 80 columns
    -- 'vertical leftabove'        - Vertical split left
    -- 'rightbelow'                - Below current window
    -- 'leftabove'                 - Above current window

    -- Float configuration
    float = {
      width = 0.8,                  -- Ratio of editor width
      height = 0.6,                 -- Ratio of editor height
      border = 'rounded',           -- Border style
    },

    -- Terminal keybindings
    keymaps = {
      close = '<C-q>',              -- Close terminal
      escape = '<C-\\><C-n>',       -- Exit terminal mode
      new_session = '<leader>tn',   -- Create new session
      list_sessions = '<leader>tl', -- List sessions
    },
  },

  -- Port forwarding with dynamic allocation
  port_forwarding = {
    auto_forward = true,
    notification = true,
    common_ports = {3000, 8080, 5000, 3001},
    -- Dynamic port allocation settings
    enable_dynamic_ports = true,
    port_range_start = 10000,
    port_range_end = 20000,
    conflict_resolution = 'auto', -- 'auto', 'prompt', 'error'
  },

  -- Workspace settings
  workspace = {
    auto_mount = true,
    mount_point = '/workspace',
    exclude_patterns = { '.git', 'node_modules', '.next' },
  },

  -- Test integration settings
  test_integration = {
    enabled = true,           -- Enable test plugin integration
    auto_setup = true,        -- Auto-setup when container starts
    output_mode = 'buffer',   -- Default output mode: 'buffer' or 'terminal'
  },
})
```

### Advanced Configuration System

The plugin provides a robust configuration system with multiple ways to customize settings:

#### Configuration Management Commands

```vim
" Show current configuration
:ContainerConfig

" Reload configuration
:ContainerConfig reload

" Reset to defaults
:ContainerConfig reset

" Validate configuration
:ContainerConfig validate

" Show environment variable options
:ContainerConfig env

" Save configuration to file
:ContainerConfig save ~/.config/container/config.lua

" Load configuration from file
:ContainerConfig load ~/.config/container/config.lua

" Watch configuration file for changes
:ContainerConfig watch

" Get specific configuration value
:ContainerConfig terminal.default_shell

" Set configuration value
:ContainerConfigSet terminal.default_shell /bin/zsh
:ContainerConfigSet lsp.port_range [9000,10000]
```

#### Project-specific Configuration

Create a `.container.nvim.lua` file in your project root:

```lua
-- .container.nvim.lua
return {
  log_level = 'debug',
  terminal = {
    default_shell = '/bin/zsh',
  },
  port_forwarding = {
    common_ports = { 3000, 8080 },
  },
}
```

This file is automatically loaded and takes precedence over user configuration.

#### Environment Variable Overrides

You can override configuration using environment variables:

```bash
# Basic settings
export DEVCONTAINER_AUTO_START=true
export DEVCONTAINER_LOG_LEVEL=debug
export DEVCONTAINER_CONTAINER_RUNTIME=podman

# Terminal settings
export DEVCONTAINER_TERMINAL_SHELL=/bin/zsh
export DEVCONTAINER_TERMINAL_POSITION=float

# Port forwarding
export DEVCONTAINER_PORT_COMMON=3000,8080,5000
export DEVCONTAINER_PORT_AUTO_FORWARD=false

# UI settings
export DEVCONTAINER_UI_PICKER=fzf-lua
export DEVCONTAINER_UI_NOTIFICATION_LEVEL=minimal
```

Run `:ContainerConfig env` to see all available environment variables.

#### Configuration Priority

Configuration is loaded in this order (later sources override earlier ones):

1. Default configuration
2. Environment variables
3. User configuration (from `setup()`)
4. Project configuration (`.container.nvim.lua`)

#### Configuration Validation

The plugin validates all configuration values to ensure they are correct:

- Type checking (boolean, number, string, array)
- Enum validation (valid options for specific fields)
- Range validation (port numbers, percentages)
- Path validation (mount points, directories)
- Cross-field validation (port ranges, dependencies)

#### Live Configuration Reload

Configuration changes can be applied without restarting Neovim:

- Manual reload: `:ContainerConfig reload`
- Automatic reload: `:ContainerConfig watch` monitors `.container.nvim.lua`
- Event-based: Other modules react to `ContainerConfigReloaded` event

## Dev Container Specification Compatibility

Container.nvim is designed to be compatible with the [official Dev Container specification](https://containers.dev/) while providing additional features for enhanced Neovim development experience.

### Standard Compliance

All standard devcontainer.json properties are fully supported:
- ✅ Basic properties: `name`, `image`, `dockerFile`, `build`
- ✅ Port forwarding: `forwardPorts`, `portsAttributes`
- ✅ Environment: `containerEnv`, `remoteEnv`
- ✅ Lifecycle: `postCreateCommand` (string or array), `postStartCommand`, `postAttachCommand`
- ✅ Workspace: `mounts`, `workspaceFolder`, `remoteUser`

### Extended Features

Container.nvim extends the specification with additional features in the `customizations.container.nvim` section:

#### Dynamic Port Allocation
```json
{
  "forwardPorts": [3000, 8080],
  "customizations": {
    "container.nvim": {
      "dynamicPorts": ["auto:3001", "range:8000-8010:5000"]
    }
  }
}
```

#### Environment Variables

container.nvim supports standard Dev Container environment variables:

```json
{
  "name": "Go Project",
  "image": "mcr.microsoft.com/devcontainers/go:1-1.24-bookworm",

  // Standard container environment (used during container creation)
  "containerEnv": {
    "GO111MODULE": "on",
    "GOPATH": "/go",
    "PATH": "/usr/local/go/bin:${containerEnv:PATH}",
    "HOME_VAR": "${containerEnv:HOME}",
    "USER_VAR": "${containerEnv:USER}"
  },

  // Standard remote environment (used during development)
  "remoteEnv": {
    "GOPATH": "/go",
    "GOPLS_FLAGS": "-debug",
    "PATH": "/usr/local/go/bin:${remoteEnv:PATH}"
  },

  // Optional: Language presets for backward compatibility
  "customizations": {
    "container.nvim": {
      "languagePreset": "go"
    }
  }
}
```

**Environment Variable Expansion:**
- `${containerEnv:VAR}` expands during container creation
- `${remoteEnv:VAR}` expands during remote operations
- Fallback values provided for common variables (PATH, HOME, USER, SHELL, TERM)

#### Post-Creation Commands

container.nvim supports both string and array formats for `postCreateCommand`:

```json
{
  // String format (simple command)
  "postCreateCommand": "npm install && npm run build",

  // Array format (multiple commands)
  "postCreateCommand": [
    "echo 'Starting post-create setup'",
    "npm install",
    "npm run build",
    "echo 'Post-create setup completed'"
  ]
}
```

**Array Format Features:**
- Commands are executed sequentially with `&&` joining
- Automatic error tolerance with `set +e` prefix
- Individual command logging for better debugging
- Supports complex multi-step setup processes

**Standard vs Legacy:**
- ✅ **Standard**: Use `containerEnv` and `remoteEnv` for better VSCode compatibility
- ⚠️ **Legacy**: Custom `postCreateEnvironment`, `execEnvironment`, `lspEnvironment` are deprecated but still supported with automatic migration

### VSCode Compatibility

Your devcontainer.json files remain fully compatible with VSCode:
- VSCode ignores container.nvim customizations
- Standard properties work in both tools
- Teams can use their preferred editor

For detailed compatibility information, see [docs/DEVCONTAINER_COMPATIBILITY.md](docs/DEVCONTAINER_COMPATIBILITY.md).

## StatusLine Integration

The plugin provides built-in statusline integration to display devcontainer status in your Neovim statusline.

### Configuration

Enable statusline integration in your configuration:

```lua
require('container').setup({
  ui = {
    status_line = true,  -- Enable statusline integration
    icons = {
      container = "🐳",
      running = "✅",
      stopped = "⏹️",
      building = "🔨",
      error = "❌",
    },
    statusline = {
      -- Customize display format using {icon}, {name}, {status} variables
      format = {
        running = '{icon} {name}',                    -- Default: "✅ MyProject"
        stopped = '{icon} {name}',                    -- Default: "⏹️ MyProject"
        available = '{icon} {name} (available)',      -- Default: "⏹️ MyProject (available)"
        building = '{icon} {name}',                   -- Default: "🔨 MyProject"
        error = '{icon} {name}',                      -- Default: "❌ MyProject"
      },
      labels = {
        container_name = 'DevContainer',   -- Fallback name when container name unavailable
        available_suffix = 'available',    -- Text for "(available)" suffix
      },
      show_container_name = true,          -- Use actual container name vs generic label
      default_format = '{icon} {name}',    -- Fallback format
    },
  },
})
```

### Customization Examples

#### Minimal Display (Icons Only)
```lua
require('container').setup({
  ui = {
    status_line = true,
    statusline = {
      format = {
        running = '{icon}',
        stopped = '{icon}',
        available = '{icon}',
        building = '{icon}',
        error = '{icon}',
      },
    },
  },
})
```

#### Custom Text Labels
```lua
require('container').setup({
  ui = {
    status_line = true,
    icons = {
      running = "🟢",
      stopped = "🔴",
      building = "🟡",
    },
    statusline = {
      format = {
        running = '{icon} Container: {name}',
        stopped = '{icon} Container: {name}',
        available = '{icon} Available: {name}',
      },
      labels = {
        container_name = 'Docker',
        available_suffix = 'ready',
      },
    },
  },
})
```

#### Status-Based Display
```lua
require('container').setup({
  ui = {
    status_line = true,
    statusline = {
      format = {
        running = '🚀 {name} ({status})',              -- "🚀 MyProject (running)"
        stopped = '💤 {name} ({status})',              -- "💤 MyProject (stopped)"
        available = '📦 {name} - ready to start',      -- "📦 MyProject - ready to start"
        building = '⚙️ {name} ({status})',              -- "⚙️ MyProject (building)"
      },
    },
  },
})
```

### Usage Examples

#### Manual StatusLine Configuration

```lua
-- In your statusline configuration
local function devcontainer_status()
  return require('container').statusline()
end

-- Example with vim.o.statusline
vim.o.statusline = '%f %{luaeval("require(\"container\").statusline()")} %='
```

#### Lualine Integration

```lua
require('lualine').setup({
  sections = {
    lualine_c = {
      'filename',
      require('container').statusline_component(),
    }
  }
})
```

**Progress Display**: During container operations (e.g., stopping), the statusline will show progress indicators:
- `⏹️ ⠋ Stopping...` (with animated spinner)
- Icons and animation indicate operation status in real-time

#### Lightline Integration

```vim
let g:lightline = {
  \ 'active': {
  \   'left': [ [ 'mode', 'paste' ],
  \           [ 'readonly', 'filename', 'modified', 'devcontainer' ] ]
  \ },
  \ 'component_function': {
  \   'devcontainer': 'DevcontainerStatus'
  \ },
  \ }

function! DevcontainerStatus()
  return luaeval('require("container.ui.statusline").lightline_component()')
endfunction
```

### Status Display

The statusline shows:
- **✅ DevContainer** - Running container
- **⏹️ DevContainer** - Stopped container  
- **⏹️ DevContainer (available)** - devcontainer.json exists but no container
- Empty - No devcontainer configuration

## Dynamic Port Allocation

The plugin supports advanced port forwarding with dynamic allocation to prevent conflicts between multiple projects.

### Port Specification Formats

```json
{
  "forwardPorts": [3000, 8080],
  "customizations": {
    "container.nvim": {
      "dynamicPorts": [
        "auto:3001",            // Auto-allocate available port
        "range:8000-8010:3002"  // Allocate from specific range
      ]
    }
  }
}
```

### Benefits

- **Conflict Prevention**: Multiple projects can run simultaneously without port conflicts
- **Automatic Allocation**: No need to manually manage port assignments
- **Project Isolation**: Each project gets its own port allocation space
- **Easy Monitoring**: Use `:ContainerPorts` and `:ContainerPortStats` to monitor usage

### Usage Examples

Multi-project development:
```json
// Project A
{
  "forwardPorts": [3000, 8080],
  "customizations": {
    "container.nvim": {
      "dynamicPorts": ["auto:3000", "auto:8080"]
    }
  }
}

// Project B  
{
  "forwardPorts": [3000, 8080],
  "customizations": {
    "container.nvim": {
      "dynamicPorts": ["auto:3000", "auto:8080"]
    }
  }
}
```

Both projects can run simultaneously with automatically assigned unique ports.

## Third-Party Plugin Integration

container.nvim seamlessly integrates with popular Neovim plugins to enhance your development workflow within containers.

### Picker Integration

The plugin supports multiple picker backends for an enhanced UI experience:

#### Available Pickers

- **`telescope`**: Full-featured picker with preview and advanced actions (requires `nvim-telescope/telescope.nvim`)
- **`fzf-lua`**: Fast and lightweight picker with similar features (requires `ibhagwan/fzf-lua`)
- **`vim.ui.select`**: Built-in Neovim picker (always available, basic functionality)

#### Configuration

```lua
require('container').setup({
  ui = {
    picker = 'telescope', -- Choose your preferred picker
  }
})
```

#### Picker-Specific Features

**Telescope**
- Full preview functionality
- Advanced filtering and sorting
- Custom key bindings (e.g., `<C-d>` to delete sessions)

**fzf-lua**
- Extremely fast performance
- Built-in preview
- Key bindings: `<C-y>` (copy), `<C-x>` (delete), `<C-e>` (edit)

**vim.ui.select**
- No external dependencies
- Basic selection functionality
- Fallback when other pickers are unavailable

#### Examples

```lua
-- Use fzf-lua for faster performance
require('container').setup({
  ui = { picker = 'fzf-lua' }
})

-- Use vim.ui.select for minimal setup
require('container').setup({
  ui = { picker = 'vim.ui.select' }
})

-- Auto-fallback: telescope -> fzf-lua -> vim.ui.select
require('container').setup({
  ui = { picker = 'telescope' } -- Will fallback if telescope not available
})
```

### Test Plugin Integration

container.nvim automatically integrates with popular test runner plugins to execute tests within containers, ensuring consistent test environments.

#### Supported Test Plugins

- **vim-test/vim-test**: Classic Vim test runner
- **klen/nvim-test**: Neovim-specific test runner  
- **nvim-neotest/neotest**: Modern test framework with rich features

#### Lazy Loading Support

Test plugins can be lazy-loaded and will be automatically detected when needed:

```lua
-- Example with lazy.nvim
{
  'ksoichiro/container.nvim',
  dependencies = { 'nvim-lua/plenary.nvim' },
  config = function()
    require('container').setup({
      test_integration = { enabled = true },
    })
  end,
},
{
  'vim-test/vim-test',
  lazy = true, -- Works with lazy loading
},
{
  'nvim-neotest/neotest',
  lazy = true, -- Deferred integration for lazy loading
  dependencies = {
    'nvim-neotest/neotest-go', -- Add adapters as needed
  },
}
```

#### Automatic Plugin Detection

container.nvim automatically detects and integrates with test plugins:

- Already loaded plugins are detected immediately
- Installed but not loaded plugins (lazy.nvim) are loaded on-demand
- Manual fallback commands work without any test plugin

#### Test Commands

| Command | Description |
|---------|-------------|
| `:ContainerTestNearest [mode]` | Run nearest test in container |
| `:ContainerTestFile [mode]` | Run all tests in current file |
| `:ContainerTestSuite [mode]` | Run entire test suite |
| `:ContainerTestSetup` | Setup test plugin integrations |

**Output Modes:**
- `buffer`: Tests run asynchronously with output in Neovim's message area
- `terminal`: Tests run interactively in a dedicated terminal window

#### Language Support

Built-in test command patterns for:
- Go: `go test`
- Python: `pytest`
- JavaScript/TypeScript: `npm test`
- Rust: `cargo test`

Custom test patterns can be added for other languages.

### LSP Integration

container.nvim provides seamless LSP integration for development within containers:

#### Automatic LSP Detection

- Automatically detects language servers installed in containers
- Configures LSP clients to connect to container-based servers
- Supports popular language servers: gopls, pylsp, pyright, tsserver, lua_ls, rust_analyzer, clangd, jdtls, solargraph, intelephense

#### LSP Commands

| Command | Description |
|---------|-------------|
| `:ContainerLspStatus [detailed]` | Show LSP server status |
| `:ContainerLspSetup` | Manually setup LSP servers |
| `:ContainerLspDiagnose` | Comprehensive LSP health check |
| `:ContainerLspRecover` | Recover from LSP failures |
| `:ContainerLspRetry {server}` | Retry specific server setup |

#### Requirements

- nvim-lspconfig (recommended for full LSP integration)
- Language servers installed within the container

### Statusline Integration

Built-in statusline integration works with popular statusline plugins:

#### Lualine Integration

```lua
require('lualine').setup({
  sections = {
    lualine_c = {
      'filename',
      require('container').statusline_component(),
    }
  }
})
```

**Progress Display**: During container operations (e.g., stopping), the statusline will show progress indicators:
- `⏹️ ⠋ Stopping...` (with animated spinner)
- Icons and animation indicate operation status in real-time

#### Lightline Integration

```vim
let g:lightline = {
  \ 'active': {
  \   'left': [ [ 'mode', 'paste' ],
  \           [ 'readonly', 'filename', 'modified', 'devcontainer' ] ]
  \ },
  \ 'component_function': {
  \   'devcontainer': 'DevcontainerStatus'
  \ },
  \ }

function! DevcontainerStatus()
  return luaeval('require("container.ui.statusline").lightline_component()')
endfunction
```

#### Custom Statusline

```lua
-- In your statusline configuration
local function devcontainer_status()
  return require('container').statusline()
end

-- Example with vim.o.statusline
vim.o.statusline = '%f %{luaeval("require(\"container\").statusline()")} %='
```

### Plugin Manager Compatibility

container.nvim is compatible with all major Neovim plugin managers:

#### lazy.nvim
```lua
{
  'ksoichiro/container.nvim',
  dependencies = { 'nvim-lua/plenary.nvim' },
  config = function()
    require('container').setup()
  end,
}
```

#### packer.nvim
```lua
use {
  'ksoichiro/container.nvim',
  requires = { 'nvim-lua/plenary.nvim' },
  config = function()
    require('container').setup()
  end,
}
```

#### vim-plug
```vim
Plug 'nvim-lua/plenary.nvim'
Plug 'ksoichiro/container.nvim'
```

### Plugin Extension Points

container.nvim provides extension points for other plugin developers:

#### User Events

The plugin triggers User autocmd events for integration:

```lua
vim.api.nvim_create_autocmd('User', {
  pattern = 'DevcontainerStarted',
  callback = function(args)
    local data = args.data or {}
    print('Container started: ' .. (data.container_name or 'unknown'))
  end,
})
```

Available events: `DevcontainerOpened`, `DevcontainerBuilt`, `DevcontainerStarted`, `DevcontainerStopped`, `DevcontainerClosed`

#### Configuration API

Runtime configuration management for dynamic plugin interaction:

```lua
local container = require('container')

-- Get current configuration
local config = container.get_config()

-- Update configuration at runtime
container.config_set('terminal.default_shell', '/bin/zsh')

-- Watch for configuration changes
vim.api.nvim_create_autocmd('User', {
  pattern = 'ContainerConfigReloaded',
  callback = function()
    -- React to configuration changes
  end,
})
```

## Notification Levels

Control the verbosity of plugin notifications with the `notification_level` setting:

### Available Levels

- **`verbose`**: Show all notifications (debug, info, warnings, errors)
- **`normal`** (default): Show important notifications (critical operations, container events, warnings)
- **`minimal`**: Show only essential notifications (critical operations, container lifecycle)
- **`silent`**: Show only error messages

### Configuration

```lua
require('container').setup({
  ui = {
    notification_level = 'normal', -- Change to your preferred level
  }
})
```

### Notification Categories

The plugin categorizes notifications into:

- **Critical**: Fatal errors and important operations requiring user attention
- **Container**: Container lifecycle events (start, stop, build)
- **Terminal**: Terminal session management notifications
- **UI**: User interface feedback (copy confirmations, selections)
- **Status**: Status information and routine operation feedback

### Examples

```lua
-- Minimal notifications (quiet development)
require('container').setup({
  ui = { notification_level = 'minimal' }
})

-- Verbose notifications (debugging/development)
require('container').setup({
  ui = { notification_level = 'verbose' }
})

-- Silent mode (errors only)
require('container').setup({
  ui = { notification_level = 'silent' }
})
```

## Lua API

For programmatic access to the plugin:

```lua
-- Basic operations
require('container').open()
require('container').build()
require('container').start()
require('container').stop()

-- Command execution
require('container').exec('npm test')

-- Enhanced terminal functions
require('container').terminal({ name = 'dev', position = 'float' })
require('container').terminal_new('build')
require('container').terminal_list()
require('container').terminal_close('dev')

-- Information retrieval
local status = require('container').status()
local config = require('container').get_config()
local container_id = require('container').get_container_id()
```

## devcontainer.json Examples

### Node.js Project

```json
{
  "name": "Node.js Development",
  "dockerFile": "Dockerfile",
  "context": "..",
  "workspaceFolder": "/workspace",
  "mounts": [
    "source=${localWorkspaceFolder},target=/workspace,type=bind,consistency=cached"
  ],
  "forwardPorts": [3000, 8080, 9229],
  "portsAttributes": {
    "3000": {
      "label": "Frontend",
      "onAutoForward": "notify"
    },
    "9229": {
      "label": "Node Debug",
      "onAutoForward": "silent"
    }
  },
  "postCreateCommand": "npm install",
  "postStartCommand": "npm run dev",
  "customizations": {
    "container.nvim": {
      "dynamicPorts": ["auto:8080", "range:9000-9100:9229"]
    },
    "neovim": {
      "settings": {
        "editor.tabSize": 2,
        "editor.insertSpaces": true
      },
      "extensions": [
        "typescript-language-server",
        "eslint-language-server"
      ]
    }
  },
  "features": {
    "ghcr.io/devcontainers/features/node:1": {
      "version": "18"
    },
    "ghcr.io/devcontainers/features/git:1": {}
  },
  "remoteUser": "node"
}
```

### Python Project

```json
{
  "name": "Python Development",
  "image": "mcr.microsoft.com/devcontainers/python:3.11",
  "workspaceFolder": "/workspace",
  "mounts": [
    "source=${localWorkspaceFolder},target=/workspace,type=bind"
  ],
  "forwardPorts": [8000, 5000],
  "postCreateCommand": "pip install -r requirements.txt",
  "customizations": {
    "neovim": {
      "extensions": [
        "pylsp",
        "mypy"
      ]
    }
  },
  "features": {
    "ghcr.io/devcontainers/features/python:1": {
      "version": "3.11"
    }
  }
}
```

### Docker Compose Example

```json
{
  "name": "Web Application",
  "dockerComposeFile": "docker-compose.yml",
  "service": "web",
  "workspaceFolder": "/workspace",
  "forwardPorts": [3000, 8080],
  "postCreateCommand": "npm install && npm run setup"
}
```

## Troubleshooting

### Docker not available

```bash
# Check Docker status
docker --version
docker info

# Start Docker daemon
sudo systemctl start docker
```

### Container won't start

```vim
:ContainerLogs
:ContainerDebug
```

### Configuration file errors

```vim
:ContainerConfig
```

Use this command to check configuration and verify devcontainer.json syntax.

### Performance issues

- Use build cache
- Exclude unnecessary files with `.dockerignore`
- Adjust volume mount consistency settings

## Development Roadmap

### v0.2.1 (Current)
- ✅ Basic devcontainer operations
- ✅ Docker integration
- ✅ LSP server integration
- ✅ Enhanced terminal integration with session management
- ✅ Smart port forwarding with dynamic allocation

### v0.4.0 (Next)
- 📋 Port forwarding UI improvements
- 📋 Telescope integration
- 📋 External plugin integration (nvim-test, nvim-dap)

### v0.5.0 (Planned)
- 📋 Multi-container support
- 📋 Docker Compose integration
- 📋 Advanced networking features

### v1.0.0 (Goal)
- 📋 Complete VSCode compatibility
- 📋 Comprehensive testing
- 📋 Complete documentation

## Testing

The project includes test suites to verify functionality:

### Running Tests

```bash
# Run basic tests (requires standard Lua)
cd test
lua test_mock.lua

# Run comprehensive tests (requires standard Lua)
lua test_basic.lua
```

### Test Coverage

- **Module loading tests** - Verify all Lua modules load correctly
- **Configuration tests** - Test configuration loading and merging
- **Path conversion tests** - Test local/container path mapping
- **LSP module tests** - Verify LSP integration structure

## Development

### Prerequisites

- Neovim 0.8+
- Docker or Podman
- luacheck (for linting)

### Setup Development Environment

```bash
# One-time setup: install development dependencies and pre-commit hooks
make install-dev
make install-hooks

# Manual quality checks (automatically run by pre-commit hooks)
make lint
make test
make pre-commit
```

### Code Quality Standards

- **Pre-commit Hooks**: Automatically enforce quality checks on every commit
- **Linting**: All Lua code must pass luacheck validation
- **Testing**: Changes should pass existing tests
- **File Formatting**: Automatic cleanup of whitespace, line endings, etc.
- **Security**: Automatic detection of sensitive data and large files
- **Style**: Follow existing code patterns and conventions
- **Documentation**: Keep comments clear and in English

## Contributing

Pull requests and issue reports are welcome!

1. Fork this repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. **Set up development environment** (`make install-dev && make install-hooks`)
4. Make your changes
5. Commit your changes (`git commit -m 'Add amazing feature'`) - hooks run automatically
6. Push to the branch (`git push origin feature/amazing-feature`)
7. Create a pull request

**Note:** Pre-commit hooks automatically run quality checks. Manual verification: `make pre-commit`

## License

MIT License - See [LICENSE](LICENSE) file for details.

## Related Projects

- [VS Code Dev Containers](https://code.visualstudio.com/docs/remote/containers)
- [devcontainer/cli](https://github.com/devcontainers/cli)
- [devcontainer/spec](https://github.com/devcontainers/spec)
