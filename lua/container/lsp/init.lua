local M = {}
local log = require('container.utils.log')
-- local async = require('container.utils.async')  -- Reserved for future use

-- Compatibility helper for LSP client API changes
local function get_lsp_clients(opts)
  -- Use new API if available (Neovim 0.10+)
  if vim.lsp.get_clients then
    return vim.lsp.get_clients(opts)
  else
    -- Fall back to deprecated API for older versions
    return vim.lsp.get_active_clients(opts)
  end
end

-- Compatibility helper for starting LSP clients
local function start_lsp_client(config)
  -- Use new API if available (Neovim 0.12+)
  if vim.lsp.start then
    return vim.lsp.start(config)
  else
    -- Fall back to deprecated API for older versions
    return vim.lsp.start_client(config)
  end
end

-- State management
local state = {
  servers = {},
  clients = {},
  port_mappings = {},
  container_id = nil,
}

-- Track if path mappings have been initialized
local path_mappings_initialized = false

-- Track auto-initialization status per container to prevent duplicates
local container_init_status = {} -- { [container_id] = "in_progress" | "completed" }

-- Initialize LSP module
function M.setup(config)
  log.debug('LSP: Initializing LSP module')
  M.config = vim.tbl_deep_extend('force', {
    auto_setup = true,
    timeout = 5000,
    servers = {},
  }, config or {})

  -- Setup automatic LSP initialization when Go files are opened
  if M.config.auto_setup then
    M._setup_auto_initialization()
  end

  -- Initialize LSP commands module
  local commands_ok, commands = pcall(require, 'container.lsp.commands')
  if commands_ok then
    commands.setup({
      host_workspace = vim.fn.getcwd(),
      container_workspace = '/workspace',
    })
    commands.setup_commands()
    log.debug('LSP: Commands module initialized')
  else
    log.debug('LSP: Commands module not available: %s', commands)
  end
end

