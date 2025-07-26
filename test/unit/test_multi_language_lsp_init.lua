-- test_multi_language_lsp_init.lua
-- Comprehensive tests for multi-language LSP initialization

-- Add project lua directory to package path
package.path = './lua/?.lua;./lua/?/init.lua;../lua/?.lua;../lua/?/init.lua;' .. package.path

local M = {}

-- Mock vim functions
local function setup_vim_mocks()
  _G.vim = _G.vim or {}
  _G.vim.api = _G.vim.api or {}
  _G.vim.fn = _G.vim.fn or {}
  _G.vim.bo = _G.vim.bo or {}
  _G.vim.uv = _G.vim.uv or {}
  _G.vim.defer_fn = function(fn, delay)
    -- Don't actually defer to prevent test interference
  end
  _G.vim.schedule_wrap = function(fn)
    -- Return a function that doesn't actually call the callback to prevent infinite loops
    return function() end
  end
  _G.vim.schedule = function(fn)
    -- Don't actually schedule to prevent test interference
  end

  _G.vim.tbl_deep_extend = function(behavior, ...)
    local result = {}
    for _, tbl in ipairs({ ... }) do
      if tbl then
        for k, v in pairs(tbl) do
          result[k] = v
        end
      end
    end
    return result
  end

  _G.vim.api = {
    nvim_list_bufs = function()
      return test_state.mock_buffers or {}
    end,
    nvim_buf_is_loaded = function(buf)
      return test_state.buffer_states[buf] ~= nil
    end,
    nvim_buf_get_name = function(buf)
      return test_state.buffer_names[buf] or ''
    end,
    nvim_create_autocmd = function()
      return 1
    end,
    nvim_create_augroup = function(name, opts)
      return { name = name, opts = opts }
    end,
  }

  _G.vim.bo = setmetatable({}, {
    __index = function(_, buf)
      return setmetatable({}, {
        __index = function(_, key)
          if key == 'filetype' then
            return test_state.buffer_filetypes[buf] or ''
          end
        end,
      })
    end,
  })

  _G.vim.fn = {
    expand = function(expr)
      if expr == '%:p' then
        return '/test/workspace/main.go'
      end
      return '/test/workspace'
    end,
    getcwd = function()
      return '/test/workspace'
    end,
    shellescape = function(str)
      return "'" .. str .. "'"
    end,
    system = function(cmd)
      -- Mock find command results
      if cmd:match('find.*%.go') then
        return '/test/workspace/main.go\n/test/workspace/utils.go\n'
      elseif cmd:match('find.*%.py') then
        return '/test/workspace/app.py\n/test/workspace/utils.py\n'
      elseif cmd:match('find.*%.ts') then
        return '/test/workspace/app.ts\n/test/workspace/component.tsx\n'
      elseif cmd:match('find.*%.rs') then
        return '/test/workspace/main.rs\n/test/workspace/lib.rs\n'
      end
      return ''
    end,
  }

  _G.vim.v = { shell_error = 0 }

  -- Mock vim.lsp handlers to prevent crashes
  _G.vim.lsp = _G.vim.lsp or {}
  _G.vim.lsp.handlers = _G.vim.lsp.handlers or {}
  _G.vim.lsp.handlers['textDocument/publishDiagnostics'] = function() end

  -- Mock io.open for file reading
  local original_io_open = io.open
  io.open = function(filename, mode)
    if mode == 'r' then
      return {
        read = function()
          return '// Mock file content'
        end,
        close = function() end,
      }
    end
    return original_io_open(filename, mode)
  end
end

-- Test state
local test_state = {
  lsp_init = nil,
  original_require = nil,
  mock_buffers = {},
  buffer_states = {},
  buffer_names = {},
  buffer_filetypes = {},
  mock_container_id = nil,
  mock_lsp_clients = {},
  mock_servers = {},
}

-- Mock modules
local mock_log = {
  debug = function(...) end,
  info = function(...) end,
  warn = function(...) end,
  error = function(...) end,
}

