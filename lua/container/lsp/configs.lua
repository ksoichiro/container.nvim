-- Language-specific LSP configurations for container environments
local M = {}

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

return M
