-- Minimal Neovim initialization for tests
-- This provides only the essential APIs needed for integration tests
-- without loading any user configuration

-- Set up package paths
package.path = './test/helpers/?.lua;./lua/?.lua;./lua/?/init.lua;' .. package.path

-- Essential vim APIs that may be missing in --headless -u NONE
if not vim.inspect then
  vim.inspect = function(obj)
    if type(obj) == 'table' then
      local parts = {}
      for k, v in pairs(obj) do
        table.insert(parts, tostring(k) .. '=' .. tostring(v))
      end
      return '{' .. table.concat(parts, ', ') .. '}'
    else
      return tostring(obj)
    end
  end
end

if not vim.defer_fn then
  vim.defer_fn = function(fn, timeout)
    -- Immediate execution for tests
    if type(fn) == 'function' then
      fn()
    end
  end
end

-- Add minimal JSON support if not available
if not vim.json then
  vim.json = {
    decode = function(str)
      -- Very basic JSON decode for test purposes
      if str == '{}' then
        return {}
      end
      if str == '[]' then
        return {}
      end
      return {}
    end,
    encode = function(obj)
      return '{}'
    end,
  }
end

-- Ensure runtimepath includes current directory
vim.opt.runtimepath:prepend('.')

-- Disable swap files and other file operations that might interfere
vim.opt.swapfile = false
vim.opt.backup = false
vim.opt.writebackup = false

-- Set up basic autocmd support
if not vim.api.nvim_create_augroup then
  vim.api.nvim_create_augroup = function(name, opts)
    return 1
  end
end

if not vim.api.nvim_create_autocmd then
  vim.api.nvim_create_autocmd = function(event, opts)
    return 1
  end
end