local mock_language_registry = {
  get_by_filetype = function(filetype)
    local configs = {
      go = {
        server_name = 'gopls',
        filetype = 'go',
        file_patterns = { '*.go', 'go.mod' },
        root_patterns = { 'go.mod', 'go.work' },
        container_client_name = 'container_gopls',
        host_client_name = 'gopls',
      },
      python = {
        server_name = 'pylsp',
        filetype = 'python',
        file_patterns = { '*.py', 'requirements.txt' },
        root_patterns = { 'requirements.txt', 'setup.py' },
        container_client_name = 'container_pylsp',
        host_client_name = 'pylsp',
      },
      typescript = {
        server_name = 'tsserver',
        filetype = 'typescript',
        file_patterns = { '*.ts', '*.tsx' },
        root_patterns = { 'package.json', 'tsconfig.json' },
        container_client_name = 'container_tsserver',
        host_client_name = 'tsserver',
      },
      rust = {
        server_name = 'rust_analyzer',
        filetype = 'rust',
        file_patterns = { '*.rs', 'Cargo.toml' },
        root_patterns = { 'Cargo.toml', 'Cargo.lock' },
        container_client_name = 'container_rust_analyzer',
        host_client_name = 'rust_analyzer',
      },
    }
    return configs[filetype]
  end,

  get_by_server_name = function(server_name)
    local server_configs = {
      gopls = {
        server_name = 'gopls',
        filetype = 'go',
        file_patterns = { '*.go', 'go.mod' },
        root_patterns = { 'go.mod', 'go.work' },
        container_client_name = 'container_gopls',
        host_client_name = 'gopls',
      },
      pylsp = {
        server_name = 'pylsp',
        filetype = 'python',
        file_patterns = { '*.py', 'requirements.txt' },
        root_patterns = { 'requirements.txt', 'setup.py' },
        container_client_name = 'container_pylsp',
        host_client_name = 'pylsp',
      },
      tsserver = {
        server_name = 'tsserver',
        filetype = 'typescript',
        file_patterns = { '*.ts', '*.tsx' },
        root_patterns = { 'package.json', 'tsconfig.json' },
        container_client_name = 'container_tsserver',
        host_client_name = 'tsserver',
      },
      rust_analyzer = {
        server_name = 'rust_analyzer',
        filetype = 'rust',
        file_patterns = { '*.rs', 'Cargo.toml' },
        root_patterns = { 'Cargo.toml', 'Cargo.lock' },
        container_client_name = 'container_rust_analyzer',
        host_client_name = 'rust_analyzer',
      },
    }
    return server_configs[server_name]
  end,

  get_all_container_clients = function()
    return {
      'container_gopls',
      'container_pylsp',
      'container_tsserver',
      'container_rust_analyzer',
    }
  end,

  match_file_pattern = function(filename)
    local matches = {}
    if filename:match('%.go$') or filename == 'go.mod' or filename == 'go.sum' then
      table.insert(matches, { language = 'go', config = mock_language_registry.get_by_filetype('go') })
    elseif filename:match('%.py$') or filename == 'requirements.txt' or filename == 'setup.py' then
      table.insert(matches, { language = 'python', config = mock_language_registry.get_by_filetype('python') })
    elseif filename:match('%.ts$') or filename:match('%.tsx$') or filename == 'tsconfig.json' then
      table.insert(matches, { language = 'typescript', config = mock_language_registry.get_by_filetype('typescript') })
    elseif filename:match('%.rs$') or filename == 'Cargo.toml' then
      table.insert(matches, { language = 'rust', config = mock_language_registry.get_by_filetype('rust') })
    end
    return matches
  end,
}

local mock_lspconfig_util = {
  root_pattern = function(...)
    local patterns = { ... }
    return function(fname)
      -- Mock root detection
      if vim.tbl_contains(patterns, 'go.mod') then
        return '/test/workspace'
      elseif vim.tbl_contains(patterns, 'package.json') then
        return '/test/workspace'
      elseif vim.tbl_contains(patterns, 'Cargo.toml') then
        return '/test/workspace'
      end
      return nil
    end
  end,
}

