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

### Development Workflow
Since there are no linting/formatting tools configured yet:
- Follow existing code style (2-space indentation, clear module separation)
- Test changes manually in Neovim
- Use git for version control

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