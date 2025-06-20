local M = {}
local log = require('container.utils.log')
-- local async = require('container.utils.async')  -- Reserved for future use

-- State management
local state = {
  servers = {},
  clients = {},
  port_mappings = {},
  container_id = nil,
}

-- Track if path mappings have been initialized
local path_mappings_initialized = false

-- Initialize LSP module
function M.setup(config)
  log.debug('LSP: Initializing LSP module')
  M.config = vim.tbl_deep_extend('force', {
    auto_setup = true,
    timeout = 5000,
    servers = {},
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
    { name = 'lua_ls', cmd = 'lua-language-server', languages = { 'lua' } },
    -- Python
    { name = 'pylsp', cmd = 'pylsp', languages = { 'python' } },
    { name = 'pyright', cmd = 'pyright-langserver', languages = { 'python' } },
    -- JavaScript/TypeScript
    { name = 'tsserver', cmd = 'typescript-language-server', languages = { 'javascript', 'typescript' } },
    { name = 'eslint', cmd = 'vscode-eslint-language-server', languages = { 'javascript', 'typescript' } },
    -- Go
    { name = 'gopls', cmd = 'gopls', languages = { 'go' } },
    -- Rust
    { name = 'rust_analyzer', cmd = 'rust-analyzer', languages = { 'rust' } },
    -- C/C++
    { name = 'clangd', cmd = 'clangd', languages = { 'c', 'cpp' } },
    -- Java
    { name = 'jdtls', cmd = 'jdtls', languages = { 'java' } },
    -- Ruby
    { name = 'solargraph', cmd = 'solargraph', languages = { 'ruby' } },
    -- PHP
    { name = 'intelephense', cmd = 'intelephense', languages = { 'php' } },
  }

  local detected_servers = {}

  for _, server in ipairs(common_servers) do
    -- Lazy load docker module to avoid circular dependencies
    local docker = require('container.docker.init')

    log.debug('LSP: Checking for ' .. server.name .. ' (' .. server.cmd .. ')')

    -- Use synchronous execution to check if server exists
    local args = {
      'exec',
    }

    -- Add environment-specific args (includes user and env vars)
    local environment = require('container.environment')
    local config = require('container').get_state().current_config
    local env_args = environment.build_lsp_args(config)
    for _, arg in ipairs(env_args) do
      table.insert(args, arg)
    end

    -- Add container and command
    table.insert(args, state.container_id)
    table.insert(args, 'which')
    table.insert(args, server.cmd)
    local result = docker.run_docker_command(args)

    if result and result.success then
      log.info('LSP: Found ' .. server.name .. ' in container at: ' .. vim.trim(result.stdout))
      detected_servers[server.name] = {
        cmd = server.cmd,
        languages = server.languages,
        available = true,
        path = vim.trim(result.stdout),
      }
    else
      log.debug('LSP: ' .. server.name .. ' not found')
    end
  end

  state.servers = detected_servers
  return detected_servers
end

-- Check if LSP client already exists for a server
function M.client_exists(server_name)
  -- Check active clients first
  local active_clients = vim.lsp.get_active_clients({ name = server_name })
  if #active_clients > 0 then
    log.debug('LSP: Found existing active client for %s', server_name)
    return true, active_clients[1].id
  end

  -- Check our internal state
  if state.clients[server_name] and state.clients[server_name].client_id then
    -- Verify the client is still active
    local client = vim.lsp.get_client_by_id(state.clients[server_name].client_id)
    if client and not client.is_stopped then
      log.debug('LSP: Found existing client in state for %s', server_name)
      return true, client.id
    else
      -- Clean up stale state
      state.clients[server_name] = nil
      log.debug('LSP: Cleaned up stale client state for %s', server_name)
    end
  end

  return false, nil
end

-- Setup LSP servers in the container
function M.setup_lsp_in_container()
  if not M.config.auto_setup then
    log.debug('LSP: Auto-setup disabled')
    return
  end

  local servers = M.detect_language_servers()
  local setup_count = 0
  local skipped_count = 0

  for name, server in pairs(servers) do
    if server.available then
      -- Check if client already exists
      local exists, client_id = M.client_exists(name)
      if exists then
        log.info('LSP: Skipping %s - client already exists (ID: %s)', name, client_id)
        skipped_count = skipped_count + 1

        -- Update our state if needed
        if not state.clients[name] then
          state.clients[name] = {
            client_id = client_id,
            config = nil, -- Will be filled if needed
            server_config = server,
          }
        end
      else
        log.info('LSP: Setting up %s', name)
        M.create_lsp_client(name, server)
        setup_count = setup_count + 1
      end
    end
  end

  log.info('LSP: Setup complete - %d new clients, %d existing clients', setup_count, skipped_count)
end

-- Create an LSP client for a server in the container
function M.create_lsp_client(name, server_config)
  if not name or type(name) ~= 'string' then
    log.error('Invalid server name provided')
    return
  end
  if not server_config or type(server_config) ~= 'table' then
    log.error('Invalid server config provided')
    return
  end

  log.debug('Creating LSP client for %s', name)
  local lsp_config = M._prepare_lsp_config(name, server_config)

  -- Check if lspconfig is available
  local ok, lspconfig = pcall(require, 'lspconfig')
  if not ok then
    print('ERROR: nvim-lspconfig not found')
    log.warn('LSP: nvim-lspconfig not found, skipping LSP setup')
    return
  end

  -- Check if the server is supported by lspconfig
  if not lspconfig[name] then
    print('ERROR: Server ' .. name .. ' not supported by lspconfig')
    log.warn('LSP: Server ' .. name .. ' not supported by lspconfig')
    return
  end

  log.debug('Getting forwarding command for %s', name)
  -- Get forwarding module for communication setup
  local forwarding = require('container.lsp.forwarding')

  -- Configure the command for container communication
  local cmd = forwarding.get_client_cmd(name, server_config, state.container_id)
  if cmd then
    log.debug('LSP command: %s', table.concat(cmd, ' '))
    lsp_config.cmd = cmd
    lsp_config.handlers = forwarding.create_client_middleware()
  else
    print('ERROR: Failed to setup communication for ' .. name)
    log.error('LSP: Failed to setup communication for ' .. name)
    return
  end

  log.debug('Setting up LSP client with lspconfig')

  -- Use lspconfig to properly register the server configuration
  lspconfig[name].setup(lsp_config)

  -- For lspconfig to work properly with :LspInfo, we need to let it manage the client
  -- But we can trigger it to start by attaching to a buffer of the right filetype
  local bufnr = vim.api.nvim_get_current_buf()
  local ft = vim.api.nvim_buf_get_option(bufnr, 'filetype')

  -- Check if this filetype should trigger the LSP
  local supported_filetypes = server_config.filetypes or server_config.languages or {}
  local should_attach = vim.tbl_contains(supported_filetypes, ft)

  if should_attach then
    -- Trigger lspconfig by simulating a buffer attach
    vim.cmd('doautocmd FileType')
  end

  -- Store the server configuration for state tracking
  state.clients[name] = {
    client_id = nil, -- Will be set when client actually starts
    config = lsp_config,
    server_config = server_config,
  }

  -- Wait a moment for the client to start, then set up additional functionality
  vim.defer_fn(function()
    local clients = vim.lsp.get_active_clients({ name = name })
    local client_id = nil
    for _, client in ipairs(clients) do
      if client.name == name then
        client_id = client.id
        log.info('LSP client started via lspconfig with ID: %s', client_id)

        -- Update state with actual client ID
        if state.clients[name] then
          state.clients[name].client_id = client_id
        end

        -- Setup autocommand for automatic attachment to new buffers
        M._setup_auto_attach(name, server_config, client_id)

        -- Attach to existing loaded buffers with matching filetypes
        M._attach_to_existing_buffers(name, server_config, client_id)

        break
      end
    end

    if not client_id then
      log.warn('LSP client for %s not found after lspconfig setup', name)
    end
  end, 500) -- Increase delay to allow lspconfig to start the client

  log.info('LSP: Successfully configured %s via lspconfig', name)
end

-- Prepare LSP configuration for a server
function M._prepare_lsp_config(name, server_config)
  local path_utils = require('container.lsp.path')

  local config = vim.tbl_deep_extend('force', {
    -- Base configuration
    name = name,
    filetypes = server_config.languages,

    -- Command will be overridden by forwarding module
    cmd = { 'echo', 'LSP server not properly configured' },

    -- Root directory pattern - ensure we use container paths
    root_dir = function(fname)
      local util = require('lspconfig.util')
      -- Convert local path to container path for LSP server
      local container_path = path_utils.to_container_path(fname)

      if container_path then
        -- Use container workspace as root for consistency
        local workspace = path_utils.get_container_workspace()
        log.debug('LSP: Using container workspace as root: %s for file %s', workspace, fname)
        return workspace
      else
        -- Fallback to original logic
        return util.find_git_ancestor(fname) or util.path.dirname(fname)
      end
    end,

    -- Capabilities
    capabilities = vim.lsp.protocol.make_client_capabilities(),

    -- Workspace folders - explicitly set to container workspace
    workspaceFolders = {
      {
        uri = 'file://' .. path_utils.get_container_workspace(),
        name = 'devcontainer-workspace',
      },
    },

    -- On attach callback
    on_attach = function(client, bufnr)
      log.debug('LSP: ' .. name .. ' attached to buffer ' .. bufnr)

      -- Initialize path mappings for this client
      local path_utils = require('container.lsp.path')
      local local_workspace = path_utils.get_local_workspace()
      local container_workspace = path_utils.get_container_workspace()

      if not path_mappings_initialized then
        path_utils.setup(local_workspace, container_workspace)
        path_mappings_initialized = true
        log.debug('LSP: Initialized path mappings for %s', name)
      end

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
    config = M.config,
  }
end

-- Setup autocommand for automatic attachment to new buffers
function M._setup_auto_attach(server_name, server_config, client_id)
  local supported_filetypes = server_config.filetypes or server_config.languages or {}

  if #supported_filetypes == 0 then
    log.debug('No filetypes specified for %s, skipping auto-attach setup', server_name)
    return
  end

  -- Create autocmd group for this server
  local group_name = 'DevcontainerLSP_' .. server_name
  vim.api.nvim_create_augroup(group_name, { clear = true })

  -- Setup autocommand for each supported filetype
  for _, filetype in ipairs(supported_filetypes) do
    vim.api.nvim_create_autocmd({ 'BufEnter', 'BufNewFile' }, {
      group = group_name,
      pattern = '*',
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
              log.info('Auto-attached %s LSP to buffer %s (filetype: %s)', server_name, buf, ft)
            end
          else
            log.debug('LSP client %s is no longer active, skipping auto-attach', server_name)
          end
        end
      end,
    })
  end

  log.debug('Setup auto-attach for %s (filetypes: %s)', server_name, vim.inspect(supported_filetypes))
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
          log.info('Attached %s LSP to existing buffer %s (filetype: %s)', server_name, buf, ft)
        end
      end
    end
  end
end

-- Enhanced LSP error handling and recovery functions

-- Diagnose LSP server issues in container
function M.diagnose_lsp_server(server_name)
  local server_config = state.servers[server_name]
  if not server_config then
    return {
      available = false,
      error = 'Server not detected in container',
      suggestions = {
        'Check if the server is installed in the container',
        'Verify devcontainer.json includes necessary dependencies',
        'Run: docker exec ' .. (state.container_id or '<container>') .. ' which ' .. (server_name or '<server>'),
      },
    }
  end

  local docker = require('container.docker.init')
  local environment = require('container.environment')
  local config = require('container').get_state().current_config

  -- Check if server command exists
  local args = { 'exec' }
  local env_args = environment.build_lsp_args(config)
  for _, arg in ipairs(env_args) do
    table.insert(args, arg)
  end
  table.insert(args, state.container_id)
  table.insert(args, 'which')
  table.insert(args, server_config.cmd)

  local which_result = docker.run_docker_command(args)

  if not which_result.success then
    return {
      available = false,
      error = 'Server command not found in container PATH',
      details = {
        command = server_config.cmd,
        path_env = 'Check PATH environment variable in container',
        stderr = which_result.stderr,
      },
      suggestions = {
        'Install ' .. server_config.cmd .. ' in the container',
        'Add installation command to devcontainer.json postCreateCommand',
        'Check container PATH includes the server binary location',
        'Verify user permissions to execute the server command',
      },
    }
  end

  -- Check if server can start (test run)
  local test_args = { 'exec', '-i' }
  for _, arg in ipairs(env_args) do
    table.insert(test_args, arg)
  end
  table.insert(test_args, state.container_id)
  table.insert(test_args, server_config.cmd)
  table.insert(test_args, '--version') -- Most LSP servers support --version

  local version_result = docker.run_docker_command(test_args)

  if not version_result.success then
    return {
      available = true,
      error = 'Server found but cannot start',
      details = {
        command = server_config.cmd,
        path = server_config.path,
        exit_code = version_result.code,
        stderr = version_result.stderr,
        stdout = version_result.stdout,
      },
      suggestions = {
        'Check server dependencies are installed',
        'Verify server configuration is correct',
        'Check container environment variables',
        'Review container logs for additional errors',
      },
    }
  end

  return {
    available = true,
    working = true,
    details = {
      command = server_config.cmd,
      path = server_config.path,
      version_output = version_result.stdout,
    },
  }
end

-- Retry LSP server setup with enhanced diagnostics
function M.retry_lsp_server_setup(server_name, max_attempts)
  max_attempts = max_attempts or 3

  local function attempt_setup(attempt_num)
    log.info('LSP: Attempting to setup %s (attempt %d/%d)', server_name, attempt_num, max_attempts)

    -- First, diagnose the server
    local diagnosis = M.diagnose_lsp_server(server_name)

    if not diagnosis.available then
      log.error('LSP: Server %s is not available: %s', server_name, diagnosis.error)
      local notify = require('container.utils.notify')
      notify.error(
        'LSP Server Not Available: ' .. server_name,
        diagnosis.error .. '\n\nSuggestions:\n• ' .. table.concat(diagnosis.suggestions, '\n• ')
      )
      return false
    end

    if diagnosis.available and not diagnosis.working then
      log.error('LSP: Server %s found but not working: %s', server_name, diagnosis.error)
      local notify = require('container.utils.notify')
      notify.warn(
        'LSP Server Issues: ' .. server_name,
        diagnosis.error
          .. '\n\nDetails:\n'
          .. vim.inspect(diagnosis.details)
          .. '\n\nSuggestions:\n• '
          .. table.concat(diagnosis.suggestions, '\n• ')
      )
      return false
    end

    -- Server is available and working, attempt setup
    local server_config = state.servers[server_name]
    M.create_lsp_client(server_name, server_config)

    -- Wait a moment and check if client started successfully
    vim.defer_fn(function()
      local exists, client_id = M.client_exists(server_name)
      if exists then
        log.info('LSP: Successfully setup %s on attempt %d', server_name, attempt_num)
        local notify = require('container.utils.notify')
        notify.success('LSP Server Started', server_name .. ' is now ready')
      else
        if attempt_num < max_attempts then
          log.warn('LSP: Setup failed for %s, retrying in 2 seconds...', server_name)
          vim.defer_fn(function()
            attempt_setup(attempt_num + 1)
          end, 2000)
        else
          log.error('LSP: Failed to setup %s after %d attempts', server_name, max_attempts)
          local notify = require('container.utils.notify')
          notify.error(
            'LSP Setup Failed',
            'Could not start ' .. server_name .. ' after ' .. max_attempts .. ' attempts'
          )
        end
      end
    end, 1000)
  end

  attempt_setup(1)
end

-- Recover from LSP failures by restarting all servers
function M.recover_all_lsp_servers()
  log.info('LSP: Starting recovery process for all LSP servers')

  -- Stop all existing clients
  M.stop_all()

  -- Wait a moment for cleanup
  vim.defer_fn(function()
    -- Detect servers again
    local servers = M.detect_language_servers()

    -- Setup servers with retry logic
    for name, server in pairs(servers) do
      if server.available then
        M.retry_lsp_server_setup(name, 2)
      end
    end
  end, 1000)
end

-- Health check for LSP system
function M.health_check()
  local health = {
    container_connected = state.container_id ~= nil,
    lspconfig_available = pcall(require, 'lspconfig'),
    servers_detected = vim.tbl_count(state.servers),
    clients_active = vim.tbl_count(state.clients),
    issues = {},
  }

  if not health.container_connected then
    table.insert(health.issues, 'No container connected')
  end

  if not health.lspconfig_available then
    table.insert(health.issues, 'nvim-lspconfig not available')
  end

  if health.servers_detected == 0 then
    table.insert(health.issues, 'No LSP servers detected in container')
  end

  -- Check each active client
  for name, client_info in pairs(state.clients) do
    local client = vim.lsp.get_client_by_id(client_info.client_id)
    if not client or client.is_stopped then
      table.insert(health.issues, 'LSP client ' .. name .. ' is not running')
    end
  end

  return health
end

return M