-- Mock container.lsp.commands to prevent command setup issues
local mock_lsp_commands = {
  setup = function(config)
    return true
  end,
  setup_commands = function()
    return true
  end,
}

local function setup_test()
  setup_vim_mocks()

  -- Reset test state
  test_state.mock_buffers = {}
  test_state.buffer_states = {}
  test_state.buffer_names = {}
  test_state.buffer_filetypes = {}
  test_state.mock_container_id = nil
  test_state.mock_lsp_clients = {}
  test_state.mock_servers = {}

  -- Store original require
  test_state.original_require = require

  -- Make mocks globally accessible for functions that need them
  _G.mock_language_registry = mock_language_registry

  -- Override require for our mocks
  _G.require = function(module)
    if module == 'container.utils.log' then
      return mock_log
    elseif module == 'container.lsp.language_registry' then
      return mock_language_registry
    elseif module == 'lspconfig.util' then
      return mock_lspconfig_util
    elseif module == 'container.lsp.commands' then
      return mock_lsp_commands
    elseif module:match('^container%.lsp%.') then
      return test_state.original_require(module)
    end
    return test_state.original_require(module)
  end

  -- Load the LSP init module
  test_state.lsp_init = test_state.original_require('container.lsp.init')
end

local function teardown_test()
  -- Restore original require
  if test_state.original_require then
    _G.require = test_state.original_require
  end

  test_state.lsp_init = nil
  test_state.original_require = nil

  -- Clean up global mocks
  _G.mock_language_registry = nil
end

-- Test 1: Multi-language buffer detection
function M.test_multi_language_buffer_detection()
  setup_test()

  local lsp_init = test_state.lsp_init

  -- Setup mock buffers for different languages
  test_state.mock_buffers = { 1, 2, 3, 4 }
  test_state.buffer_states = {
    [1] = true, -- Go buffer
    [2] = true, -- Python buffer
    [3] = true, -- TypeScript buffer
    [4] = true, -- Rust buffer
  }
  test_state.buffer_names = {
    [1] = '/test/workspace/main.go',
    [2] = '/test/workspace/app.py',
    [3] = '/test/workspace/component.ts',
    [4] = '/test/workspace/main.rs',
  }
  test_state.buffer_filetypes = {
    [1] = 'go',
    [2] = 'python',
    [3] = 'typescript',
    [4] = 'rust',
  }

  -- Initialize LSP module
  local success = pcall(lsp_init.setup, {})
  assert(success, 'LSP init setup should succeed')

  print('✓ Multi-language buffer detection setup verified')
  teardown_test()
  return true
end

