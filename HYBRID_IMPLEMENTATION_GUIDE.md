# Hybrid Architecture Implementation Guide

This guide provides detailed implementation steps for the recommended hybrid approach to deep plugin integration in devcontainer.nvim.

## Phase 1: Enhanced Command Forwarding Framework

### 1.1 Plugin Integration API

Create a new module `lua/devcontainer/plugin_integration/init.lua`:

```lua
local M = {}

-- Registry of integrated plugins
M.registry = {}

-- Register a plugin integration
function M.register(config)
  local integration = {
    name = config.name,
    patterns = config.patterns or {},
    commands = config.commands or {},
    wrapper = config.wrapper,
    detector = config.detector,
    setup = config.setup,
    teardown = config.teardown,
  }
  
  M.registry[config.name] = integration
  
  -- Auto-setup if plugin is loaded
  if config.auto_setup then
    M._setup_integration(integration)
  end
end

-- Wrap a command for container execution
function M.wrap_command(plugin_name, cmd, args)
  local integration = M.registry[plugin_name]
  if not integration then
    return nil
  end
  
  if integration.wrapper then
    return integration.wrapper(cmd, args)
  end
  
  -- Default wrapper
  return M._default_wrapper(cmd, args)
end

-- Get integration for a command
function M.get_integration_for_command(cmd)
  for name, integration in pairs(M.registry) do
    for _, pattern in ipairs(integration.patterns) do
      if cmd:match(pattern) then
        return integration
      end
    end
    
    for _, command in ipairs(integration.commands) do
      if cmd == command then
        return integration
      end
    end
  end
  
  return nil
end
```

### 1.2 Integration Templates

Create `lua/devcontainer/plugin_integration/templates.lua`:

```lua
local M = {}

-- Template for test runner plugins
M.test_runner = function(config)
  return {
    name = config.name,
    patterns = config.patterns or { "^Test" },
    detector = function()
      return vim.fn.exists(':' .. (config.main_command or 'TestNearest')) == 2
    end,
    wrapper = function(cmd, args)
      local docker = require('devcontainer.docker')
      local container_id = require('devcontainer').get_container_id()
      
      -- Extract test command from args
      local test_cmd = config.extract_command(cmd, args)
      
      -- Prepend any required setup (cd to workspace, set env, etc.)
      local full_cmd = config.prepare_command(test_cmd)
      
      return docker.exec_command(container_id, full_cmd, {
        user = config.user or 'vscode',
        interactive = false,
        stream = true,
      })
    end,
    setup = function()
      -- Override plugin commands
      for _, cmd in ipairs(config.commands) do
        vim.cmd(string.format([[
          command! -nargs=* %s lua require('devcontainer.plugin_integration').execute('%s', '<args>')
        ]], cmd, cmd))
      end
    end
  }
end

-- Template for linter plugins
M.linter = function(config)
  return {
    name = config.name,
    patterns = config.patterns or { "^Lint" },
    wrapper = function(cmd, args)
      local file_path = vim.fn.expand('%:p')
      local container_path = require('devcontainer.lsp.path').to_container(file_path)
      
      local lint_cmd = string.format(
        config.command_template,
        config.linter,
        container_path
      )
      
      return require('devcontainer.docker').exec_command(
        require('devcontainer').get_container_id(),
        lint_cmd,
        { user = 'vscode', stream = true }
      )
    end
  }
end

-- Template for formatter plugins
M.formatter = function(config)
  return {
    name = config.name,
    patterns = config.patterns or { "^Format" },
    wrapper = function(cmd, args)
      local file_path = vim.fn.expand('%:p')
      local container_path = require('devcontainer.lsp.path').to_container(file_path)
      
      -- Read current buffer content
      local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
      local content = table.concat(lines, '\n')
      
      -- Format in container
      local format_cmd = string.format(
        config.command_template,
        config.formatter,
        container_path
      )
      
      local result = require('devcontainer.docker').exec_command(
        require('devcontainer').get_container_id(),
        format_cmd,
        { 
          stdin = content,
          user = 'vscode',
          capture_output = true
        }
      )
      
      -- Update buffer with formatted content
      if result.success then
        local formatted_lines = vim.split(result.stdout, '\n')
        vim.api.nvim_buf_set_lines(0, 0, -1, false, formatted_lines)
      end
      
      return result
    end
  }
end

return M
```

