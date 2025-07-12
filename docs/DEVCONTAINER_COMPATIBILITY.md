# Dev Container Specification Compatibility

This document outlines container.nvim's compatibility with the official [Dev Container specification](https://containers.dev/) and details our custom extensions.

## Standard Compliance

Container.nvim supports all standard Dev Container properties including:

- ✅ `name`, `image`, `dockerFile`, `build`
- ✅ `forwardPorts`, `portsAttributes`
- ✅ `containerEnv`, `remoteEnv`
- ✅ `postCreateCommand`, `postStartCommand`, `postAttachCommand`
- ✅ `mounts`, `workspaceFolder`, `remoteUser`
- ✅ `features`, `customizations`

## Custom Extensions

Container.nvim extends the specification with additional features in the `customizations.container.nvim` section:

### 1. Dynamic Port Forwarding

**Non-standard syntax in `forwardPorts`:**

```json
{
  "forwardPorts": [
    3000,                        // Standard: fixed port
    "8080:80",                  // Standard: host:container mapping
    "auto:3000",                // Extension: auto-allocate host port
    "range:8000-8010:3000"      // Extension: allocate from port range
  ]
}
```

**Impact**: VSCode and other tools will ignore the extended syntax and may fail to forward these ports.

**Workaround**: Use standard syntax when sharing with VSCode users:
```json
{
  "forwardPorts": [3000, 8080],
  "customizations": {
    "container.nvim": {
      "dynamicPorts": ["auto:3000", "range:8000-8010:3000"]
    }
  }
}
```

### 2. Language-Specific Environment Presets

**Custom environment configuration:**

```json
{
  // Standard environment variables
  "containerEnv": {
    "PATH": "/usr/local/go/bin:${containerEnv:PATH}",
    "GOPATH": "/go"
  },
  "remoteEnv": {
    "NODE_ENV": "development",
    "GOPLS_FLAGS": "-debug"
  },

  // Optional customizations
  "customizations": {
    "container.nvim": {
      "languagePreset": "go"
    }
  }
}
```

**Standard equivalent:**

```json
{
  "containerEnv": {
    "PATH": "/usr/local/go/bin:${containerEnv:PATH}",
    "GOPATH": "/go"
  },
  "remoteEnv": {
    "NODE_ENV": "development",
    "GOPLS_FLAGS": "-debug"
  }
}
```

**Impact**: Our custom approach provides context-aware environments but isn't portable to other tools.

### 3. Project Identification

Container.nvim generates unique container names using project path hashing to support multiple projects simultaneously. This is an implementation detail that doesn't affect devcontainer.json compatibility.

## Migration Guide

### For Maximum Compatibility

If you need to share your devcontainer.json with VSCode users:

1. **Use standard port syntax**:
   ```json
   "forwardPorts": [3000, 8080]
   ```

2. **Use standard environment variables**:
   ```json
   "containerEnv": {
     "MY_VAR": "value"
   }
   ```

3. **Keep container.nvim extensions in customizations**:
   ```json
   "customizations": {
     "container.nvim": {
       // Container.nvim specific settings
     }
   }
   ```

### For Container.nvim Features

When working exclusively with container.nvim, you can use all extended features for enhanced functionality:

1. Dynamic ports for avoiding conflicts
2. Language presets for quick setup
3. Context-specific environments for different commands

## Recommendations

1. **For personal projects**: Use container.nvim extensions freely
2. **For team projects**: Use standard syntax with extensions in customizations
3. **For open source**: Stick to standard specification only

## Future Considerations

We're evaluating ways to:
- Propose useful extensions to the official specification
- Provide automatic conversion between formats
- Maintain backward compatibility while improving standards compliance

## Related Documentation

- [Official Dev Container Specification](https://containers.dev/implementors/json_reference/)
- [Container.nvim Configuration Guide](../README.md#configuration)
- [VSCode Dev Containers Documentation](https://code.visualstudio.com/docs/devcontainers/containers)