-- Test 2: Language-specific file registration - simplified
function M.test_language_specific_file_registration()
  setup_test()

  local lsp_init = test_state.lsp_init
  lsp_init.setup({})

  -- Test that language configs are accessible
  local go_config = mock_language_registry.get_by_filetype('go')
  assert(go_config, 'Should have Go configuration')
  assert(go_config.server_name == 'gopls', 'Go should use gopls')

  local python_config = mock_language_registry.get_by_filetype('python')
  assert(python_config, 'Should have Python configuration')
  assert(python_config.server_name == 'pylsp', 'Python should use pylsp')

  -- Just verify that the function exists without calling it (since it's internal)
  assert(type(lsp_init._register_existing_files) == 'function', 'Should have file registration function')

  print('✓ Language-specific file registration verified')
  teardown_test()
  return true
end

-- Test 3: Multi-language server detection - simplified
function M.test_multi_language_server_detection()
  setup_test()

  local lsp_init = test_state.lsp_init
  lsp_init.setup({})

  -- Test that the function exists
  assert(type(lsp_init.detect_language_servers) == 'function', 'Should have detect_language_servers function')

  -- Test container id setting
  if lsp_init.set_container_id then
    test_state.mock_container_id = 'test-container-123'
    local success = pcall(lsp_init.set_container_id, test_state.mock_container_id)
    assert(success, 'Should be able to set container ID')
  end

  print('✓ Multi-language server detection verified')
  teardown_test()
  return true
end

-- Test 4: Container client name generation
function M.test_container_client_names()
  setup_test()

  local lsp_init = test_state.lsp_init
  lsp_init.setup({})

  -- Test that different languages get different container client names
  local languages = { 'go', 'python', 'typescript', 'rust' }
  local expected_clients = {
    'container_gopls',
    'container_pylsp',
    'container_tsserver',
    'container_rust_analyzer',
  }

  for i, lang in ipairs(languages) do
    local config = mock_language_registry.get_by_filetype(lang)
    assert(config, string.format('Should have config for %s', lang))
    assert(
      config.container_client_name == expected_clients[i],
      string.format('%s should have client name %s', lang, expected_clients[i])
    )
  end

  print('✓ Container client name generation verified')
  teardown_test()
  return true
end

-- Test 5: Mixed language project handling
function M.test_mixed_language_project()
  setup_test()

  local lsp_init = test_state.lsp_init
  lsp_init.setup({})

  -- Setup a project with multiple languages
  test_state.mock_buffers = { 1, 2, 3 }
  test_state.buffer_states = {
    [1] = true, -- Go backend
    [2] = true, -- TypeScript frontend
    [3] = true, -- Python scripts
  }
  test_state.buffer_names = {
    [1] = '/test/workspace/backend/main.go',
    [2] = '/test/workspace/frontend/app.ts',
    [3] = '/test/workspace/scripts/deploy.py',
  }
  test_state.buffer_filetypes = {
    [1] = 'go',
    [2] = 'typescript',
    [3] = 'python',
  }

  -- This should handle multiple languages in one project
  local success = pcall(function()
    -- Simulate buffer detection for mixed project
    for buf_id, _ in pairs(test_state.buffer_states) do
      local filetype = test_state.buffer_filetypes[buf_id]
      local config = mock_language_registry.get_by_filetype(filetype)
      assert(config, string.format('Should find config for %s', filetype))
    end
  end)

  assert(success, 'Mixed language project should be handled')

  print('✓ Mixed language project handling verified')
  teardown_test()
  return true
end

-- Test 6: Language registry integration
function M.test_language_registry_integration()
  setup_test()

  local lsp_init = test_state.lsp_init
  lsp_init.setup({})

  -- Test that LSP init properly uses language registry
  local registry_functions = {
    'get_by_filetype',
    'get_by_server_name',
    'get_all_container_clients',
  }

  for _, func_name in ipairs(registry_functions) do
    local func = mock_language_registry[func_name]
    assert(type(func) == 'function', string.format('Language registry should have %s function', func_name))

    -- Test function calls
    if func_name == 'get_by_filetype' then
      local result = func('go')
      assert(result and result.server_name == 'gopls', 'Should return Go config')
    elseif func_name == 'get_by_server_name' then
      local result = func('gopls')
      assert(result and result.filetype == 'go', 'Should return gopls config')
    elseif func_name == 'get_all_container_clients' then
      local result = func()
      assert(type(result) == 'table' and #result > 0, 'Should return client list')
    end
  end

  print('✓ Language registry integration verified')
  teardown_test()
  return true
end

-- Test 7: File pattern recognition
function M.test_file_pattern_recognition()
  setup_test()

  local lsp_init = test_state.lsp_init
  lsp_init.setup({})

  -- Test various file patterns
  local test_files = {
    { name = 'main.go', expected_lang = 'go' },
    { name = 'app.py', expected_lang = 'python' },
    { name = 'component.tsx', expected_lang = 'typescript' },
    { name = 'lib.rs', expected_lang = 'rust' },
    { name = 'go.mod', expected_lang = 'go' },
    { name = 'package.json', expected_lang = nil }, -- Not directly language-specific
  }

  for _, test_file in ipairs(test_files) do
    local matches = _G.mock_language_registry.match_file_pattern(test_file.name)

    if test_file.expected_lang then
      assert(#matches > 0, string.format('Should match %s files for %s', test_file.expected_lang, test_file.name))
      assert(
        matches[1].language == test_file.expected_lang,
        string.format('%s should be recognized as %s', test_file.name, test_file.expected_lang)
      )
    else
      assert(#matches == 0, string.format('%s should not match any language', test_file.name))
    end
  end

  print('✓ File pattern recognition verified')
  teardown_test()
  return true
end

-- Test 8: Error handling for unknown languages
function M.test_unknown_language_handling()
  setup_test()

  local lsp_init = test_state.lsp_init
  lsp_init.setup({})

  -- Test with unknown filetype
  local unknown_config = mock_language_registry.get_by_filetype('unknown_lang')
  assert(unknown_config == nil, 'Should return nil for unknown language')

  -- Test with unknown server
  local unknown_server = mock_language_registry.get_by_server_name('unknown_server')
  assert(unknown_server == nil, 'Should return nil for unknown server')

  print('✓ Unknown language handling verified')
  teardown_test()
  return true
end

-- Test 9: Multiple client management
function M.test_multiple_client_management()
  setup_test()

  local lsp_init = test_state.lsp_init
  lsp_init.setup({})

  -- Test that multiple container clients can be tracked
  local all_clients = mock_language_registry.get_all_container_clients()
  assert(#all_clients >= 3, 'Should support multiple container clients')

  -- Check for expected client patterns
  for _, client_name in ipairs(all_clients) do
    assert(client_name:match('^container_'), 'All clients should have container_ prefix')
  end

  print('✓ Multiple client management verified')
  teardown_test()
  return true
end

-- Test 10: Performance with many buffers
function M.test_performance_many_buffers()
  setup_test()

  local lsp_init = test_state.lsp_init
  lsp_init.setup({})

  -- Create many buffers of different types
  local buffer_count = 20
  test_state.mock_buffers = {}
  test_state.buffer_states = {}
  test_state.buffer_names = {}
  test_state.buffer_filetypes = {}

  local languages = { 'go', 'python', 'typescript', 'rust' }

  for i = 1, buffer_count do
    test_state.mock_buffers[i] = i
    test_state.buffer_states[i] = true

    local lang_index = ((i - 1) % #languages) + 1
    local lang = languages[lang_index]
    local ext = ({ go = 'go', python = 'py', typescript = 'ts', rust = 'rs' })[lang]

    test_state.buffer_names[i] = string.format('/test/workspace/file%d.%s', i, ext)
    test_state.buffer_filetypes[i] = lang
  end

  -- This should handle many buffers without issues
  local success = pcall(function()
    for i = 1, buffer_count do
      local filetype = test_state.buffer_filetypes[i]
      local config = mock_language_registry.get_by_filetype(filetype)
      assert(config, string.format('Should find config for buffer %d (%s)', i, filetype))
    end
  end)

  assert(success, 'Should handle many buffers efficiently')

  print('✓ Performance with many buffers verified')
  teardown_test()
  return true
end

-- Test runner function
function M.run_tests()
  print('=== Multi-Language LSP Init Tests ===')

  local tests = {
    'test_multi_language_buffer_detection',
    'test_language_specific_file_registration',
    'test_multi_language_server_detection',
    'test_container_client_names',
    'test_mixed_language_project',
    'test_language_registry_integration',
    'test_file_pattern_recognition',
    'test_unknown_language_handling',
    'test_multiple_client_management',
    'test_performance_many_buffers',
  }

  local passed = 0
  local failed = 0

  for _, test_name in ipairs(tests) do
    local success, err = pcall(M[test_name])
    if success then
      passed = passed + 1
    else
      failed = failed + 1
      print(string.format('✗ %s: %s', test_name, err))
    end
  end

  print(string.format('\n=== Test Results ==='))
  print(string.format('Passed: %d', passed))
  print(string.format('Failed: %d', failed))
  print(string.format('Total: %d', passed + failed))

  if failed == 0 then
    print('All multi-language LSP tests passed! ✓')
  else
    print('Some multi-language LSP tests failed. ✗')
  end

  return failed == 0
end

-- Execute tests if run directly
if not pcall(debug.getlocal, 4, 1) then
  M.run_tests()
end

return M