### 1.3 Common Plugin Integrations

Create `lua/devcontainer/plugin_integration/plugins/vim_test.lua`:

```lua
local templates = require('devcontainer.plugin_integration.templates')

return templates.test_runner({
  name = 'vim-test',
  main_command = 'TestNearest',
  commands = { 'TestNearest', 'TestFile', 'TestSuite', 'TestLast', 'TestVisit' },
  
  extract_command = function(cmd, args)
    -- vim-test stores the command in a global variable
    return vim.g.test_command or ''
  end,
  
  prepare_command = function(test_cmd)
    local workspace = require('devcontainer').get_workspace_folder()
    return string.format('cd %s && %s', workspace, test_cmd)
  end,
})
```

### 1.4 Auto-detection System

Create `lua/devcontainer/plugin_integration/detector.lua`:

```lua
local M = {}

-- Known plugins and their integration modules
M.known_plugins = {
  ['vim-test/vim-test'] = 'vim_test',
  ['klen/nvim-test'] = 'nvim_test',
  ['dense-analysis/ale'] = 'ale',
  ['neomake/neomake'] = 'neomake',
  ['sbdchd/neoformat'] = 'neoformat',
  ['nvim-neotest/neotest'] = 'neotest',
}

-- Auto-detect and load integrations
function M.auto_detect()
  local loaded = {}
  
  -- Check for known plugins
  for plugin_path, integration_name in pairs(M.known_plugins) do
    if M._is_plugin_loaded(plugin_path) then
      local ok, integration = pcall(require, 'devcontainer.plugin_integration.plugins.' .. integration_name)
      if ok then
        require('devcontainer.plugin_integration').register(integration)
        table.insert(loaded, integration_name)
      end
    end
  end
  
  return loaded
end

-- Check if a plugin is loaded
function M._is_plugin_loaded(plugin_path)
  -- Check common plugin managers
  
  -- Lazy.nvim
  local ok, lazy = pcall(require, 'lazy.core.config')
  if ok then
    return lazy.plugins[plugin_path] ~= nil
  end
  
  -- Packer
  if packer_plugins and packer_plugins[plugin_path] then
    return true
  end
  
  -- Vim-plug
  if vim.fn.exists('g:plugs') == 1 then
    local plug_name = vim.split(plugin_path, '/')[2]
    return vim.g.plugs[plug_name] ~= nil
  end
  
  return false
end

return M
```

## Phase 2: Remote Plugin Host Support

### 2.1 Container Plugin Host

Create `lua/devcontainer/remote_plugin/host.lua`:

```lua
local M = {}

-- Setup remote plugin host in container
function M.setup_host(container_id)
  local setup_script = [[
    #!/bin/bash
    # Install Neovim plugin host if not present
    if ! command -v nvim-plugin-host &> /dev/null; then
      python3 -m pip install --user pynvim
      npm install -g neovim
    fi
    
    # Start plugin host
    nvim --headless --cmd "call rpcstart('0.0.0.0', 7777)" &
    echo $! > /tmp/nvim-plugin-host.pid
  ]]
  
  -- Copy and execute setup script
  local docker = require('devcontainer.docker')
  docker.exec_command(container_id, 'bash -c "' .. setup_script .. '"', {
    user = 'vscode',
    detach = true
  })
  
  -- Wait for host to be ready
  vim.wait(2000, function()
    return M._check_host_ready(container_id)
  end)
end

-- Connect to remote plugin host
function M.connect(container_id)
  -- Get container IP
  local docker = require('devcontainer.docker')
  local ip_result = docker.exec_command(container_id, 
    'hostname -I | awk \'{print $1}\'',
    { capture_output = true }
  )
  
  if not ip_result.success then
    return nil, "Failed to get container IP"
  end
  
  local container_ip = vim.trim(ip_result.stdout)
  
  -- Connect to remote host
  local channel = vim.fn.sockconnect('tcp', container_ip .. ':7777', {
    rpc = true,
    on_request = M._handle_request,
  })
  
  return channel
end

-- Load plugin in remote host
function M.load_remote_plugin(channel, plugin_path)
  return vim.rpcrequest(channel, 'nvim_exec_lua', [[
    return require(']] .. plugin_path .. [[')
  ]], {})
end

return M
```

