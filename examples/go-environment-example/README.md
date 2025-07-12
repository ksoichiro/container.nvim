# Go Environment Customization Example

This example demonstrates how to use standard devcontainer environment variables with Go projects in container.nvim.

## Features

- **Standard Environment Variables**: Uses `containerEnv` and `remoteEnv` for VSCode compatibility
- **Language Preset**: Includes backward-compatible `go` preset
- **Automatic Migration**: Legacy configurations are automatically converted

## devcontainer.json Configuration

The `.devcontainer/devcontainer.json` file shows:

1. **containerEnv**: Environment variables for container creation (includes postCreateCommand environment)
2. **remoteEnv**: Environment variables for development operations (exec commands, LSP)
3. **Language Preset**: Optional `"languagePreset": "go"` for additional convenience

## Migration from Legacy Format

This example was migrated from the legacy format:

**Before (Legacy):**
```json
{
  "customizations": {
    "container.nvim": {
      "postCreateEnvironment": { "GOPATH": "/go", ... },
      "execEnvironment": { "GOPATH": "/go", ... },
      "lspEnvironment": { "GOPATH": "/go", ... }
    }
  }
}
```

**After (Standard):**
```json
{
  "containerEnv": { "GOPATH": "/go", ... },
  "remoteEnv": { "GOPATH": "/go", ... },
  "customizations": {
    "container.nvim": {
      "languagePreset": "go"
    }
  }
}
```

## Usage

1. Open this directory in Neovim
2. Run `:ContainerOpen` to load the configuration
3. Run `:ContainerStart` to start the container
4. The `postCreateCommand` will install `gopls` with the correct environment
5. LSP will automatically detect and start `gopls` using the configured environment

## Testing Environment Variables

After starting the container, you can test the environment:

```vim
:ContainerExec echo $GOPATH
:ContainerExec echo $GOROOT
:ContainerExec go version
:ContainerExec which gopls
```

## Benefits

- **VSCode Compatibility**: Uses standard devcontainer specification
- **Automatic Migration**: Legacy configurations work without changes
- **Simplified Configuration**: Single place for environment variables
- **Better Tooling Support**: Works with other devcontainer tools