-- Setup automatic LSP initialization
function M._setup_auto_initialization()
  local auto_group = vim.api.nvim_create_augroup('ContainerLspAutoSetup', { clear = true })

  -- Strategy: Listen for container detection, then check for Go buffers
  -- This solves the timing issue where BufEnter fires before container detection

  -- Helper function to check and setup LSP for Go buffers
  local function check_go_buffers_and_setup(container_id)
    log.debug('LSP: Checking Go buffers for container %s', container_id)

    -- Prevent duplicate initialization for this container
    if container_init_status[container_id] == 'in_progress' then
      log.debug('LSP: Auto-initialization already in progress for container %s', container_id)
      return
    end

    if container_init_status[container_id] == 'completed' then
      log.debug('LSP: Auto-initialization already completed for container %s', container_id)
      return
    end

    -- Check if container_gopls is already running and functional
    local existing_container_gopls = get_lsp_clients({ name = 'container_gopls' })
    local functional_gopls = nil
    for _, client in ipairs(existing_container_gopls) do
      if not client.is_stopped() and client.initialized then
        functional_gopls = client
        break
      end
    end

    if functional_gopls then
      log.debug('LSP: Functional container_gopls already exists (ID: %d), skipping setup', functional_gopls.id)
      container_init_status[container_id] = 'completed'
      return
    end

    -- Clean up ALL existing container_gopls clients to ensure clean state
    local container_client_name = 'container_gopls'
    local existing_clients = get_lsp_clients({ name = container_client_name })

    if #existing_clients > 0 then
      log.info(
        'LSP: Found %d existing container_gopls client(s), stopping all for clean initialization',
        #existing_clients
      )

      -- Stop ALL existing container_gopls clients
      for _, client in ipairs(existing_clients) do
        log.info('LSP: Stopping existing container_gopls (id: %d)', client.id)
        client.stop()

        -- Detach from all buffers
        for _, buf in ipairs(vim.api.nvim_list_bufs()) do
          if vim.api.nvim_buf_is_loaded(buf) then
            local buf_clients = get_lsp_clients({ bufnr = buf })
            for _, buf_client in ipairs(buf_clients) do
              if buf_client.id == client.id then
                vim.lsp.buf_detach_client(buf, client.id)
                log.debug('LSP: Detached container_gopls from buffer %d', buf)
              end
            end
          end
        end
      end

      -- Wait a moment for cleanup to complete
      vim.defer_fn(function()
        log.info('LSP: Container_gopls cleanup complete, proceeding with new initialization')
      end, 100)
    end

    -- Mark initialization as in progress for this container
    container_init_status[container_id] = 'in_progress'

    -- Stop any existing host gopls clients to avoid conflicts
    local host_gopls_clients = get_lsp_clients({ name = 'gopls' })
    for _, client in ipairs(host_gopls_clients) do
      log.info('LSP: Stopping host gopls client (id: %d) to avoid conflicts', client.id)
      client.stop()

      -- Also detach from all buffers to prevent automatic restart
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(buf) then
          local buf_clients = get_lsp_clients({ bufnr = buf })
          for _, buf_client in ipairs(buf_clients) do
            if buf_client.id == client.id then
              vim.lsp.buf_detach_client(buf, client.id)
              log.debug('LSP: Detached host gopls from buffer %d', buf)
            end
          end
        end
      end
    end

    -- Small delay to ensure host gopls is fully stopped
    vim.defer_fn(function()
      -- Check if any host gopls clients are still running and force stop them
      local remaining_host_clients = get_lsp_clients({ name = 'gopls' })
      if #remaining_host_clients > 0 then
        log.warn('LSP: %d host gopls client(s) still running, force stopping...', #remaining_host_clients)
        for _, client in ipairs(remaining_host_clients) do
          if not client.is_stopped then
            client.stop(true) -- Force stop
            log.info('LSP: Force stopped host gopls client (id: %d)', client.id)
          end
        end
      end
    end, 200)

    -- Look for loaded Go buffers
    local go_buffers = {}
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_loaded(buf) then
        local filetype = vim.bo[buf].filetype
        local filename = vim.api.nvim_buf_get_name(buf)
        if filetype == 'go' or (filename and filename:match('%.go$')) then
          table.insert(go_buffers, buf)
        end
      end
    end

    if #go_buffers > 0 then
      log.info('LSP: Found %d Go buffer(s), auto-initializing container_gopls for %s', #go_buffers, container_id)
      M.set_container_id(container_id)
      M.setup_lsp_in_container()

      -- Mark setup as completed for this container (with delay to ensure setup is done)
      vim.defer_fn(function()
        container_init_status[container_id] = 'completed'
        log.debug('LSP: Auto-initialization completed for container %s', container_id)
      end, 2000)
    else
      log.debug('LSP: No Go buffers found, skipping LSP setup for container %s', container_id)
      container_init_status[container_id] = nil -- Clear status since no setup needed
    end
  end

  -- Listen for container state changes using User events
  vim.api.nvim_create_autocmd('User', {
    pattern = 'ContainerDetected',
    group = auto_group,
    callback = function(args)
      local container_id = args.data and args.data.container_id
      if container_id then
        log.debug('LSP: Container detected: %s', container_id)
        vim.defer_fn(function()
          check_go_buffers_and_setup(container_id)
        end, 100)
      end
    end,
  })

  -- Also listen for manual container operations
  vim.api.nvim_create_autocmd('User', {
    pattern = { 'ContainerStarted', 'ContainerOpened' },
    group = auto_group,
    callback = function(args)
      local container_id = args.data and args.data.container_id
      if container_id then
        log.debug('LSP: Container operation completed: %s', container_id)
        vim.defer_fn(function()
          check_go_buffers_and_setup(container_id)
        end, 500) -- Longer delay for container operations
      end
    end,
  })

  -- Fallback: Still handle FileType events for cases where container is already detected
  vim.api.nvim_create_autocmd({ 'BufEnter', 'FileType' }, {
    pattern = { '*.go', 'go' },
    group = auto_group,
    callback = function(args)
      -- Only proceed for Go files
      local filetype = vim.bo[args.buf].filetype
      if filetype ~= 'go' then
        return
      end

      -- Small delay to allow container detection to complete if in progress
      vim.defer_fn(function()
        local container = require('container')
        local state = container.get_state()

        if state.current_container then
          log.debug('LSP: FileType fallback triggered for container %s', state.current_container)
          check_go_buffers_and_setup(state.current_container)
        else
          log.debug('LSP: FileType fallback - no container available yet')
        end
      end, 1000) -- 1 second delay to allow container detection
    end,
  })

  log.debug('LSP: Auto-initialization setup complete (event-driven approach)')
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
  local container_client_name = 'container_' .. server_name

  -- Check active clients first
  local active_clients = get_lsp_clients({ name = container_client_name })
  if #active_clients > 0 then
    log.debug('LSP: Found existing active client for %s', container_client_name)
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
  if not M.config or not M.config.auto_setup then
    log.debug('LSP: Auto-setup disabled or module not initialized')
    return
  end

  local servers = M.detect_language_servers()
  local setup_count = 0
  local skipped_count = 0

  for name, server in pairs(servers) do
    if server.available then
      -- Check if client already exists and clean up duplicates
      local container_client_name = 'container_' .. name
      local existing_clients = get_lsp_clients({ name = container_client_name })

      if #existing_clients > 0 then
        log.info('LSP: Found %d existing %s client(s)', #existing_clients, container_client_name)

        -- Stop all but the first client to avoid duplicates
        for i = 2, #existing_clients do
          log.info('LSP: Stopping duplicate %s client (ID: %s)', container_client_name, existing_clients[i].id)
          existing_clients[i].stop()
        end

        local client = existing_clients[1]
        log.info('LSP: Using existing %s client (ID: %s)', container_client_name, client.id)
        skipped_count = skipped_count + 1

        -- Update our state
        state.clients[name] = {
          client_id = client.id,
          config = nil,
          server_config = server,
        }

        -- Ensure client is attached to current Go buffers
        M._attach_to_existing_buffers(name, server, client.id)
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

  -- Initialize strategy selector if not already done
  if not M._strategy_selector_initialized then
    local strategy = require('container.lsp.strategy')
    strategy.setup()
    M._strategy_selector_initialized = true
  end

  -- Select the best strategy for this server
  local strategy = require('container.lsp.strategy')
  local chosen_strategy, strategy_config = strategy.select_strategy(name, state.container_id, server_config)

  log.info('LSP: Selected %s strategy for %s', chosen_strategy, name)

  -- Prepare base LSP configuration
  local base_lsp_config = M._prepare_lsp_config(name, server_config)

  -- Create client using the selected strategy
  local lsp_config, strategy_error = strategy.create_client_with_strategy(
    chosen_strategy,
    name,
    state.container_id,
    server_config, -- Pass server_config directly
    strategy_config
  )

  -- If strategy didn't provide certain required fields, use base config as fallback
  if lsp_config then
    -- Only add base config fields that are missing in strategy config
    -- Skip callbacks that strategy might have defined
    local skip_fields = { 'before_init', 'on_init', 'on_attach', 'on_exit', 'handlers' }
    for key, value in pairs(base_lsp_config) do
      if lsp_config[key] == nil and not vim.tbl_contains(skip_fields, key) then
        lsp_config[key] = value
      end
    end
  end

  if not lsp_config then
    print('ERROR: Failed to create client with ' .. chosen_strategy .. ' strategy: ' .. tostring(strategy_error))
    log.error('LSP: Failed to create client with %s strategy: %s', chosen_strategy, strategy_error)
    return
  end

  log.debug('LSP: Starting client with %s strategy using start_lsp_client', chosen_strategy)

  -- Debug: Check if before_init exists
  if lsp_config.before_init then
    log.info('LSP: before_init is defined in lsp_config for %s', name)
  else
    log.error('LSP: before_init is NOT defined in lsp_config for %s!', name)
    -- Add a fallback before_init for debugging
    lsp_config.before_init = function(params, config)
      log.error('LSP: Fallback before_init called for %s - this should not happen!', name)
    end
  end

  -- Start client directly using compatibility helper
  log.info('LSP: About to start LSP client for %s with command: %s', name, table.concat(lsp_config.cmd or {}, ' '))
  local client_id = start_lsp_client(lsp_config)

  if not client_id then
    log.error('LSP: Failed to start client for %s - start_lsp_client returned nil', name)
    log.error('LSP: This usually means the command failed to execute or was invalid')
    log.error('LSP: Command was: %s', table.concat(lsp_config.cmd or {}, ' '))
    return
  end

  log.info('LSP: Started client for %s with ID %s using %s strategy', name, client_id, chosen_strategy)

  -- Verify client is actually running
  vim.defer_fn(function()
    local client = vim.lsp.get_client_by_id(client_id)
    if not client then
      log.error('LSP: Client %s (ID: %d) not found after creation - it may have exited immediately', name, client_id)
    elseif client.is_stopped() then
      log.error('LSP: Client %s (ID: %d) is already stopped after creation', name, client_id)
    else
      log.info('LSP: Client %s (ID: %d) is running successfully', name, client_id)
    end
  end, 1000)

  -- Get the client immediately to set up strategy-specific features
  local client = vim.lsp.get_client_by_id(client_id)
  if not client then
    log.error('LSP: Failed to get client immediately after creation')
    return
  end

  -- Add container metadata
  client.config.container_id = state.container_id
  client.config.container_managed = true

  -- Setup strategy-specific path transformation
  strategy.setup_path_transformation(client, name, state.container_id)
  log.info('LSP: Strategy-specific setup completed for %s', name)

  -- Update state with actual client ID
  state.clients[name] = {
    client_id = client_id,
    config = lsp_config,
    server_config = server_config,
  }

  -- Delay buffer attachment to ensure path transformation is fully set up
  vim.defer_fn(function()
    -- Verify client and transformation are ready
    local client = vim.lsp.get_client_by_id(client_id)
    if not client then
      log.error('LSP: Client %s (ID: %d) not found for buffer attachment', name, client_id)
      return
    end

    log.debug('LSP: Proceeding with buffer attachment for %s', name)

    -- Attach to current buffer and existing Go buffers
    local bufnr = vim.api.nvim_get_current_buf()
    local ft = vim.api.nvim_buf_get_option(bufnr, 'filetype')

    -- Check if this filetype should trigger the LSP
    local supported_filetypes = server_config.filetypes or server_config.languages or {}
    local should_attach = vim.tbl_contains(supported_filetypes, ft)

    if should_attach then
      vim.lsp.buf_attach_client(bufnr, client_id)
      log.info('LSP: Attached %s to current buffer %s', name, bufnr)
    end

    -- Setup autocommand for automatic attachment to new buffers
    M._setup_auto_attach(name, server_config, client_id)

    -- Attach to existing loaded buffers with matching filetypes
    M._attach_to_existing_buffers(name, server_config, client_id)

    -- Setup LSP commands keybindings for Go files if this is gopls
    if name == 'gopls' then
      M._setup_gopls_commands(client_id)
    end
  end, 100) -- 100ms delay ensures transformation setup completes

  log.info('LSP: Successfully started %s client directly', name)
end

-- Prepare LSP configuration for a server
function M._prepare_lsp_config(name, server_config)
  local path_utils = require('container.lsp.path')

  local config = vim.tbl_deep_extend('force', {
    -- Base configuration - use unique name for container-based LSP
    name = 'container_' .. name,
    filetypes = server_config.languages,

    -- Command will be overridden by forwarding module
    cmd = { 'echo', 'LSP server not properly configured' },

    -- Root directory pattern - Strategy A: use host paths (unified via symlinks)
    root_dir = function(fname)
      local util = require('lspconfig.util')
      -- Strategy A: For Go, find go.mod first, then fall back to git root
      if name == 'gopls' then
        -- Look for go.mod in current and parent directories
        local go_root = util.root_pattern('go.mod', 'go.work')(fname)
        if go_root then
          log.debug('LSP: Found Go root at %s for %s', go_root, fname)
          return go_root
        end
      end
      -- Fallback: Use git root or file directory
      return util.find_git_ancestor(fname) or util.path.dirname(fname)
    end,

    -- Capabilities - enable workspace configuration
    capabilities = vim.tbl_deep_extend('force', vim.lsp.protocol.make_client_capabilities(), {
      workspace = {
        configuration = true,
        didChangeConfiguration = {
          dynamicRegistration = true,
        },
      },
    }),

    -- Initial workspace folders - Strategy A: use host workspace path
    workspace_folders = {
      {
        uri = 'file://' .. vim.fn.getcwd(),
        name = 'workspace',
      },
    },

    -- Before init callback - Strategy A: use host paths (unified via symlinks)
    before_init = function(initialize_params, config)
      log.debug('LSP: before_init called for ' .. name)

      -- Strategy A: Use the current file to determine correct workspace root
      local current_file = vim.fn.expand('%:p')
      local workspace_root = vim.fn.getcwd()

      -- For gopls, try to find the go.mod root if available
      if name == 'gopls' and current_file ~= '' then
        local util = require('lspconfig.util')
        local go_root = util.root_pattern('go.mod', 'go.work')(current_file)
        if go_root then
          workspace_root = go_root
          log.debug('LSP: Using Go project root: %s', workspace_root)
        end
      end

      if initialize_params.workspaceFolders then
        for i, folder in ipairs(initialize_params.workspaceFolders) do
          folder.uri = 'file://' .. workspace_root
          folder.name = 'workspace'
          log.debug('LSP: Set workspace folder %d to %s', i, folder.uri)
        end
      end

      -- Set root paths to determined workspace root
      initialize_params.rootUri = 'file://' .. workspace_root
      initialize_params.rootPath = workspace_root

      log.debug('LSP: Initialize params set to workspace root: %s (Strategy A)', workspace_root)
    end,

    -- On init callback - called after initialize response
    on_init = function(client, initialize_result)
      log.debug('LSP: on_init called for ' .. name)

      -- Strategy A: Set workspace folders to determined project root
      local current_file = vim.fn.expand('%:p')
      local workspace_root = vim.fn.getcwd()

      -- For gopls, use Go project root if available
      if name == 'gopls' and current_file ~= '' then
        local util = require('lspconfig.util')
        local go_root = util.root_pattern('go.mod', 'go.work')(current_file)
        if go_root then
          workspace_root = go_root
        end
      end

      if client.workspace_folders then
        client.workspace_folders = {
          {
            uri = 'file://' .. workspace_root,
            name = 'workspace',
          },
        }
        log.debug('LSP: Set client.workspace_folders to project root: %s (Strategy A)', workspace_root)
      end

      -- Send workspace/didChangeConfiguration if supported
      if client.server_capabilities.workspace and client.server_capabilities.workspace.didChangeConfiguration then
        client.notify('workspace/didChangeConfiguration', { settings = {} })
        log.debug('LSP: Sent workspace/didChangeConfiguration')
      end

      if M.config.on_init then
        return M.config.on_init(client, initialize_result)
      end
    end,

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

      -- Setup path transformation for this client
      client.config.container_id = state.container_id
      client.config.container_managed = true
      local transform = require('container.lsp.transform')
      transform.setup_path_transformation(client)

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

  -- Clear container initialization status
  container_init_status = {}
  log.debug('LSP: Cleared all container initialization status')
end

-- Stop a specific LSP client
function M.stop_client(name)
  local client_info = state.clients[name]
  if not client_info then
    return
  end

  -- Stop any active LSP clients using container client name
  local container_client_name = 'container_' .. name
  local clients = get_lsp_clients({ name = container_client_name })
  for _, client in ipairs(clients) do
    client.stop()
  end

  state.clients[name] = nil
  log.info('LSP: Stopped ' .. container_client_name)
end

-- Clear initialization status for a specific container
function M.clear_container_init_status(container_id)
  if container_init_status[container_id] then
    container_init_status[container_id] = nil
    log.debug('LSP: Cleared initialization status for container %s', container_id)
  end
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
            local attached_clients = get_lsp_clients({ bufnr = buf })
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
        local attached_clients = get_lsp_clients({ bufnr = buf })
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

-- Setup gopls-specific commands and keybindings
function M._setup_gopls_commands(client_id)
  local commands_ok, commands = pcall(require, 'container.lsp.commands')
  if not commands_ok then
    log.debug('LSP: Commands module not available for gopls setup')
    return
  end

  -- Setup keybindings for Go buffers
  local group_name = 'ContainerGoplsCommands'
  vim.api.nvim_create_augroup(group_name, { clear = true })

  vim.api.nvim_create_autocmd({ 'BufEnter', 'FileType' }, {
    group = group_name,
    pattern = { '*.go', 'go' },
    callback = function(args)
      local bufnr = args.buf
      local ft = vim.bo[bufnr].filetype

      if ft == 'go' then
        -- Check if this buffer has container_gopls attached
        local buf_clients = get_lsp_clients({ bufnr = bufnr })
        local has_container_gopls = false

        for _, client in ipairs(buf_clients) do
          if client.name == 'container_gopls' then
            has_container_gopls = true
            break
          end
        end

        if has_container_gopls then
          -- Setup keybindings for this buffer with delay to ensure LSP is ready
          vim.defer_fn(function()
            local success = commands.setup_keybindings({
              buffer = bufnr,
              server_name = 'gopls',
              keybindings = M.config.keybindings or {
                hover = 'K',
                definition = 'gd',
                references = 'gr',
              },
            })

            if success then
              log.info('LSP: Successfully setup gopls keybindings for buffer %d', bufnr)
            else
              log.warn('LSP: Failed to setup gopls keybindings for buffer %d', bufnr)
            end
          end, 200)

          log.debug('LSP: Scheduled gopls commands setup for buffer %d', bufnr)
        end
      end
    end,
  })

  -- Also setup on LSP attach events
  vim.api.nvim_create_autocmd('LspAttach', {
    group = group_name,
    callback = function(args)
      local bufnr = args.buf
      local client = vim.lsp.get_client_by_id(args.data.client_id)

      if client and client.name == 'container_gopls' then
        local ft = vim.bo[bufnr].filetype
        if ft == 'go' then
          log.info('LSP: container_gopls attached to buffer %d, setting up keybindings', bufnr)

          -- Setup keybindings immediately since LSP is now attached
          local success = commands.setup_keybindings({
            buffer = bufnr,
            server_name = 'gopls',
            keybindings = M.config.keybindings or {
              hover = 'K',
              definition = 'gd',
              references = 'gr',
            },
          })

          if success then
            log.info('LSP: Successfully setup keybindings on attach for buffer %d', bufnr)
          else
            log.warn('LSP: Failed to setup keybindings on attach for buffer %d', bufnr)
          end
        end
      end
    end,
  })

  log.info('LSP: Setup gopls commands autocommand and attach handler')
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
    servers_detected = vim.tbl_count(state.servers),
    clients_active = vim.tbl_count(state.clients),
    issues = {},
  }

  if not health.container_connected then
    table.insert(health.issues, 'No container connected')
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

-- Get detailed debugging information about LSP clients
function M.get_debug_info()
  local debug_info = {
    config = M.config,
    state = state,
    container_id = state.container_id,
    active_clients = {},
    current_buffer_clients = {},
  }

  -- Get all active LSP clients
  local clients = get_lsp_clients()
  for _, client in ipairs(clients) do
    local client_info = {
      id = client.id,
      name = client.name,
      root_dir = client.config.root_dir,
      cmd = client.config.cmd,
      container_managed = client.config.container_managed,
      is_stopped = client.is_stopped(),
      initialized = client.initialized,
      attached_buffers = client.attached_buffers and vim.tbl_keys(client.attached_buffers) or {},
      server_capabilities = client.server_capabilities and vim.tbl_keys(client.server_capabilities) or {},
    }
    table.insert(debug_info.active_clients, client_info)
  end

  -- Get clients attached to current buffer
  local bufnr = vim.api.nvim_get_current_buf()
  local buf_clients = get_lsp_clients({ bufnr = bufnr })
  for _, client in ipairs(buf_clients) do
    table.insert(debug_info.current_buffer_clients, {
      id = client.id,
      name = client.name,
      initialized = client.initialized,
    })
  end

  return debug_info
end

-- Detailed LSP client analysis for specific client
function M.analyze_client(client_name)
  local clients = get_lsp_clients({ name = client_name })
  if #clients == 0 then
    return { error = 'No client found with name: ' .. client_name }
  end

  local client = clients[1]
  local analysis = {
    basic_info = {
      id = client.id,
      name = client.name,
      is_stopped = client.is_stopped(),
      initialized = client.initialized,
    },
    config = {
      cmd = client.config.cmd,
      root_dir = client.config.root_dir,
      capabilities = client.config.capabilities and vim.tbl_keys(client.config.capabilities) or {},
      settings = client.config.settings,
      init_options = client.config.init_options,
    },
    server_info = {
      server_capabilities = client.server_capabilities,
      workspace_folders = client.workspace_folders,
    },
    buffer_attachment = {},
  }

  -- Check buffer attachments
  local bufnr = vim.api.nvim_get_current_buf()
  local buf_clients = get_lsp_clients({ bufnr = bufnr })
  local attached_to_current = false
  for _, buf_client in ipairs(buf_clients) do
    if buf_client.id == client.id then
      attached_to_current = true
      break
    end
  end

  analysis.buffer_attachment = {
    attached_to_current_buffer = attached_to_current,
    current_buffer = bufnr,
    current_buffer_name = vim.api.nvim_buf_get_name(bufnr),
    attached_buffers = client.attached_buffers and vim.tbl_keys(client.attached_buffers) or {},
  }

  return analysis
end

return M
