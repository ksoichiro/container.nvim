-- ftplugin/go.lua
-- Prevent host gopls from starting when container_gopls is available

local log = require('container.utils.log')

-- Check if container LSP is active for this project
local function is_container_lsp_active()
  local container = require('container')
  local state = container.get_state()
  return state.current_container and state.container_status == 'running'
end

-- Check if container_gopls is already running
local function has_container_gopls()
  local clients = vim.lsp.get_clients and vim.lsp.get_clients() or vim.lsp.get_active_clients()
  for _, client in ipairs(clients) do
    if client.name == 'container_gopls' and not client.is_stopped() then
      return true
    end
  end
  return false
end

-- Stop any host gopls clients
local function stop_host_gopls()
  local clients = vim.lsp.get_clients and vim.lsp.get_clients() or vim.lsp.get_active_clients()
  for _, client in ipairs(clients) do
    if client.name == 'gopls' then
      log.info('Go ftplugin: Stopping host gopls (ID: %d) to prevent conflicts with container_gopls', client.id)
      client.stop()
    end
  end
end

-- Main logic
if is_container_lsp_active() then
  log.debug('Go ftplugin: Container LSP is active, preventing host gopls interference')

  -- Stop any existing host gopls
  stop_host_gopls()

  -- Set a flag to prevent automatic gopls startup from other plugins
  vim.b.disable_gopls = true
  vim.g.go_gopls_enabled = false

  -- Override lspconfig gopls setup if it exists
  local ok, lspconfig = pcall(require, 'lspconfig')
  if ok and lspconfig.gopls then
    -- Temporarily disable gopls auto-start for this buffer
    local original_autostart = lspconfig.gopls.autostart
    lspconfig.gopls.autostart = false

    -- Restore after a short delay (other plugins may have already triggered)
    vim.defer_fn(function()
      if original_autostart ~= nil then
        lspconfig.gopls.autostart = original_autostart
      end
    end, 1000)
  end

  -- Monitor for unwanted gopls clients and stop them
  local monitor_timer = vim.uv.new_timer()
  monitor_timer:start(1000, 2000, vim.schedule_wrap(function()
    if has_container_gopls() then
      stop_host_gopls()
    else
      -- If container_gopls is gone, allow host gopls again
      monitor_timer:stop()
      monitor_timer:close()
      vim.b.disable_gopls = false
      if vim.g.go_gopls_enabled ~= nil then
        vim.g.go_gopls_enabled = true
      end
      log.debug('Go ftplugin: Container_gopls is gone, re-enabling host gopls')
    end
  end))

  -- Clean up timer when buffer is unloaded
  vim.api.nvim_create_autocmd('BufUnload', {
    buffer = 0,
    callback = function()
      if monitor_timer then
        monitor_timer:stop()
        monitor_timer:close()
      end
    end,
  })

else
  log.debug('Go ftplugin: Container LSP not active, allowing normal gopls behavior')
end
