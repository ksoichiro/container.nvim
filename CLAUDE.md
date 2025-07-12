# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Common Development Tasks

### Running the Plugin
This is a Neovim plugin that can be loaded using Lazy.nvim or Packer. For development:
```lua
-- Load from local directory in Lazy.nvim
{
  dir = "/path/to/container.nvim",
  config = function()
    require('container').setup({ log_level = 'debug' })
  end,
}
```

### Testing Changes
- When testing in an actual nvim environment is necessary, utilize headless mode as much as possible to eliminate manual user operations. This approach is more reliable for verifying what needs to be checked and is also more efficient.
- When user has to test manually:
  1. Reload the plugin: `:lua package.loaded.container = nil; require('container').setup()`
  2. Test commands: `:ContainerOpen`, `:ContainerBuild`, `:ContainerStart`
  3. Check debug info: `:ContainerDebug`
  4. View logs: `:ContainerLogs`

**Important**: When using `nvim --headless` for automated testing, always include the `-u NONE` option to prevent loading user configuration files from `~/.config/nvim`. This ensures consistent test environments.

Example:
```bash
nvim --headless -u NONE -c "lua require('container').setup()" -c "qa"
```

### TODO Management
When identifying future improvements or tasks during development:
1. **DO NOT** use session memory (TodoWrite tool) for persistent tasks
2. **DO** add items directly to `TODO.md` file under appropriate priority sections
3. **COMMIT** TODO.md changes to ensure tasks are tracked in git history
4. **ORGANIZE** items by priority: 🔴 High Priority, 🟡 Medium Priority, 🟢 Low Priority

### Development Workflow

#### Code Quality Requirements
**MANDATORY: Set up pre-commit hooks for automatic quality checks**
```bash
# Set up pre-commit hooks (one-time setup)
make install-hooks

# Manual quality checks (if needed)
make lint
make test

# Install development dependencies if needed
make install-dev
```

**Pre-commit hooks automatically run:**
- Luacheck linting on all Lua files
- StyLua code formatting checks
- Test suite execution
- File formatting (trailing whitespace, end-of-file fixes)
- JSON/YAML validation
- Security checks (private keys, large files)
- Project structure validation (CLAUDE.md, Makefile targets)

#### Committing Changes
**IMPORTANT: Always use pre-commit instead of manually running make format**
```bash
# Before committing, ensure pre-commit hooks are set up
pre-commit run --all-files  # Optional: run pre-commit manually

# Then proceed with git commands
git add .
git commit -m "your commit message"
```

This prevents common issues with:
- Trailing whitespace in documentation files
- Inconsistent Lua code formatting
- End-of-file newlines

#### Development Rules
1. **Pre-commit Hooks**: Set up once with `make install-hooks` - automatically enforces quality
2. **Code Style**: Follow existing patterns (2-space indentation, clear module separation)
3. **Error Handling**: Add proper error handling and parameter validation
4. **Documentation**: Keep comments clear and concise in English
5. **Manual Checks**: Use `make lint` and `make test` for manual verification when needed
6. **TODO Management**: Add future tasks and improvements to `TODO.md` file, NOT session memory
7. **Help Documentation**: Update `doc/container.txt` when adding/modifying commands or features

#### Available Make Targets
- `make install-hooks` - Install pre-commit hooks (one-time setup)
- `make lint` - Run luacheck on all Lua files
- `make format` - Format all Lua code with StyLua
- `make format-check` - Check if code is properly formatted
- `make test` - Run test suite
- `make install-dev` - Install development dependencies (luacheck, stylua)
- `make pre-commit` - Run lint, format-check, and test (manual verification)
- `make help-tags` - Generate Neovim help tags
- `make help` - Show all available targets

#### Code Quality Configuration
**Linting (Luacheck)**
- Configuration: `.luacheckrc`
- Standards: lua54+luajit with Neovim globals
- Max line length: 120 characters
- Cyclomatic complexity limit: 15

**Formatting (StyLua)**
- Configuration: `stylua.toml`
- Line width: 120 characters
- Indentation: 2 spaces
- Quote style: AutoPreferSingle
- Call parentheses: Always

### Documentation Updates
When modifying the plugin:
1. **Commands**: Update both `README.md` and `doc/container.txt`
2. **Configuration**: Update help documentation with new options
3. **API Functions**: Document in the API section of help file
4. **Examples**: Keep devcontainer.json examples up to date

