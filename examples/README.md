# container.nvim Examples

This directory contains various examples demonstrating different features and use cases of container.nvim.

## Available Examples

### Language-specific Examples

- **[go-example/](./go-example/)** - Basic Go development environment with LSP support
- **[go-test-example/](./go-test-example/)** - Go project with comprehensive test integration
- **[go-environment-example/](./go-environment-example/)** - Advanced Go environment configuration
- **[node-example/](./node-example/)** - Node.js development with TypeScript and ESLint
- **[python-example/](./python-example/)** - Python development with LSP and linting
- **[python-environment-example/](./python-environment-example/)** - Advanced Python environment setup

### Feature-specific Examples

- **[dynamic-ports-example/](./dynamic-ports-example/)** - **NEW** Demonstrates dynamic port allocation with standard-compliant configuration

## Getting Started

1. Choose an example that matches your development needs
2. Copy the example directory to your project root
3. Customize the `.devcontainer/devcontainer.json` file as needed
4. Open the directory in Neovim with container.nvim installed
5. Run `:ContainerOpen` to start the development container

## Key Features Demonstrated

### Basic Container Operations
- Container creation and management
- Workspace mounting and configuration
- PostCreate command execution

### LSP Integration
- Automatic language server detection
- Container-aware LSP configuration
- Path transformation for seamless development

### Port Forwarding
- Fixed port mapping
- **Dynamic port allocation** (auto and range allocation)
- Standard-compliant configuration format

### Test Integration
- Integration with vim-test, nvim-test, and neotest
- Container-based test execution
- Multiple output modes (buffer/terminal)

### Development Tools
- Debugging support with nvim-dap
- Environment variable management
- Custom language presets

## Advanced Configuration

### Dynamic Port Allocation

The `dynamic-ports-example` demonstrates the new standard-compliant way to use dynamic port allocation:

```json
{
  "forwardPorts": [3000, 8080, 9229, 5000],
  "customizations": {
    "container.nvim": {
      "dynamicPorts": [
        "auto:8080",
        "range:9000-9100:9229"
      ]
    }
  }
}
```

This approach provides:
- VSCode Dev Containers compatibility
- Advanced port allocation features
- Automatic migration from legacy syntax

### Environment Customization

Use language presets or custom environment variables:

```json
{
  "customizations": {
    "container.nvim": {
      "languagePreset": "go",
      "postCreateEnvironment": {
        "PATH": "/custom/bin:$PATH"
      }
    }
  }
}
```

## Migration Guide

If you're upgrading from older container.nvim versions:

1. **Port Configuration**: Legacy dynamic port syntax in `forwardPorts` will be automatically migrated to `customizations.container.nvim.dynamicPorts`
2. **Environment Variables**: Consider migrating custom environment settings to standard `containerEnv`/`remoteEnv` where appropriate
3. **Documentation**: Check each example's README for specific migration notes

## Contributing

When adding new examples:

1. Create a new directory with a descriptive name
2. Include a complete `.devcontainer/devcontainer.json` configuration
3. Add a detailed README explaining the example's purpose and features
4. Include sample code that demonstrates the container setup
5. Update this main README to list the new example
