# devcontainer.nvim

A Neovim plugin that provides VSCode Dev Containers-like development experience.

## Features

- **devcontainer.json Support**: Fully compatible with VSCode configuration files
- **Automatic Image Building**: Automatic Docker image building and management
- **Enhanced Terminal Integration**: Advanced in-container terminal with session management
- **LSP Integration**: Automatic detection and configuration of LSP servers in containers
- **Smart Port Forwarding**: Dynamic port allocation to prevent conflicts between projects
- **Asynchronous Operations**: All Docker operations executed asynchronously

## Requirements

- Neovim 0.8+
- Docker or Podman
- Git

## Installation

### lazy.nvim

```lua
{
  'ksoichiro/devcontainer.nvim',
  dependencies = {
    'nvim-lua/plenary.nvim', -- For async operations (future feature expansion)
  },
  config = function()
    require('devcontainer').setup({
      -- Configuration options
      log_level = 'info',
      container_runtime = 'docker', -- 'docker' or 'podman'
      auto_start = false,
    })
  end,
}
```

### packer.nvim

```lua
use {
  'ksoichiro/devcontainer.nvim',
  requires = {
    'nvim-lua/plenary.nvim',
  },
  config = function()
    require('devcontainer').setup()
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
  "forwardPorts": [3000, "auto:8080"],
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

```vim
:DevcontainerOpen
:DevcontainerBuild
:DevcontainerStart
```

## Commands

For detailed command documentation, use `:help devcontainer-commands` in Neovim.

### Basic Operations

| Command | Description |
|---------|-------------|
| `:DevcontainerOpen [path]` | Open devcontainer |
| `:DevcontainerBuild` | Build image |
| `:DevcontainerStart` | Start container |
| `:DevcontainerStop` | Stop container |
| `:DevcontainerKill` | Kill container (immediate termination) |
| `:DevcontainerTerminate` | Terminate container (immediate termination) |
| `:DevcontainerRestart` | Restart container |

### Execution & Access

| Command | Description |
|---------|-------------|
| `:DevcontainerExec <command>` | Execute command in container |

### Enhanced Terminal Integration

| Command | Description |
|---------|-------------|
| `:DevcontainerTerminal [options]` | Open enhanced terminal with session management |
| `:DevcontainerTerminalNew [name]` | Create new terminal session |
| `:DevcontainerTerminalList` | List all terminal sessions |
| `:DevcontainerTerminalClose [name]` | Close terminal session |
| `:DevcontainerTerminalCloseAll` | Close all terminal sessions |
| `:DevcontainerTerminalRename <old> <new>` | Rename terminal session |
| `:DevcontainerTerminalNext` | Switch to next terminal session |
| `:DevcontainerTerminalPrev` | Switch to previous terminal session |
| `:DevcontainerTerminalStatus` | Show terminal system status |
| `:DevcontainerTerminalCleanup [days]` | Clean up old terminal history files |

### Information Display

| Command | Description |
|---------|-------------|
| `:DevcontainerStatus` | Show container status |
| `:DevcontainerLogs` | Show container logs |
| `:DevcontainerConfig` | Show configuration |

### LSP Integration

| Command | Description |
|---------|-------------|
| `:DevcontainerLspStatus` | Show LSP server status |
| `:DevcontainerLspSetup` | Setup LSP servers in container |

### Port Management

| Command | Description |
|---------|-------------|
| `:DevcontainerPorts` | Show detailed port forwarding information |
| `:DevcontainerPortStats` | Show port allocation statistics |

### Telescope Integration

| Command | Description |
|---------|-------------|
| `:DevcontainerPicker` | Open devcontainer picker |
| `:DevcontainerSessionPicker` | Open terminal session picker |
| `:DevcontainerPortPicker` | Open port management picker |
| `:DevcontainerHistoryPicker` | Open command history picker |

### Management

| Command | Description |
|---------|-------------|
| `:DevcontainerAutoStart [mode]` | Configure auto-start behavior (off, notify, prompt, immediate) |
| `:DevcontainerReset` | Reset plugin state |
| `:DevcontainerDebug` | Show comprehensive debug information |
| `:DevcontainerReconnect` | Reconnect to existing devcontainer |

## Configuration

### Default Configuration

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
    default_position = 'split',     -- 'split', 'vsplit', 'tab', 'float'

    -- Split configuration
    split = {
      height = 15,                  -- Lines for horizontal split
      width = 80,                   -- Columns for vertical split
    },

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
})
```

## StatusLine Integration

The plugin provides built-in statusline integration to display devcontainer status in your Neovim statusline.

### Configuration

Enable statusline integration in your configuration:

```lua
require('devcontainer').setup({
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
require('devcontainer').setup({
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
require('devcontainer').setup({
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
require('devcontainer').setup({
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
  return require('devcontainer').statusline()
end

-- Example with vim.o.statusline
vim.o.statusline = '%f %{luaeval("require(\"devcontainer\").statusline()")} %='
```

#### Lualine Integration

```lua
require('lualine').setup({
  sections = {
    lualine_c = {
      'filename',
      require('devcontainer').statusline_component(),
    }
  }
})
```

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
  return luaeval('require("devcontainer.ui.statusline").lightline_component()')
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
  "forwardPorts": [
    3000,                    // Fixed port (traditional)
    "auto:3001",            // Auto-allocate available port
    "range:8000-8010:3002", // Allocate from specific range
    "8080:3003"             // Host:container mapping
  ]
}
```

### Benefits

- **Conflict Prevention**: Multiple projects can run simultaneously without port conflicts
- **Automatic Allocation**: No need to manually manage port assignments
- **Project Isolation**: Each project gets its own port allocation space
- **Easy Monitoring**: Use `:DevcontainerPorts` and `:DevcontainerPortStats` to monitor usage

### Usage Examples

Multi-project development:
```json
// Project A
{ "forwardPorts": ["auto:3000", "auto:8080"] }

// Project B  
{ "forwardPorts": ["auto:3000", "auto:8080"] }
```

Both projects can run simultaneously with automatically assigned unique ports.

## Notification Levels

Control the verbosity of plugin notifications with the `notification_level` setting:

### Available Levels

- **`verbose`**: Show all notifications (debug, info, warnings, errors)
- **`normal`** (default): Show important notifications (critical operations, container events, warnings)
- **`minimal`**: Show only essential notifications (critical operations, container lifecycle)
- **`silent`**: Show only error messages

### Configuration

```lua
require('devcontainer').setup({
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
require('devcontainer').setup({
  ui = { notification_level = 'minimal' }
})

-- Verbose notifications (debugging/development)
require('devcontainer').setup({
  ui = { notification_level = 'verbose' }
})

-- Silent mode (errors only)
require('devcontainer').setup({
  ui = { notification_level = 'silent' }
})
```

## Lua API

For programmatic access to the plugin:

```lua
-- Basic operations
require('devcontainer').open()
require('devcontainer').build()
require('devcontainer').start()
require('devcontainer').stop()

-- Command execution
require('devcontainer').exec('npm test')

-- Enhanced terminal functions
require('devcontainer').terminal({ name = 'dev', position = 'float' })
require('devcontainer').terminal_new('build')
require('devcontainer').terminal_list()
require('devcontainer').terminal_close('dev')

-- Information retrieval
local status = require('devcontainer').status()
local config = require('devcontainer').get_config()
local container_id = require('devcontainer').get_container_id()
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
  "forwardPorts": [3000, "auto:8080", "range:9000-9100:9229"],
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
:DevcontainerLogs
:DevcontainerDebug
```

### Configuration file errors

```vim
:DevcontainerConfig
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