After documentation changes:
```bash
make help-tags  # Generate help tags
# Or in Neovim: :helptags doc
```

## High-Level Architecture

### Module Structure
The plugin follows a modular architecture with clear separation of concerns:

```
lua/container/
├── init.lua          # Main entry point, command registration, public API
├── config.lua        # Configuration management and defaults
├── parser.lua        # devcontainer.json parsing logic
├── docker/
│   └── init.lua      # Docker/Podman runtime interaction layer
├── lsp/
│   ├── init.lua      # LSP integration and management
│   ├── commands.lua  # LSP command implementations
│   └── simple_transform.lua  # Path transformation utilities
├── terminal/
│   ├── init.lua      # Terminal session management
│   └── session.lua   # Session state handling
├── ui/
│   └── picker.lua    # Picker integrations (telescope, fzf-lua)
└── utils/
    ├── async.lua     # Asynchronous operation utilities
    ├── fs.lua        # File system operations
    ├── log.lua       # Logging system
    └── notify.lua    # Notification utilities
```

### Key Design Patterns

1. **Lazy Module Loading**: Modules are loaded on-demand to improve startup performance
2. **Configuration System**: Centralized in `config.lua` with sensible defaults and deep merging
3. **Docker Abstraction**: All container runtime operations go through `docker/init.lua` to support both Docker and Podman
4. **Async Operations**: Heavy operations (Docker commands) use async utilities to avoid blocking Neovim
5. **VSCode Compatibility**: Parser supports standard devcontainer.json format for VSCode compatibility

### Command Flow
1. User runs command (e.g., `:ContainerOpen`)
2. `plugin/container.lua` defines the command
3. Command calls into `lua/container/init.lua` public API
4. Main module orchestrates:
   - Parse devcontainer.json via `parser.lua`
   - Execute Docker operations via `docker/init.lua`
   - Log activities via `utils/log.lua`
   - Handle async operations via `utils/async.lua`

### Current Implementation Status
- Core plugin structure and configuration system ✓
- Docker/Podman runtime integration ✓
- Enhanced terminal integration with session management ✓
- Command definitions created ✓
- Parser for devcontainer.json ✓
- Environment variable management with language presets ✓
- Test runner integration with dual output modes ✓
  - Buffer mode: Integrated output in Neovim messages
  - Terminal mode: Interactive execution in dedicated terminal
  - Support for vim-test, nvim-test, and neotest plugins
- Smart port forwarding with dynamic allocation ✓
- Picker integration (telescope, fzf-lua, vim.ui.select) ✓
- Logging and filesystem utilities ✓
- Async handling utilities ✓
- User events for lifecycle management ✓
- LSP integration with dynamic path transformation ✓
  - Simple path transformation without complex interception
  - Automatic file registration and change tracking
  - Container-aware LSP commands (hover, definition, references)
  - Multi-file support with automatic keybinding setup

### LSP Integration

#### Current Implementation - Dynamic Path Transformation
- Simple and reliable path transformation approach
- Automatic file registration and change tracking
- Works with standard Neovim LSP handlers for consistent UI
- Integrated into main plugin with automatic setup

#### Key Components:
1. **`lua/container/lsp/simple_transform.lua`**: Path transformation utilities
2. **`lua/container/lsp/commands.lua`**: LSP command implementations  
3. **Integration in `lua/container/lsp/init.lua`**: Automatic setup for gopls

#### Usage:
When a container with gopls is detected, the plugin automatically:
- Sets up container_gopls LSP client
- Maps standard LSP keys (K, gd, gr) to container-aware commands
- Handles path transformation transparently

Users can also use commands directly:
- `:ContainerLspHover` - Show hover information
- `:ContainerLspDefinition` - Go to definition
- `:ContainerLspReferences` - Find references

#### Remaining Limitations:
1. **Standard Library**: Cannot navigate to Go stdlib (outside /workspace)
   - Workaround: Mount Go installation or use vendored dependencies
2. **Performance**: Slight overhead from path transformation
   - Generally not noticeable in practice


### Planned Features (Future)
- Multi-container support with docker-compose
- Advanced networking configuration
- Plugin ecosystem and extension points
- GUI configuration interface

This architecture allows for incremental development while maintaining clean separation between VSCode devcontainer compatibility and Neovim-specific features.
