-- .luacheckrc configuration for container.nvim

-- Global options
std = "lua54+luajit"

-- Files to check
files = {
  "lua/",
  "plugin/"
}

-- Exclude patterns
exclude_files = {
  "test/",
  "examples/"
}

-- Globals provided by Neovim
globals = {
  "vim",
  "_G",
}

-- Read-only globals
read_globals = {
  -- Vim API
  "vim.api",
  "vim.cmd",
  "vim.fn",
  "vim.fs",
  "vim.log",
  "vim.loop",
  "vim.lsp",
  "vim.schedule",
  "vim.split",
  "vim.startswith",
  "vim.tbl_contains",
  "vim.tbl_deep_extend",
  "vim.tbl_keys",
  "vim.trim",
  "vim.uri_from_fname",
  "vim.uri_to_fname",
  "vim.deepcopy",
  "vim.inspect",
  "vim.defer_fn",

  -- Standard library extensions
  "table.unpack",
  "unpack",
}

-- Warning configuration
-- Disable specific warnings
ignore = {
  "431",  -- Shadowing upvalue (for common names like 'config', 'log')
  "542",  -- Empty if branch
  "561",  -- Cyclomatic complexity (we'll address these case by case)
  "611",  -- Line contains only whitespace (formatting issue)
  "631",  -- Line is too long (we'll address these case by case)
}

-- Maximum line length
max_line_length = 120

-- Maximum cyclomatic complexity
max_cyclomatic_complexity = 15

-- Report only warnings for:
-- - 111: Setting non-standard global variable
-- - 112: Mutating non-standard global variable
-- - 113: Accessing undefined variable
-- - 211: Unused local variable
-- - 311: Value assigned to variable is unused
-- - 411: Redefining local variable
-- - 412: Redefining argument
-- - 421: Shadowing definition of variable
-- - 422: Shadowing definition of argument
-- - 423: Shadowing definition of loop variable

-- Only report these warnings
only = {
  "111", "112", "113",
  "211", "221", "231",
  "311", "321", "331",
  "411", "412", "413",
  "421", "422", "423",
  "511", "512", "521", "531", "532", "541", "542", "551", "561", "571", "581",
  "611", "612", "613", "614", "621", "631"
}

-- Format configuration
codes = true
formatter = "default"

-- Cache results for faster subsequent runs
cache = true
