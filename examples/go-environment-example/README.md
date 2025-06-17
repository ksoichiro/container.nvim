# Go Environment Customization Example

This example demonstrates how to customize the execution environment for Go projects using `devcontainer.nvim` customizations.

## Features

- **Language Preset**: Uses the built-in `go` preset for common Go paths
- **Custom Environment Variables**: Adds Go-specific environment variables
- **Context-specific Environments**: Different environments for different execution contexts

## devcontainer.json Configuration

The `.devcontainer/devcontainer.json` file shows:

1. **Language Preset**: `"languagePreset": "go"` automatically sets up Go-specific PATH, GOPATH, and GOROOT
2. **postCreateEnvironment**: Environment variables used when running `postCreateCommand`
3. **execEnvironment**: Environment variables used when running `:DevcontainerExec` commands
4. **lspEnvironment**: Environment variables used for LSP server detection and startup

## Usage

1. Open this directory in Neovim
2. Run `:DevcontainerOpen` to load the configuration
3. Run `:DevcontainerStart` to start the container
4. The `postCreateCommand` will install `gopls` with the correct environment
5. LSP will automatically detect and start `gopls` using the configured environment

## Testing Environment Variables

After starting the container, you can test the environment:

```vim
:DevcontainerExec echo $GOPATH
:DevcontainerExec echo $GOROOT
:DevcontainerExec go version
:DevcontainerExec which gopls
```

## Benefits

- No hardcoded paths in the plugin
- Easily customizable for different Go versions or setups
- Consistent environment across postCreate, exec, and LSP contexts
- Compatible with standard devcontainer.json extensions
