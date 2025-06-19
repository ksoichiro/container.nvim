-- Local configuration for this example project
-- This demonstrates how to set up nvim-test with container.nvim

-- If you have vim-test installed, it will be automatically configured
-- to run tests in the container

-- Example key mappings for test execution
vim.api.nvim_set_keymap('n', '<leader>tn', ':ContainerTestNearest<CR>', { noremap = true, silent = true, desc = 'Run nearest test in container' })
vim.api.nvim_set_keymap('n', '<leader>tf', ':ContainerTestFile<CR>', { noremap = true, silent = true, desc = 'Run file tests in container' })
vim.api.nvim_set_keymap('n', '<leader>ts', ':ContainerTestSuite<CR>', { noremap = true, silent = true, desc = 'Run test suite in container' })

-- Terminal-based test execution
vim.api.nvim_set_keymap('n', '<leader>tN', ':ContainerTestNearestTerminal<CR>', { noremap = true, silent = true, desc = 'Run nearest test in terminal' })
vim.api.nvim_set_keymap('n', '<leader>tF', ':ContainerTestFileTerminal<CR>', { noremap = true, silent = true, desc = 'Run file tests in terminal' })
vim.api.nvim_set_keymap('n', '<leader>tS', ':ContainerTestSuiteTerminal<CR>', { noremap = true, silent = true, desc = 'Run test suite in terminal' })

-- If you have vim-test, these will also work and run in container:
-- vim.api.nvim_set_keymap('n', '<leader>t', ':TestNearest<CR>', { noremap = true, silent = true })
-- vim.api.nvim_set_keymap('n', '<leader>T', ':TestFile<CR>', { noremap = true, silent = true })

-- Optional: Configure test output display
vim.g.test_preserve_screen = 1  -- Preserve screen after test runs
vim.g.test_neovim_silent = 0    -- Show test output

print("Test integration example loaded. Use <leader>tn, <leader>tf, or <leader>ts to run tests.")
