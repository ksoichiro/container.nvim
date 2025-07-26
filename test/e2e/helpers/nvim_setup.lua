-- Neovim environment setup for E2E tests running in headless mode
-- This module provides essential vim mocks and environment setup

local M = {}

-- Initialize minimal vim environment for headless mode
function M.setup_nvim_environment()
  -- Set E2E test environment flag
  vim.env = vim.env or {}
  vim.env.NVIM_E2E_TEST = '1'

  -- Set up basic vim globals and functions that the plugin expects
  vim = vim or {}
  vim.g = vim.g or {}
  vim.fn = vim.fn or {}
  vim.api = vim.api or {}
  vim.cmd = vim.cmd or function() end
  vim.notify = vim.notify or print
  vim.schedule = vim.schedule or function(fn)
    fn()
  end

  -- Mock essential vim.fn functions
  vim.fn.exists = vim.fn.exists or function()
    return 0
  end
  vim.fn.executable = vim.fn.executable or function()
    return 1
  end
  vim.fn.expand = vim.fn.expand or function(path)
    return path
  end
  vim.fn.fnamemodify = vim.fn.fnamemodify or function(path)
    return path
  end
  vim.fn.getcwd = vim.fn.getcwd or function()
    return '.'
  end
  vim.fn.system = vim.fn.system
    or function(cmd)
      -- Add timeout for E2E tests to prevent hanging
      local timeout_cmd = string.format('timeout 30s %s 2>&1', cmd)
      local handle = io.popen(timeout_cmd)
      local result = handle:read('*a')
      local success = handle:close()
      -- Set shell error based on timeout result
      vim.v.shell_error = success and 0 or 124 -- 124 is timeout exit code
      return result
    end
  vim.fn.shellescape = vim.fn.shellescape
    or function(str)
      -- Simple shell escaping for E2E tests
      return "'" .. str:gsub("'", "'\\''") .. "'"
    end

  -- Mock essential vim.api functions
  vim.api.nvim_create_user_command = vim.api.nvim_create_user_command or function() end
  vim.api.nvim_create_autocmd = vim.api.nvim_create_autocmd or function() end
  vim.api.nvim_exec_autocmds = vim.api.nvim_exec_autocmds or function() end

  -- Set up package path for plugin loading
  package.path = './test/helpers/?.lua;./lua/?.lua;./lua/?/init.lua;' .. package.path
end

return M
