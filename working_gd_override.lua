-- Working GD Override Implementation
-- Successfully tested implementation for container_gopls definition jump
-- Based on /tmp/investigation_1-24.lua with improvements

local M = {}

-- Apply the working gd override for container_gopls
function M.apply_gd_override()
  print("\n=== APPLYING WORKING GD OVERRIDE ===")

  local bufnr = vim.api.nvim_get_current_buf()

  -- Override gd mapping with container-aware implementation
  vim.keymap.set('n', 'gd', function()
    print("[GD OVERRIDE] Custom gd handler called")

    local current_bufnr = vim.api.nvim_get_current_buf()

    -- Find container_gopls client
    local container_client = nil
    for _, client in ipairs(vim.lsp.get_clients({bufnr = current_bufnr})) do
      if client.name == 'container_gopls' then
        container_client = client
        break
      end
    end

    if not container_client then
      vim.notify("No container_gopls found", vim.log.levels.ERROR)
      return
    end

    -- Create position params with proper encoding
    -- Try different approach to avoid the warning
    local win = vim.api.nvim_get_current_win()
    local params = vim.lsp.util.make_position_params(win, container_client.offset_encoding or 'utf-16')

    -- Transform URI from host path to container path
    local transformed_params = vim.deepcopy(params)
    transformed_params.textDocument.uri = transformed_params.textDocument.uri:gsub(
      '^file://' .. vim.pesc(container_client.config.root_dir),
      'file:///workspace'
    )

    print("Requesting definition with URI:", transformed_params.textDocument.uri)

    -- Send request to container LSP
    container_client.request('textDocument/definition', transformed_params, function(err, result)
      if err then
        print("Error:", vim.inspect(err))
        vim.notify('Definition error: ' .. tostring(err.message or err), vim.log.levels.ERROR)
        return
      end

      if not result or vim.tbl_isempty(result) then
        vim.notify('No definition found', vim.log.levels.INFO)
        return
      end

      print("Got result:", vim.inspect(result))

      -- Handle first result (could be enhanced for multiple results)
      local location = result[1]
      if location and location.uri then
        -- Transform container path back to host path
        local host_uri = location.uri:gsub('^file:///workspace', 'file://' .. container_client.config.root_dir)
        local file_path = vim.uri_to_fname(host_uri)
        local current_file = vim.fn.expand('%:p')

        print("Target file:", file_path)
        print("Current file:", current_file)

        -- Smart handling: same file vs different file
        if file_path == current_file then
          -- Same file - only move cursor, don't reopen file
          print("Same file jump - moving cursor only")
          if location.range and location.range.start then
            local line = location.range.start.line + 1
            local col = location.range.start.character + 1
            print("Setting cursor to line", line, "col", col)
            vim.api.nvim_win_set_cursor(0, {line, col})
          end
        else
          -- Different file - open file and set cursor
          print("Different file jump - opening:", file_path)
          vim.cmd('edit ' .. vim.fn.fnameescape(file_path))

          -- Set cursor position after file is opened
          if location.range and location.range.start then
            vim.schedule(function()
              local line = location.range.start.line + 1
              local col = location.range.start.character + 1
              print("Setting cursor to line", line, "col", col)
              vim.api.nvim_win_set_cursor(0, {line, col})
            end)
          end
        end
      end
    end, current_bufnr)
  end, { buffer = bufnr, desc = "Go to definition (container aware)" })

  print("✅ Working gd mapping applied for buffer", bufnr)
end

-- Apply the override automatically when container_gopls is detected
function M.auto_apply_if_needed()
  local bufnr = vim.api.nvim_get_current_buf()
  local has_container_gopls = false

  for _, client in ipairs(vim.lsp.get_clients({bufnr = bufnr})) do
    if client.name == 'container_gopls' then
      has_container_gopls = true
      break
    end
  end

  if has_container_gopls then
    M.apply_gd_override()
    return true
  end

  return false
end

-- Manual application for testing
if not pcall(debug.getlocal, 4, 1) then
  -- Called directly, apply immediately
  M.apply_gd_override()
end

return M
