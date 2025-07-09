# container.nvim Installation Guide

## Integration with Lazy.nvim

### 1. Using Local Development Version

Since the current directory is the container.nvim plugin source, you can install it by specifying the local path.

```lua
-- ~/.config/nvim/lua/plugins/container.lua or appropriate config file
return {
  {
    -- Specify local path (change to this project's path)
    dir = "/path/to/container.nvim",
    name = "container.nvim",
    config = function()
      require('container').setup({
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
    'ksoichiro/container.nvim',
    config = function()
      require('container').setup({
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
-- ~/.config/nvim/lua/plugins/container.lua
return {
  {
    -- Use local path during development
    dir = vim.fn.expand("~/path/to/container.nvim"), -- Change to actual path
    name = "container.nvim",

    -- Disable lazy loading in development mode
    lazy = false,

    config = function()
      require('container').setup({
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
      { "<leader>co", "<cmd>ContainerOpen<cr>", desc = "Open container" },
      { "<leader>cb", "<cmd>ContainerBuild<cr>", desc = "Build container" },
      { "<leader>cs", "<cmd>ContainerStart<cr>", desc = "Start container" },
      { "<leader>cx", "<cmd>ContainerStop<cr>", desc = "Stop container" },
      { "<leader>ct", "<cmd>ContainerTerminal<cr>", desc = "Open terminal" },
      { "<leader>cl", "<cmd>ContainerLogs<cr>", desc = "Show logs" },
      { "<leader>ci", "<cmd>ContainerStatus<cr>", desc = "Show status" },
      { "<leader>cr", "<cmd>ContainerReset<cr>", desc = "Reset state" },
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
touch lua/plugins/container.lua
```

### 2. Write Configuration

Write one of the configuration examples above to `lua/plugins/container.lua`.

### 3. Adjust Path

Change the `dir` parameter to the actual path of the container.nvim project:

```lua
dir = "/Users/yourname/path/to/container.nvim",
```

### 4. Restart Neovim

After saving the configuration, restart Neovim to load the plugin.

## Operation Verification

### 1. Check Plugin Loading

```vim
:ContainerDebug
```

This displays the plugin status and debug information.

### 2. Check Configuration

```vim
:ContainerConfig
```

This displays the current configuration.

### 3. Check Docker

```vim
:ContainerOpen
```

This checks Docker availability.

## Troubleshooting

### When Plugin Doesn't Load

1. Verify the path is correct
```lua
:lua print(vim.fn.expand("~/path/to/container.nvim"))
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
vim.api.nvim_create_user_command('ContainerReload', function()
  -- Clear module cache
  for module_name, _ in pairs(package.loaded) do
    if module_name:match("^container") then
      package.loaded[module_name] = nil
    end
  end

  -- Reload plugin
  require('container').setup()
  print("container.nvim reloaded!")
end, {})
```

### Log File Configuration

```lua
config = function()
  require('container').setup({
    log_level = 'debug',
    -- Set log file
    log_file = vim.fn.stdpath('data') .. '/container.log',
  })

  -- Command to open log file
  vim.api.nvim_create_user_command('ContainerLogFile', function()
    vim.cmd('edit ' .. vim.fn.stdpath('data') .. '/container.log')
  end, {})
end,
```

Now you can integrate and test the container.nvim plugin with Lazy.nvim!
