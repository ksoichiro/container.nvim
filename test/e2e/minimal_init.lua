-- Minimal init.lua for E2E tests
-- Only includes essential Neovim APIs needed for container.nvim testing

-- Set up basic vim settings for headless mode
vim.opt.compatible = false
vim.opt.runtimepath:prepend('.')

-- Ensure essential APIs are available
-- These are built-in to Neovim but might need explicit initialization in some contexts
if not vim.json then
  -- This should not happen in modern Neovim, but just in case
  error('vim.json API not available - Neovim version too old?')
end

if not vim.fn then
  error('vim.fn API not available - Neovim version too old?')
end

if not vim.v then
  error('vim.v API not available - Neovim version too old?')
end

-- Check if vim.defer_fn is available and provide fallback if needed
if not vim.defer_fn then
  -- Provide a simple fallback implementation for headless testing
  vim.defer_fn = function(callback, delay)
    -- In headless testing, just call immediately
    -- Real vim.defer_fn is asynchronous but for testing we can simplify
    callback()
  end
end

-- Check if vim.schedule is available (used by some async operations)
if not vim.schedule then
  vim.schedule = function(callback)
    -- Simple immediate execution for testing
    callback()
  end
end

-- Set up minimal logging to avoid issues
vim.opt.verbosefile = ''
vim.opt.verbose = 0

-- Disable swap files and other file operations that might interfere
vim.opt.swapfile = false
vim.opt.backup = false
vim.opt.writebackup = false

-- Minimal configuration completed
-- print('Minimal E2E test environment initialized')