### 2.2 Plugin Router

Create `lua/devcontainer/plugin_integration/router.lua`:

```lua
local M = {}

-- Plugin execution strategies
M.strategies = {
  COMMAND = 'command',      -- Simple command forwarding
  REMOTE = 'remote',        -- Remote plugin execution
  NATIVE = 'native',        -- Direct integration (LSP, DAP)
  LOCAL = 'local',          -- Run on host (UI plugins)
}

-- Plugin category definitions
M.categories = {
  -- UI plugins should run locally
  ui = {
    'telescope.nvim',
    'nvim-tree.lua',
    'lualine.nvim',
    'bufferline.nvim',
  },
  
  -- Code analysis plugins benefit from remote execution
  analysis = {
    'nvim-treesitter',
    'nvim-lint',
    'null-ls.nvim',
  },
  
  -- Simple command plugins use forwarding
  commands = {
    'vim-test',
    'neoformat',
    'vim-fugitive',
  },
  
  -- Special handling
  native = {
    'nvim-lspconfig',
    'nvim-dap',
    'nvim-cmp',
  },
}

-- Determine execution strategy for a plugin
function M.get_strategy(plugin_name)
  -- Check user overrides first
  local config = require('devcontainer.config').get()
  if config.plugin_strategies and config.plugin_strategies[plugin_name] then
    return config.plugin_strategies[plugin_name]
  end
  
  -- Check categories
  for category, plugins in pairs(M.categories) do
    for _, name in ipairs(plugins) do
      if name == plugin_name then
        if category == 'ui' then
          return M.strategies.LOCAL
        elseif category == 'analysis' then
          return M.strategies.REMOTE
        elseif category == 'commands' then
          return M.strategies.COMMAND
        elseif category == 'native' then
          return M.strategies.NATIVE
        end
      end
    end
  end
  
  -- Default strategy
  return M.strategies.COMMAND
end

-- Route plugin command based on strategy
function M.route_command(plugin_name, cmd, args)
  local strategy = M.get_strategy(plugin_name)
  
  if strategy == M.strategies.COMMAND then
    return require('devcontainer.plugin_integration').wrap_command(plugin_name, cmd, args)
  elseif strategy == M.strategies.REMOTE then
    return require('devcontainer.remote_plugin').execute_remote(plugin_name, cmd, args)
  elseif strategy == M.strategies.NATIVE then
    -- Native plugins handle their own integration
    return nil
  elseif strategy == M.strategies.LOCAL then
    -- Execute locally
    vim.cmd(cmd .. ' ' .. args)
    return { success = true }
  end
end

return M
```

## Phase 3: Smart Integration System

### 3.1 Performance Monitor

Create `lua/devcontainer/plugin_integration/monitor.lua`:

