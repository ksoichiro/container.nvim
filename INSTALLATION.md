# devcontainer.nvim Installation Guide

## Integration with Lazy.nvim

### 1. Using Local Development Version

Since the current directory is the devcontainer.nvim plugin source, you can install it by specifying the local path.

```lua
-- ~/.config/nvim/lua/plugins/devcontainer.lua or appropriate config file
return {
  {
    -- Specify local path (change to this project's path)
    dir = "/path/to/devcontainer.nvim",
    name = "devcontainer.nvim",
    config = function()
      require('devcontainer').setup({
        -- Basic configuration
        log_level = 'info',
        container_runtime = 'docker', -- 'docker' or 'podman'
        auto_start = false,
        
        -- UI configuration
        ui = {
          show_notifications = true,
          icons = {
            container = "🐳",
            running = "✅",
            stopped = "⏹️",
            building = "🔨",
          },
        },
        
        -- Terminal configuration
        terminal = {
          shell = '/bin/bash',
          height = 15,
          direction = 'horizontal',
        },
      })
    end,
  }
}
```

### 2. Using from GitHub Repository

```lua
return {
  {
    'ksoichiro/devcontainer.nvim',
    config = function()
      require('devcontainer').setup({
        log_level = 'info',
        container_runtime = 'docker',
        auto_start = false,
      })
    end,
  }
}
```

### 3. Development Configuration Example (Recommended)

```lua
-- ~/.config/nvim/lua/plugins/devcontainer.lua
return {
  {
    -- Use local path during development
    dir = vim.fn.expand("~/path/to/devcontainer.nvim"), -- Change to actual path
    name = "devcontainer.nvim",
    
    -- Disable lazy loading in development mode
    lazy = false,
    
    config = function()
      require('devcontainer').setup({
        -- Development configuration
        log_level = 'debug', -- Display debug information
        
        -- Docker configuration
        container_runtime = 'docker',
        
        -- Disable auto-start (for manual testing)
        auto_start = false,
        
        -- UI configuration
        ui = {
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
        
        -- Terminal configuration
        terminal = {
          shell = '/bin/bash',
          height = 15,
          direction = 'horizontal',
          close_on_exit = false,
        },
        
        -- Development settings
        dev = {
          reload_on_change = true,
          debug_mode = true,
        },
      })
    end,
    
    -- Key mapping examples
    keys = {
      { "<leader>co", "<cmd>DevcontainerOpen<cr>", desc = "Open devcontainer" },
      { "<leader>cb", "<cmd>DevcontainerBuild<cr>", desc = "Build devcontainer" },
      { "<leader>cs", "<cmd>DevcontainerStart<cr>", desc = "Start devcontainer" },
      { "<leader>cx", "<cmd>DevcontainerStop<cr>", desc = "Stop devcontainer" },
      { "<leader>ct", "<cmd>DevcontainerShell<cr>", desc = "Open shell" },
      { "<leader>cl", "<cmd>DevcontainerLogs<cr>", desc = "Show logs" },
      { "<leader>ci", "<cmd>DevcontainerStatus<cr>", desc = "Show status" },
      { "<leader>cr", "<cmd>DevcontainerReset<cr>", desc = "Reset state" },
    },
  }
}
```

## Setup Procedure

### 1. Create Plugin File

```bash
# Navigate to Neovim config directory
cd ~/.config/nvim

# Create plugin config file
mkdir -p lua/plugins
touch lua/plugins/devcontainer.lua
```

### 2. Write Configuration

Write one of the configuration examples above to `lua/plugins/devcontainer.lua`.

### 3. Adjust Path

Change the `dir` parameter to the actual path of the devcontainer.nvim project:

```lua
dir = "/Users/yourname/path/to/devcontainer.nvim",
```

### 4. Restart Neovim

After saving the configuration, restart Neovim to load the plugin.

## Operation Verification

### 1. Check Plugin Loading

```vim
:DevcontainerDebug
```

This displays the plugin status and debug information.

### 2. Check Configuration

```vim
:DevcontainerConfig
```

This displays the current configuration.

### 3. Check Docker

```vim
:DevcontainerOpen
```

This checks Docker availability.

## Troubleshooting

### When Plugin Doesn't Load

1. Verify the path is correct
```lua
:lua print(vim.fn.expand("~/path/to/devcontainer.nvim"))
```

2. Check Lazy.nvim logs
```vim
:Lazy log
```

3. Check error messages
```vim
:messages
```

### Docker-related Errors

1. Check if Docker is running
```bash
docker --version
docker info
```

2. Check permissions
```bash
# Check if added to Docker group
groups $USER
```

## Useful Development Settings

### Hot Reload Configuration

```lua
-- Function to reload the plugin during development
vim.api.nvim_create_user_command('DevcontainerReload', function()
  -- Clear module cache
  for module_name, _ in pairs(package.loaded) do
    if module_name:match("^devcontainer") then
      package.loaded[module_name] = nil
    end
  end
  
  -- Reload plugin
  require('devcontainer').setup()
  print("devcontainer.nvim reloaded!")
end, {})
```

### Log File Configuration

```lua
config = function()
  require('devcontainer').setup({
    log_level = 'debug',
    -- Set log file
    log_file = vim.fn.stdpath('data') .. '/devcontainer.log',
  })
  
  -- Command to open log file
  vim.api.nvim_create_user_command('DevcontainerLogFile', function()
    vim.cmd('edit ' .. vim.fn.stdpath('data') .. '/devcontainer.log')
  end, {})
end,
```

Now you can integrate and test the devcontainer.nvim plugin with Lazy.nvim!