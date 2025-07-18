-- Language-specific LSP configurations for container environments
local M = {}

-- Strategy configuration for LSP servers
M.strategy_config = {
  -- Default strategy for all servers
  default = 'intercept', -- Use Strategy C (intercept) as default

  -- Server-specific strategy overrides
  servers = {
    gopls = 'intercept', -- Go: Use interception for reliable path handling
    pylsp = 'intercept', -- Python: Use interception
    pyright = 'intercept', -- Python (alternative): Use interception
    tsserver = 'intercept', -- TypeScript: Use interception
    rust_analyzer = 'intercept', -- Rust: Use interception
    clangd = 'intercept', -- C/C++: Use interception
    lua_ls = 'intercept', -- Lua: Use interception like other servers
  },

  -- Feature flags
  features = {
    auto_detection = true, -- Auto-detect best strategy based on environment
    prefer_performance = true, -- Prefer faster strategy when both work
    enable_fallback = false, -- Fallback disabled as only intercept strategy is available
  },
}

-- Language-specific settings that are applied in addition to base config
M.language_configs = {
  gopls = {
    init_options = {
      usePlaceholders = true,
      completeUnimported = true,
      deepCompletion = true,
      directoryFilters = { '-node_modules', '-vendor', '-.git' },
    },
    settings = {
      gopls = {
        directoryFilters = { '-node_modules', '-vendor', '-.git' },
        usePlaceholders = true,
        completeUnimported = true,
        deepCompletion = true,
        staticcheck = true,
        -- Minimize file system access in container to reduce ENOENT errors
        gofumpt = false,
        semanticTokens = false,
        -- Reduce file system operations
        symbolMatcher = 'CaseSensitive',
        symbolStyle = 'Dynamic',
        -- Use explicit workspace configuration instead of watching
        expandWorkspaceToModule = false,
      },
    },
  },

  pylsp = {
    settings = {
      pylsp = {
        plugins = {
          pycodestyle = { enabled = false },
          mccabe = { enabled = false },
          pyflakes = { enabled = false },
          pylint = { enabled = false },
        },
      },
    },
  },

  rust_analyzer = {
    settings = {
      ['rust-analyzer'] = {
        checkOnSave = {
          command = 'cargo clippy',
        },
      },
    },
  },

  tsserver = {
    init_options = {
      preferences = {
        disableSuggestions = false,
      },
    },
  },

  lua_ls = {
    settings = {
      Lua = {
        runtime = {
          version = 'LuaJIT',
        },
        diagnostics = {
          globals = { 'vim' },
        },
        workspace = {
          library = vim.api.nvim_get_runtime_file('', true),
          checkThirdParty = false,
        },
        telemetry = {
          enable = false,
        },
      },
    },
  },
}

-- Get language-specific configuration for a server
function M.get_language_config(server_name)
  return M.language_configs[server_name] or {}
end

-- Add or update language-specific configuration
function M.add_language_config(server_name, config)
  M.language_configs[server_name] = vim.tbl_deep_extend('force', M.language_configs[server_name] or {}, config)
end

-- Get strategy configuration
function M.get_strategy_config()
  return vim.tbl_deep_extend('force', {}, M.strategy_config)
end

-- Update strategy configuration
function M.update_strategy_config(config)
  M.strategy_config = vim.tbl_deep_extend('force', M.strategy_config, config)
end

-- Get strategy for a specific server
function M.get_server_strategy(server_name)
  return M.strategy_config.servers[server_name] or M.strategy_config.default
end

-- Set strategy for a specific server
function M.set_server_strategy(server_name, strategy)
  M.strategy_config.servers[server_name] = strategy
end

return M
