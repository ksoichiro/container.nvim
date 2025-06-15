# devcontainer.nvim

A Neovim plugin that provides VSCode Dev Containers-like development experience.

## Features

- **devcontainer.json Support**: Fully compatible with VSCode configuration files
- **Automatic Image Building**: Automatic Docker image building and management
- **Seamless Integration**: Complete integration with Neovim terminal
- **LSP Integration**: Automatic detection and configuration of LSP servers in containers
- **Port Forwarding**: Automatic port forwarding and port management
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

```vim
:DevcontainerOpen
:DevcontainerBuild
:DevcontainerStart
```

## Commands

### Basic Operations

| Command | Description |
|---------|-------------|
| `:DevcontainerOpen [path]` | Open devcontainer |
| `:DevcontainerBuild` | Build image |
| `:DevcontainerStart` | Start container |
| `:DevcontainerStop` | Stop container |
| `:DevcontainerRestart` | Restart container |

### Execution & Access

| Command | Description |
|---------|-------------|
| `:DevcontainerExec <command>` | Execute command in container |
| `:DevcontainerShell [shell]` | Open shell in container |

### Information Display

| Command | Description |
|---------|-------------|
| `:DevcontainerStatus` | Show container status |
| `:DevcontainerLogs` | Show container logs |
| `:DevcontainerConfig` | Show configuration |

### Management

| Command | Description |
|---------|-------------|
| `:DevcontainerReset` | Reset plugin state |
| `:DevcontainerDebug` | Show debug information |

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
    status_line = true,
    icons = {
      container = "🐳",
      running = "✅",
      stopped = "⏹️",
      building = "🔨",
      error = "❌",
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
    exclude_patterns = { '.git', 'node_modules', '.next' },
  },
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
require('devcontainer').shell('/bin/zsh')

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

### v0.1.0 (Current)
- ✅ Basic devcontainer operations
- ✅ Docker integration
- ✅ Basic commands

### v0.2.0 (In Progress)
- 🔄 LSP server integration
- 🔄 Improved terminal integration
- 🔄 Port forwarding

### v0.3.0 (Planned)
- 📋 Telescope integration
- 📋 Enhanced status display
- 📋 Configuration UI

### v1.0.0 (Goal)
- 📋 Complete feature implementation
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
