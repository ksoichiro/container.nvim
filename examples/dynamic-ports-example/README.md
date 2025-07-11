# Dynamic Ports Example

This example demonstrates container.nvim's dynamic port allocation feature with standard-compliant configuration.

## Features

- **Standard Compliant**: Uses standard `forwardPorts` format that works with VSCode and other tools
- **Dynamic Port Allocation**: Uses `customizations.container.nvim.dynamicPorts` for advanced port management
- **Automatic Migration**: If you upgrade from legacy syntax, container.nvim will automatically migrate your configuration

## Port Configuration

### Standard Format (VSCode Compatible)
```json
{
  "forwardPorts": [3000, 8080, 9229, 5000]
}
```

### Dynamic Port Allocation (container.nvim Extension)
```json
{
  "customizations": {
    "container.nvim": {
      "dynamicPorts": [
        "auto:8080",           // Auto-allocate host port for container port 8080
        "range:9000-9100:9229" // Allocate from range 9000-9100 for container port 9229
      ]
    }
  }
}
```

## How It Works

1. **Standard Ports (3000, 5000)**: Use fixed port mapping (host:container)
2. **Auto-allocated Port (8080)**: container.nvim automatically finds an available host port
3. **Range-allocated Port (9229)**: container.nvim finds an available port in the 9000-9100 range

## Migration from Legacy Syntax

If you have old configuration using legacy syntax:

```json
{
  "forwardPorts": [3000, "auto:8080", "range:9000-9100:9229", 5000]
}
```

container.nvim will automatically:
1. Show a deprecation warning
2. Migrate dynamic ports to `customizations.container.nvim.dynamicPorts`
3. Update `forwardPorts` to contain only standard port numbers

## Benefits

- **VSCode Compatibility**: Standard `forwardPorts` work with VSCode Dev Containers
- **Advanced Features**: Dynamic allocation still available through customizations
- **Automatic Migration**: Seamless upgrade from legacy configurations
- **Best of Both Worlds**: Standard compliance + advanced functionality

## Usage

1. Open this directory in container.nvim
2. Run `:ContainerOpen` to load the configuration
3. Run `:ContainerBuild` to prepare the image
4. Run `:ContainerStart` to start the development container
5. Check port allocations with `:ContainerStatus`
6. Run `:ContainerTerminal` to open a terminal in the container
7. Start the servers:
   ```bash
   # Main server (port 3000 → dynamically allocated host port)
   npm start

   # API server (port 8080 → dynamically allocated host port)  
   npm run api
   ```

### Port Mappings

After container startup, check `:ContainerStatus` to see the dynamic port allocations:

- **3000/tcp** → **localhost:XXXX** (auto-allocated, typically 10000+)
- **8080/tcp** → **localhost:YYYY** (auto-allocated, typically 10000+)
- **9229/tcp** → **localhost:9000** (range-allocated from 9000-9100)

### Accessing the Servers

Once the servers are running, you can access them via the dynamically allocated ports:

```bash
# Main development server
curl http://localhost:XXXX

# API server  
curl http://localhost:YYYY/api

# Where XXXX and YYYY are the dynamically allocated ports shown in :ContainerStatus
```
