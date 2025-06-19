# Python Environment Customization Example

This example demonstrates how to use language presets and additional environment variables for Python projects with `container.nvim`.

## Features

- **Language Preset**: Uses the built-in `python` preset for Python-specific paths
- **Additional Environment Variables**: Adds custom PYTHONPATH and DEBUG flag
- **Simplified Configuration**: Uses language preset with minimal customization

## devcontainer.json Configuration

The `.devcontainer/devcontainer.json` file shows:

1. **Language Preset**: `"languagePreset": "python"` automatically sets up Python-specific PATH and PYTHONPATH
2. **additionalEnvironment**: Adds extra environment variables on top of the preset
3. **Automatic Detection**: The plugin can auto-detect Python from the image name

## Usage

1. Open this directory in Neovim
2. Run `:ContainerOpen` to load the configuration
3. Run `:ContainerStart` to start the container
4. The `postCreateCommand` will install Python LSP tools with the correct environment

## Testing Environment Variables

After starting the container, you can test the environment:

```vim
:ContainerExec echo $PYTHONPATH
:ContainerExec echo $DEBUG
:ContainerExec python --version
:ContainerExec which pylsp
```

## Language Detection

The plugin can automatically detect the language from:
1. Explicit `languagePreset` in customizations (highest priority)
2. Image name (e.g., images containing "python")
3. Features in devcontainer.json (e.g., python features)

## Available Presets

- `go`: Go development environment
- `python`: Python development environment  
- `node`: Node.js development environment
- `rust`: Rust development environment
- `default`: Basic environment with common paths