```lua
local M = {}

-- Performance metrics storage
M.metrics = {}

-- Record command execution
function M.record_execution(plugin_name, strategy, duration, success)
  if not M.metrics[plugin_name] then
    M.metrics[plugin_name] = {
      executions = 0,
      total_duration = 0,
      failures = 0,
      strategies = {}
    }
  end
  
  local metric = M.metrics[plugin_name]
  metric.executions = metric.executions + 1
  metric.total_duration = metric.total_duration + duration
  
  if not success then
    metric.failures = metric.failures + 1
  end
  
  -- Track per-strategy metrics
  if not metric.strategies[strategy] then
    metric.strategies[strategy] = {
      executions = 0,
      total_duration = 0,
      failures = 0
    }
  end
  
  local strategy_metric = metric.strategies[strategy]
  strategy_metric.executions = strategy_metric.executions + 1
  strategy_metric.total_duration = strategy_metric.total_duration + duration
  
  if not success then
    strategy_metric.failures = strategy_metric.failures + 1
  end
end

-- Get optimal strategy based on metrics
function M.suggest_strategy(plugin_name)
  local metric = M.metrics[plugin_name]
  if not metric or metric.executions < 10 then
    return nil -- Not enough data
  end
  
  local best_strategy = nil
  local best_score = -1
  
  for strategy, data in pairs(metric.strategies) do
    if data.executions >= 5 then
      local avg_duration = data.total_duration / data.executions
      local success_rate = 1 - (data.failures / data.executions)
      
      -- Score based on speed and reliability
      local score = success_rate * (1 / avg_duration)
      
      if score > best_score then
        best_score = score
        best_strategy = strategy
      end
    end
  end
  
  return best_strategy
end

-- Export metrics for analysis
function M.export_metrics()
  local report = {}
  
  for plugin_name, metric in pairs(M.metrics) do
    local avg_duration = metric.total_duration / metric.executions
    local success_rate = 1 - (metric.failures / metric.executions)
    
    report[plugin_name] = {
      executions = metric.executions,
      average_duration = avg_duration,
      success_rate = success_rate,
      strategies = {}
    }
    
    for strategy, data in pairs(metric.strategies) do
      report[plugin_name].strategies[strategy] = {
        executions = data.executions,
        average_duration = data.total_duration / data.executions,
        success_rate = 1 - (data.failures / data.executions)
      }
    end
  end
  
  return report
end

return M
```

### 3.2 Integration Manager

Create `lua/devcontainer/plugin_integration/manager.lua`:

```lua
local M = {}

-- Initialize plugin integration system
function M.setup()
  -- Auto-detect plugins
  local detector = require('devcontainer.plugin_integration.detector')
  local loaded = detector.auto_detect()
  
  -- Setup performance monitoring
  local monitor = require('devcontainer.plugin_integration.monitor')
  
  -- Override vim.cmd to intercept plugin commands
  local original_cmd = vim.cmd
  vim.cmd = function(cmd)
    -- Try to route through integration system
    local integration = require('devcontainer.plugin_integration').get_integration_for_command(cmd)
    
    if integration and require('devcontainer').is_container_active() then
      local start_time = vim.loop.now()
      local router = require('devcontainer.plugin_integration.router')
      
      -- Get optimal strategy
      local strategy = router.get_strategy(integration.name)
      local suggested = monitor.suggest_strategy(integration.name)
      if suggested then
        strategy = suggested
      end
      
      -- Execute with monitoring
      local result = router.route_command(integration.name, cmd, '')
      local duration = vim.loop.now() - start_time
      
      monitor.record_execution(integration.name, strategy, duration, result and result.success)
      
      if result then
        return result
      end
    end
    
    -- Fallback to original command
    return original_cmd(cmd)
  end
  
  return loaded
end

-- Get integration status
function M.status()
  local integrations = require('devcontainer.plugin_integration').registry
  local monitor = require('devcontainer.plugin_integration.monitor')
  
  local status = {
    loaded_integrations = vim.tbl_keys(integrations),
    metrics = monitor.export_metrics(),
    active_container = require('devcontainer').is_container_active(),
  }
  
  return status
end

-- Create user command for managing integrations
function M.create_commands()
  vim.api.nvim_create_user_command('DevcontainerIntegrations', function(opts)
    if opts.args == 'status' then
      local status = M.status()
      print(vim.inspect(status))
    elseif opts.args == 'reload' then
      M.setup()
      print("Reloaded plugin integrations")
    elseif opts.args == 'metrics' then
      local metrics = require('devcontainer.plugin_integration.monitor').export_metrics()
      print(vim.inspect(metrics))
    else
      print("Usage: :DevcontainerIntegrations {status|reload|metrics}")
    end
  end, {
    nargs = 1,
    complete = function()
      return { 'status', 'reload', 'metrics' }
    end
  })
end

return M
```

## Integration Example: vim-test

Here's a complete example of integrating vim-test using the hybrid architecture:

