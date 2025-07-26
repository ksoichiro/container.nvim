-- ftplugin_manager.lua
-- Generic ftplugin logic for preventing host LSP conflicts with container LSP

local M = {}
local log = require('container.utils.log')
local language_registry = require('container.lsp.language_registry')

-- Active monitors by buffer
local active_monitors = {}

-- Check if container LSP is active for this project
local function is_container_lsp_active()
  local container = require('container')
  local state = container.get_state()
  return state.current_container and state.container_status == 'running'
end

-- Check if container LSP client is running for a specific language
local function has_container_lsp_client(container_client_name)
  local clients = vim.lsp.get_clients and vim.lsp.get_clients() or vim.lsp.get_active_clients()
  for _, client in ipairs(clients) do
    if client.name == container_client_name and not client.is_stopped() then
      return true
    end
  end
  return false
end

-- Stop host LSP clients for a specific language
local function stop_host_lsp_clients(host_client_name)
  local clients = vim.lsp.get_clients and vim.lsp.get_clients() or vim.lsp.get_active_clients()
  for _, client in ipairs(clients) do
    if client.name == host_client_name then
      log.info(
        'ftplugin: Stopping host %s (ID: %d) to prevent conflicts with container LSP',
        host_client_name,
        client.id
      )
      client.stop()
    end
  end
end

-- Set language-specific disable flags
local function set_language_disable_flags(filetype, lang_config)
  if filetype == 'go' then
    vim.b.disable_gopls = true
    vim.g.go_gopls_enabled = false
  elseif filetype == 'python' then
    vim.b.disable_pylsp = true
    vim.b.disable_pyright = true
  elseif filetype == 'typescript' or filetype == 'javascript' then
    vim.b.disable_tsserver = true
  elseif filetype == 'rust' then
    vim.b.disable_rust_analyzer = true
  elseif filetype == 'c' or filetype == 'cpp' then
    vim.b.disable_clangd = true
  elseif filetype == 'lua' then
    vim.b.disable_lua_ls = true
  end
end

-- Restore language-specific disable flags
local function restore_language_disable_flags(filetype)
  if filetype == 'go' then
    vim.b.disable_gopls = false
    if vim.g.go_gopls_enabled ~= nil then
      vim.g.go_gopls_enabled = true
    end
  elseif filetype == 'python' then
    vim.b.disable_pylsp = false
    vim.b.disable_pyright = false
  elseif filetype == 'typescript' or filetype == 'javascript' then
    vim.b.disable_tsserver = false
  elseif filetype == 'rust' then
    vim.b.disable_rust_analyzer = false
  elseif filetype == 'c' or filetype == 'cpp' then
    vim.b.disable_clangd = false
  elseif filetype == 'lua' then
    vim.b.disable_lua_ls = false
  end
end

-- Override lspconfig setup for a server
local function override_lspconfig_setup(server_name)
  local ok, lspconfig = pcall(require, 'lspconfig')
  if ok and lspconfig[server_name] then
    -- Temporarily disable auto-start for this buffer
    local original_autostart = lspconfig[server_name].autostart
    lspconfig[server_name].autostart = false

    -- Restore after a short delay (other plugins may have already triggered)
    vim.defer_fn(function()
      if original_autostart ~= nil then
        lspconfig[server_name].autostart = original_autostart
      end
    end, 1000)
  end
end

-- Setup LSP conflict prevention for a specific filetype
function M.setup_for_filetype(filetype)
  local lang_config = language_registry.get_by_filetype(filetype)
  if not lang_config then
    log.debug('ftplugin: No language configuration found for filetype: %s', filetype)
    return
  end

  local buffer = vim.api.nvim_get_current_buf()

  -- Skip if already setup for this buffer
  if active_monitors[buffer] then
    return
  end

  if not is_container_lsp_active() then
    log.debug('ftplugin: Container LSP not active for %s, allowing normal behavior', filetype)
    return
  end

  log.debug('ftplugin: Container LSP is active for %s, preventing host LSP interference', filetype)

  -- Stop any existing host LSP clients
  stop_host_lsp_clients(lang_config.host_client_name)

  -- Set language-specific disable flags
  set_language_disable_flags(filetype, lang_config)

  -- Override lspconfig setup
  override_lspconfig_setup(lang_config.server_name)

  -- Monitor for unwanted host LSP clients and stop them
  local monitor_timer = vim.uv.new_timer()
  monitor_timer:start(
    1000,
    2000,
    vim.schedule_wrap(function()
      if has_container_lsp_client(lang_config.container_client_name) then
        stop_host_lsp_clients(lang_config.host_client_name)
      else
        -- If container LSP client is gone, allow host LSP again
        monitor_timer:stop()
        monitor_timer:close()
        active_monitors[buffer] = nil
        restore_language_disable_flags(filetype)
        log.debug(
          'ftplugin: Container LSP client %s is gone, re-enabling host %s',
          lang_config.container_client_name,
          lang_config.host_client_name
        )
      end
    end)
  )

  -- Store monitor reference
  active_monitors[buffer] = monitor_timer

  -- Clean up timer when buffer is unloaded
  vim.api.nvim_create_autocmd('BufUnload', {
    buffer = buffer,
    callback = function()
      if active_monitors[buffer] then
        active_monitors[buffer]:stop()
        active_monitors[buffer]:close()
        active_monitors[buffer] = nil
      end
    end,
  })

  log.debug('ftplugin: LSP conflict prevention setup completed for %s (buffer %d)', filetype, buffer)
end

-- Setup autocmds for all supported filetypes
function M.setup_autocmds()
  local supported_languages = language_registry.get_supported_languages()
  local filetypes = {}

  -- Collect all filetypes from language registry
  for _, lang in ipairs(supported_languages) do
    local config = language_registry.language_mappings[lang]
    if config and config.filetype then
      table.insert(filetypes, config.filetype)
    end
  end

  -- Create autocmd for all supported filetypes
  vim.api.nvim_create_autocmd('FileType', {
    pattern = filetypes,
    callback = function(args)
      local filetype = args.match
      -- Use vim.schedule to ensure this runs after other ftplugin logic
      vim.schedule(function()
        M.setup_for_filetype(filetype)
      end)
    end,
    desc = 'container.nvim: Setup LSP conflict prevention',
  })

  log.debug('ftplugin: Autocmds setup for filetypes: %s', table.concat(filetypes, ', '))
end

-- Cleanup all monitors
function M.cleanup()
  for buffer, monitor in pairs(active_monitors) do
    if monitor then
      monitor:stop()
      monitor:close()
    end
  end
  active_monitors = {}
end

return M
