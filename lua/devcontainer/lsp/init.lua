local M = {}
local log = require('devcontainer.utils.log')
-- local async = require('devcontainer.utils.async')  -- Reserved for future use

-- State management
local state = {
  servers = {},
  clients = {},
  port_mappings = {},
  container_id = nil
}

-- Initialize LSP module
function M.setup(config)
  log.debug('LSP: Initializing LSP module')
  M.config = vim.tbl_deep_extend('force', {
    auto_setup = true,
    timeout = 5000,
    servers = {}
  }, config or {})
end

-- Set the container ID for LSP operations
function M.set_container_id(container_id)
  state.container_id = container_id
  log.debug('LSP: Set container ID: ' .. container_id)
end

-- Detect available LSP servers in the container
function M.detect_language_servers()
  if not state.container_id then
    log.error('LSP: No container ID set')
    return {}
  end

  log.info('LSP: Detecting language servers in container')

  -- Common LSP server executables to check
  local common_servers = {
    -- Lua
    { name = 'lua_ls', cmd = 'lua-language-server', languages = {'lua'} },
    -- Python
    { name = 'pylsp', cmd = 'pylsp', languages = {'python'} },
    { name = 'pyright', cmd = 'pyright-langserver', languages = {'python'} },
    -- JavaScript/TypeScript
    { name = 'tsserver', cmd = 'typescript-language-server', languages = {'javascript', 'typescript'} },
    { name = 'eslint', cmd = 'vscode-eslint-language-server', languages = {'javascript', 'typescript'} },
    -- Go
    { name = 'gopls', cmd = 'gopls', languages = {'go'} },
    -- Rust
    { name = 'rust_analyzer', cmd = 'rust-analyzer', languages = {'rust'} },
    -- C/C++
    { name = 'clangd', cmd = 'clangd', languages = {'c', 'cpp'} },
    -- Java
    { name = 'jdtls', cmd = 'jdtls', languages = {'java'} },
    -- Ruby
    { name = 'solargraph', cmd = 'solargraph', languages = {'ruby'} },
    -- PHP
    { name = 'intelephense', cmd = 'intelephense', languages = {'php'} },
  }

  local detected_servers = {}

  for _, server in ipairs(common_servers) do
    -- Lazy load docker module to avoid circular dependencies
    local docker = require('devcontainer.docker.init')

    log.debug('LSP: Checking for ' .. server.name .. ' (' .. server.cmd .. ')')

    -- Use synchronous execution to check if server exists
    local args = {"exec", "--user", "vscode", "-e", "PATH=/home/vscode/.local/bin:/usr/local/python/current/bin:/usr/local/go/bin:/go/bin:/usr/local/bin:/usr/bin:/bin", state.container_id, "which", server.cmd}
    local result = docker.run_docker_command(args)

    if result and result.success then
      log.info('LSP: Found ' .. server.name .. ' in container at: ' .. vim.trim(result.stdout))
      detected_servers[server.name] = {
        cmd = server.cmd,
        languages = server.languages,
        available = true,
        path = vim.trim(result.stdout)
      }
    else
      log.debug('LSP: ' .. server.name .. ' not found')
    end
  end

  state.servers = detected_servers
  return detected_servers
end

-- Setup LSP servers in the container
function M.setup_lsp_in_container()
  if not M.config.auto_setup then
    log.debug('LSP: Auto-setup disabled')
    return
  end

  local servers = M.detect_language_servers()

  for name, server in pairs(servers) do
    if server.available then
      log.info('LSP: Setting up ' .. name)
      M.create_lsp_client(name, server)
    end
  end
end

-- Create an LSP client for a server in the container
function M.create_lsp_client(name, server_config)
  if not name or type(name) ~= "string" then
    log.error("Invalid server name provided")
    return
  end
  if not server_config or type(server_config) ~= "table" then
    log.error("Invalid server config provided")
    return
  end
  
  log.debug("Creating LSP client for %s", name)
  local lsp_config = M._prepare_lsp_config(name, server_config)

  -- Check if lspconfig is available
  local ok, lspconfig = pcall(require, 'lspconfig')
  if not ok then
    print("ERROR: nvim-lspconfig not found")
    log.warn('LSP: nvim-lspconfig not found, skipping LSP setup')
    return
  end

  -- Check if the server is supported by lspconfig
  if not lspconfig[name] then
    print("ERROR: Server " .. name .. " not supported by lspconfig")
    log.warn('LSP: Server ' .. name .. ' not supported by lspconfig')
    return
  end

  log.debug("Getting forwarding command for %s", name)
  -- Get forwarding module for communication setup
  local forwarding = require('devcontainer.lsp.forwarding')

  -- Configure the command for container communication
  local cmd = forwarding.get_client_cmd(name, server_config, state.container_id)
  if cmd then
    log.debug("LSP command: %s", table.concat(cmd, " "))
    lsp_config.cmd = cmd
    lsp_config.handlers = forwarding.create_client_middleware()
  else
    print("ERROR: Failed to setup communication for " .. name)
    log.error('LSP: Failed to setup communication for ' .. name)
    return
  end

  log.debug("Setting up LSP client with lspconfig")

  -- Instead of creating a new server, directly start the client with custom configuration
  -- This bypasses lspconfig's setup and creates the client directly
  local client_id = vim.lsp.start_client(lsp_config)

  if client_id then
    log.info("LSP client started with ID: %s", client_id)

    -- Attach to current buffer if it matches the filetype
    local bufnr = vim.api.nvim_get_current_buf()
    local ft = vim.api.nvim_buf_get_option(bufnr, 'filetype')

    -- Attach to current buffer if it matches the supported filetypes
    local supported_filetypes = server_config.filetypes or server_config.languages or {}
    if vim.tbl_contains(supported_filetypes, ft) then
      vim.lsp.buf_attach_client(bufnr, client_id)
      log.info("Attached LSP client %s to buffer %s (filetype: %s)", name, bufnr, ft)
    else
      log.debug("Filetype %s not supported by %s (supported: %s)", ft, name, vim.inspect(supported_filetypes))
    end

    -- Store the client ID and configuration for later reference
    state.clients[name] = {
      client_id = client_id,
      config = lsp_config,
      server_config = server_config
    }
    
    -- Setup autocommand for automatic attachment to new buffers
    M._setup_auto_attach(name, server_config, client_id)
  else
    log.error("Failed to start LSP client for %s", name)
    return
  end

  -- Attach to existing loaded buffers with matching filetypes
  vim.schedule(function()
    M._attach_to_existing_buffers(name, server_config, client_id)
  end)

  log.info('LSP: Successfully set up %s', name)