```lua
-- lua/devcontainer/plugin_integration/plugins/vim_test.lua
local M = {}

function M.setup()
  -- Check if vim-test is loaded
  if vim.fn.exists(':TestNearest') ~= 2 then
    return false
  end
  
  -- Store original test strategy
  M.original_strategy = vim.g['test#strategy']
  
  -- Create custom strategy for devcontainer
  vim.g['test#custom_strategies'] = vim.g['test#custom_strategies'] or {}
  vim.g['test#custom_strategies'].devcontainer = function(cmd)
    local docker = require('devcontainer.docker')
    local container_id = require('devcontainer').get_container_id()
    
    if not container_id then
      -- Fallback to original strategy
      return vim.fn['test#strategy#' .. (M.original_strategy or 'basic')](cmd)
    end
    
    -- Prepare command for container execution
    local workspace = require('devcontainer').get_workspace_folder()
    local full_cmd = string.format('cd %s && %s', workspace, cmd)
    
    -- Execute in container
    docker.exec_command(container_id, full_cmd, {
      user = 'vscode',
      interactive = false,
      on_output = function(line)
        -- Display test output in real-time
        vim.schedule(function()
          print(line)
        end)
      end,
      on_complete = function(result)
        vim.schedule(function()
          if result.success then
            print("✓ Tests completed successfully")
          else
            print("✗ Tests failed")
          end
        end)
      end
    })
  end
  
  -- Set devcontainer as the test strategy
  vim.g['test#strategy'] = 'devcontainer'
  
  return true
end

function M.teardown()
  -- Restore original strategy
  if M.original_strategy then
    vim.g['test#strategy'] = M.original_strategy
  end
end

return {
  name = 'vim-test',
  setup = M.setup,
  teardown = M.teardown,
  auto_setup = true,
}
```

## Configuration Example

Users can configure the plugin integration system:

```lua
require('devcontainer').setup({
  -- Existing configuration...
  
  plugin_integration = {
    -- Enable automatic plugin detection
    auto_detect = true,
    
    -- Override strategies for specific plugins
    strategies = {
      ['nvim-treesitter'] = 'remote',
      ['telescope.nvim'] = 'local',
      ['vim-test'] = 'command',
    },
    
    -- Custom integrations
    custom = {
      ['my-custom-plugin'] = {
        strategy = 'command',
        wrapper = function(cmd, args)
          -- Custom wrapper logic
        end
      }
    },
    
    -- Performance optimization
    performance = {
      -- Enable adaptive strategy selection
      adaptive = true,
      
      -- Minimum executions before adaptation
      adaptation_threshold = 10,
      
      -- Cache command results
      enable_cache = true,
      cache_ttl = 300, -- 5 minutes
    }
  }
})
```

## Testing the Integration

Create `lua/devcontainer/plugin_integration/test.lua`:

```lua
local M = {}

-- Test a specific integration
function M.test_integration(plugin_name)
  local integration = require('devcontainer.plugin_integration').registry[plugin_name]
  if not integration then
    print("Integration not found: " .. plugin_name)
    return false
  end
  
  print("Testing integration: " .. plugin_name)
  
  -- Test detection
  if integration.detector then
    local detected = integration.detector()
    print("  Detection: " .. (detected and "✓" or "✗"))
  end
  
  -- Test setup
  if integration.setup then
    local ok, err = pcall(integration.setup)
    print("  Setup: " .. (ok and "✓" or "✗ " .. tostring(err)))
  end
  
  -- Test command wrapping
  if integration.wrapper then
    local test_cmd = integration.commands and integration.commands[1] or "test"
    local wrapped = integration.wrapper(test_cmd, "")
    print("  Wrapper: " .. (wrapped and "✓" or "✗"))
  end
  
  return true
end

-- Run all integration tests
function M.test_all()
  local registry = require('devcontainer.plugin_integration').registry
  local results = {}
  
  for name, _ in pairs(registry) do
    results[name] = M.test_integration(name)
  end
  
  return results
end

return M
```

This implementation guide provides a solid foundation for implementing the hybrid architecture, with clear examples and extensible patterns that can grow with the project's needs.