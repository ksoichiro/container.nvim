# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Common Development Tasks

### Running the Plugin
This is a Neovim plugin that can be loaded using Lazy.nvim or Packer. For development:
```lua
-- Load from local directory in Lazy.nvim
{
  dir = "/path/to/devcontainer.nvim",
  config = function()
    require('devcontainer').setup({ log_level = 'debug' })
  end,
}
```

### Testing Changes
Currently no formal test framework is implemented. Test manually by:
1. Reload the plugin: `:lua package.loaded.devcontainer = nil; require('devcontainer').setup()`
2. Test commands: `:DevcontainerOpen`, `:DevcontainerBuild`, `:DevcontainerStart`
3. Check debug info: `:DevcontainerDebug`
4. View logs: `:DevcontainerLogs`

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
- Test suite execution
- File formatting (trailing whitespace, end-of-file fixes)
- JSON/YAML validation
- Security checks (private keys, large files)
- Project structure validation (CLAUDE.md, Makefile targets)

#### Development Rules
1. **Pre-commit Hooks**: Set up once with `make install-hooks` - automatically enforces quality
2. **Code Style**: Follow existing patterns (2-space indentation, clear module separation)
3. **Error Handling**: Add proper error handling and parameter validation
4. **Documentation**: Keep comments clear and concise in English
5. **Manual Checks**: Use `make lint` and `make test` for manual verification when needed
6. **TODO Management**: Add future tasks and improvements to `TODO.md` file, NOT session memory
7. **Help Documentation**: Update `doc/devcontainer.txt` when adding/modifying commands or features

#### Available Make Targets
- `make install-hooks` - Install pre-commit hooks (one-time setup)
- `make lint` - Run luacheck on all Lua files
- `make test` - Run test suite
- `make install-dev` - Install development dependencies (luacheck)
- `make pre-commit` - Run both lint and test (manual verification)
- `make help-tags` - Generate Neovim help tags
- `make help` - Show all available targets

#### Linting Configuration
- Configuration: `.luacheckrc`
- Standards: lua54+luajit with Neovim globals
- Max line length: 120 characters
- Cyclomatic complexity limit: 15

### Documentation Updates
When modifying the plugin:
1. **Commands**: Update both `README.md` and `doc/devcontainer.txt`
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
lua/devcontainer/
├── init.lua          # Main entry point, command registration, public API
├── config.lua        # Configuration management and defaults
├── parser.lua        # devcontainer.json parsing logic
├── docker/
│   └── init.lua      # Docker/Podman runtime interaction layer
└── utils/
    ├── async.lua     # Asynchronous operation utilities
    ├── fs.lua        # File system operations
    └── log.lua       # Logging system
```

### Key Design Patterns

1. **Lazy Module Loading**: Modules are loaded on-demand to improve startup performance
2. **Configuration System**: Centralized in `config.lua` with sensible defaults and deep merging
3. **Docker Abstraction**: All container runtime operations go through `docker/init.lua` to support both Docker and Podman
4. **Async Operations**: Heavy operations (Docker commands) use async utilities to avoid blocking Neovim
5. **VSCode Compatibility**: Parser supports standard devcontainer.json format for VSCode compatibility

### Command Flow
1. User runs command (e.g., `:DevcontainerOpen`)
2. `plugin/devcontainer.lua` defines the command
3. Command calls into `lua/devcontainer/init.lua` public API
4. Main module orchestrates:
   - Parse devcontainer.json via `parser.lua`
   - Execute Docker operations via `docker/init.lua`
   - Log activities via `utils/log.lua`
   - Handle async operations via `utils/async.lua`

### Current Implementation Status (Phase 1)
- Core plugin structure and configuration system ✓
- Basic Docker integration started
- Command definitions created
- Parser for devcontainer.json
- Logging and filesystem utilities
- Async handling utilities

### Planned Features (from DESIGN.md)
- Phase 2: LSP server integration, terminal integration, port forwarding
- Phase 3: Telescope integration, enhanced status display, configuration UI
- Phase 4: Multi-container support, advanced networking, plugin ecosystem

This architecture allows for incremental development while maintaining clean separation between VSCode devcontainer compatibility and Neovim-specific features.