end

-- Prepare LSP configuration for a server
function M._prepare_lsp_config(name, server_config)
  local config = vim.tbl_deep_extend('force', {
    -- Base configuration
    name = name,
    filetypes = server_config.languages,

    -- Command will be overridden by forwarding module
    cmd = { 'echo', 'LSP server not properly configured' },

    -- Root directory pattern
    root_dir = function(fname)
      local util = require('lspconfig.util')
      return util.find_git_ancestor(fname) or util.path.dirname(fname)
    end,

    -- Capabilities
    capabilities = vim.lsp.protocol.make_client_capabilities(),

    -- On attach callback
    on_attach = function(client, bufnr)
      log.debug('LSP: ' .. name .. ' attached to buffer ' .. bufnr)
      if M.config.on_attach then
        M.config.on_attach(client, bufnr)
      end
    end,
  }, M.config.servers[name] or {})

  return config
end

-- Stop all LSP clients
function M.stop_all()
  log.info('LSP: Stopping all LSP clients')

  for name, _ in pairs(state.clients) do
    M.stop_client(name)
  end

  state.servers = {}
  state.clients = {}
  state.port_mappings = {}
  state.container_id = nil
end

-- Stop a specific LSP client
function M.stop_client(name)
  local client_info = state.clients[name]
  if not client_info then
    return
  end

  -- Stop any active LSP clients
  local clients = vim.lsp.get_active_clients({ name = name })
  for _, client in ipairs(clients) do
    client.stop()
  end

  state.clients[name] = nil
  log.info('LSP: Stopped ' .. name)
end

-- Get current LSP state
function M.get_state()
  return {
    servers = state.servers,
    clients = vim.tbl_keys(state.clients),
    container_id = state.container_id,
    config = M.config
  }
end

-- Setup autocommand for automatic attachment to new buffers
function M._setup_auto_attach(server_name, server_config, client_id)
  local supported_filetypes = server_config.filetypes or server_config.languages or {}
  
  if #supported_filetypes == 0 then
    log.debug("No filetypes specified for %s, skipping auto-attach setup", server_name)
    return
  end
  
  -- Create autocmd group for this server
  local group_name = "DevcontainerLSP_" .. server_name
  vim.api.nvim_create_augroup(group_name, { clear = true })
  
  -- Setup autocommand for each supported filetype
  for _, filetype in ipairs(supported_filetypes) do
    vim.api.nvim_create_autocmd({"BufEnter", "BufNewFile"}, {
      group = group_name,
      pattern = "*",
      callback = function(args)
        local buf = args.buf
        local ft = vim.api.nvim_buf_get_option(buf, 'filetype')
        
        if ft == filetype then
          -- Check if client is still running
          local client = vim.lsp.get_client_by_id(client_id)
          if client and client.is_stopped ~= true then
            -- Check if this buffer is already attached
            local attached_clients = vim.lsp.get_active_clients({ bufnr = buf })
            local already_attached = false
            for _, attached_client in ipairs(attached_clients) do
              if attached_client.id == client_id then
                already_attached = true
                break
              end
            end
            
            if not already_attached then
              vim.lsp.buf_attach_client(buf, client_id)
              log.info("Auto-attached %s LSP to buffer %s (filetype: %s)", server_name, buf, ft)
            end
          else
            log.debug("LSP client %s is no longer active, skipping auto-attach", server_name)
          end
        end
      end,
    })
  end
  
  log.debug("Setup auto-attach for %s (filetypes: %s)", server_name, vim.inspect(supported_filetypes))
end

-- Attach LSP client to existing buffers with matching filetypes
function M._attach_to_existing_buffers(server_name, server_config, client_id)
  local supported_filetypes = server_config.filetypes or server_config.languages or {}
  
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then
      local ft = vim.api.nvim_buf_get_option(buf, 'filetype')
      if vim.tbl_contains(supported_filetypes, ft) then
        -- Check if this buffer is already attached
        local attached_clients = vim.lsp.get_active_clients({ bufnr = buf })
        local already_attached = false
        for _, attached_client in ipairs(attached_clients) do
          if attached_client.id == client_id then
            already_attached = true
            break
          end
        end
        
        if not already_attached then
          vim.lsp.buf_attach_client(buf, client_id)
          log.info("Attached %s LSP to existing buffer %s (filetype: %s)", server_name, buf, ft)
        end
      end
    end
  end
end

return M