-- test_lsp_language_registry.lua
-- Tests for lua/container/lsp/language_registry.lua

-- Add project lua directory to package path
package.path = './lua/?.lua;./lua/?/init.lua;../lua/?.lua;../lua/?/init.lua;' .. package.path

local M = {}

-- Mock vim functions
local function setup_vim_mocks()
  -- Mock vim.fs.basename
  _G.vim = _G.vim or {}
  _G.vim.fs = _G.vim.fs or {}
  _G.vim.fs.basename = function(path)
    return path:match('([^/]+)$') or path
  end

  -- Mock vim.fn.getcwd
  _G.vim.fn = _G.vim.fn or {}
  _G.vim.fn.getcwd = function()
    return '/test/workspace'
  end

  -- Mock vim.tbl_keys
  _G.vim.tbl_keys = function(tbl)
    local keys = {}
    for key, _ in pairs(tbl) do
      table.insert(keys, key)
    end
    return keys
  end

  -- Mock vim.tbl_deep_extend
  _G.vim.tbl_deep_extend = function(behavior, ...)
    local result = {}
    for _, tbl in ipairs({ ... }) do
      if tbl then
        for k, v in pairs(tbl) do
          if type(v) == 'table' and type(result[k]) == 'table' then
            result[k] = vim.tbl_deep_extend(behavior, result[k], v)
          else
            result[k] = v
          end
        end
      end
    end
    return result
  end
end

-- Test state management
local test_state = {
  registry = nil,
  original_require = nil,
}

local function setup_test()
  setup_vim_mocks()

  -- Mock container.utils.fs module
  local mock_fs = {
    find_files = function(pattern, dir, opts)
      -- Simulate finding files based on pattern
      local files = {}
      if pattern:match('%.go$') or pattern == '*.go' then
        table.insert(files, '/test/workspace/main.go')
        table.insert(files, '/test/workspace/utils.go')
      elseif pattern:match('%.py$') or pattern == '*.py' then
        table.insert(files, '/test/workspace/main.py')
      elseif pattern:match('%.ts$') or pattern == '*.ts' then
        table.insert(files, '/test/workspace/app.ts')
      elseif pattern == 'go.mod' then
        table.insert(files, '/test/workspace/go.mod')
      elseif pattern == 'package.json' then
        table.insert(files, '/test/workspace/package.json')
      end

      if opts and opts.limit then
        local limited = {}
        for i = 1, math.min(opts.limit, #files) do
          table.insert(limited, files[i])
        end
        return limited
      end

      return files
    end,
  }

  -- Store original require
  test_state.original_require = require

  -- Override require for our mock
  _G.require = function(module)
    if module == 'container.utils.fs' then
      return mock_fs
    end
    return test_state.original_require(module)
  end

  -- Load the registry module
  test_state.registry = test_state.original_require('container.lsp.language_registry')
end

local function teardown_test()
  -- Restore original require
  if test_state.original_require then
    _G.require = test_state.original_require
  end

  test_state.registry = nil
  test_state.original_require = nil
end

-- Test 1: Basic module loading and structure
function M.test_module_loading()
  setup_test()

  local registry = test_state.registry

  -- Test module structure
  assert(type(registry) == 'table', 'Registry should be a table')
  assert(type(registry.language_mappings) == 'table', 'Should have language_mappings')
  assert(type(registry.alternative_servers) == 'table', 'Should have alternative_servers')

  -- Test required functions
  local required_functions = {
    'get_by_filetype',
    'get_by_server_name',
    'get_by_container_client_name',
    'get_supported_languages',
    'get_all_container_clients',
    'match_file_pattern',
    'detect_project_languages',
    'register_language',
    'register_alternative_server',
    'get_alternative_servers',
  }

  for _, func_name in ipairs(required_functions) do
    assert(type(registry[func_name]) == 'function', string.format('Should have %s function', func_name))
  end

  print('✓ Module loading and structure verified')
  teardown_test()
  return true
end

-- Test 2: Language mapping queries
function M.test_language_mappings()
  setup_test()

  local registry = test_state.registry

  -- Test get_by_filetype
  local go_config = registry.get_by_filetype('go')
  assert(go_config, 'Should find Go configuration')
  assert(go_config.server_name == 'gopls', 'Go should use gopls')
  assert(go_config.container_client_name == 'container_gopls', 'Go should have container_gopls client')

  local python_config = registry.get_by_filetype('python')
  assert(python_config, 'Should find Python configuration')
  assert(python_config.server_name == 'pylsp', 'Python should use pylsp')

  local rust_config = registry.get_by_filetype('rust')
  assert(rust_config, 'Should find Rust configuration')
  assert(rust_config.server_name == 'rust_analyzer', 'Rust should use rust_analyzer')

  -- Test non-existent filetype
  local unknown_config = registry.get_by_filetype('unknown')
  assert(unknown_config == nil, 'Should return nil for unknown filetype')

  print('✓ Language mapping queries verified')
  teardown_test()
  return true
end

-- Test 3: Server name queries
function M.test_server_name_queries()
  setup_test()

  local registry = test_state.registry

  -- Test get_by_server_name
  local gopls_config = registry.get_by_server_name('gopls')
  assert(gopls_config, 'Should find gopls configuration')
  assert(gopls_config.filetype == 'go', 'gopls should be for Go')

  local tsserver_config = registry.get_by_server_name('tsserver')
  assert(tsserver_config, 'Should find tsserver configuration')
  -- tsserver is used for both TypeScript and JavaScript, so check one of them
  assert(
    tsserver_config.filetype == 'typescript' or tsserver_config.filetype == 'javascript',
    'tsserver should be for TypeScript or JavaScript'
  )

  local unknown_server = registry.get_by_server_name('unknown_server')
  assert(unknown_server == nil, 'Should return nil for unknown server')

  print('✓ Server name queries verified')
  teardown_test()
  return true
end

-- Test 4: Container client name queries
function M.test_container_client_queries()
  setup_test()

  local registry = test_state.registry

  -- Test get_by_container_client_name
  local gopls_config = registry.get_by_container_client_name('container_gopls')
  assert(gopls_config, 'Should find config by container client name')
  assert(gopls_config.server_name == 'gopls', 'Should be gopls config')

  local pylsp_config = registry.get_by_container_client_name('container_pylsp')
  assert(pylsp_config, 'Should find pylsp config by container client name')
  assert(pylsp_config.server_name == 'pylsp', 'Should be pylsp config')

  -- Test get_all_container_clients
  local all_clients = registry.get_all_container_clients()
  assert(type(all_clients) == 'table', 'Should return table of client names')
  assert(#all_clients > 0, 'Should have at least one client')

  -- Check that expected clients are present
  local has_gopls = false
  local has_pylsp = false
  for _, client_name in ipairs(all_clients) do
    if client_name == 'container_gopls' then
      has_gopls = true
    end
    if client_name == 'container_pylsp' then
      has_pylsp = true
    end
  end
  assert(has_gopls, 'Should include container_gopls')
  assert(has_pylsp, 'Should include container_pylsp')

  print('✓ Container client queries verified')
  teardown_test()
  return true
end

-- Test 5: Supported languages
function M.test_supported_languages()
  setup_test()

  local registry = test_state.registry

  local languages = registry.get_supported_languages()
  assert(type(languages) == 'table', 'Should return table of languages')
  assert(#languages > 0, 'Should have at least one language')

  -- Check for expected languages
  local expected_langs = { 'go', 'python', 'typescript', 'rust', 'c', 'cpp', 'lua' }
  local found_langs = {}

  for _, lang in ipairs(languages) do
    found_langs[lang] = true
  end

  for _, expected in ipairs(expected_langs) do
    assert(found_langs[expected], string.format('Should include %s language', expected))
  end

  print('✓ Supported languages verified')
  teardown_test()
  return true
end

-- Test 6: File pattern matching
function M.test_file_pattern_matching()
  setup_test()

  local registry = test_state.registry

  -- Test Go file matching
  local go_matches = registry.match_file_pattern('main.go')
  assert(#go_matches > 0, 'Should match Go files')
  assert(go_matches[1].language == 'go', 'Should identify as Go language')

  -- Test Python file matching
  local python_matches = registry.match_file_pattern('app.py')
  assert(#python_matches > 0, 'Should match Python files')
  assert(python_matches[1].language == 'python', 'Should identify as Python language')

  -- Test TypeScript file matching
  local ts_matches = registry.match_file_pattern('component.tsx')
  assert(#ts_matches > 0, 'Should match TypeScript files')
  assert(ts_matches[1].language == 'typescript', 'Should identify as TypeScript language')

  -- Test Rust file matching
  local rust_matches = registry.match_file_pattern('main.rs')
  assert(#rust_matches > 0, 'Should match Rust files')
  assert(rust_matches[1].language == 'rust', 'Should identify as Rust language')

  -- Test no match
  local no_matches = registry.match_file_pattern('unknown.xyz')
  assert(#no_matches == 0, 'Should not match unknown file types')

  print('✓ File pattern matching verified')
  teardown_test()
  return true
end

-- Test 7: Project language detection
function M.test_project_detection()
  setup_test()

  local registry = test_state.registry

  local detected = registry.detect_project_languages()
  assert(type(detected) == 'table', 'Should return table of detected languages')

  -- Based on our mock, we should detect Go and Python
  assert(detected.go, 'Should detect Go in project')
  assert(detected.python, 'Should detect Python in project')
  assert(detected.go.server_name == 'gopls', 'Go detection should include config')

  print('✓ Project language detection verified')
  teardown_test()
  return true
end

-- Test 8: Language registration
function M.test_language_registration()
  setup_test()

  local registry = test_state.registry

  -- Test registering new language
  local new_lang_config = {
    server_name = 'test_server',
    filetype = 'testlang',
    file_patterns = { '*.test' },
    root_patterns = { '.testroot' },
    container_client_name = 'container_test_server',
    host_client_name = 'test_server',
  }

  registry.register_language('testlang', new_lang_config)

  -- Verify registration
  local registered_config = registry.get_by_filetype('testlang')
  assert(registered_config, 'Should find registered language')
  assert(registered_config.server_name == 'test_server', 'Should have correct server name')

  -- Test updating existing language
  registry.register_language('go', {
    custom_setting = 'test_value',
  })

  local updated_go = registry.get_by_filetype('go')
  assert(updated_go.custom_setting == 'test_value', 'Should merge configuration')
  assert(updated_go.server_name == 'gopls', 'Should preserve existing settings')

  print('✓ Language registration verified')
  teardown_test()
  return true
end

-- Test 9: Alternative servers
function M.test_alternative_servers()
  setup_test()

  local registry = test_state.registry

  -- Test registering alternative server
  registry.register_alternative_server('python', 'pyright_alt', {
    server_name = 'pyright',
    container_client_name = 'container_pyright_alt',
    host_client_name = 'pyright',
  })

  -- Test getting alternatives
  local alternatives = registry.get_alternative_servers('python')
  assert(type(alternatives) == 'table', 'Should return alternatives table')
  assert(alternatives.pyright_alt, 'Should include registered alternative')
  assert(alternatives.pyright_alt.server_name == 'pyright', 'Should have correct config')

  -- Test language with no alternatives
  local no_alternatives = registry.get_alternative_servers('nonexistent')
  assert(type(no_alternatives) == 'table', 'Should return empty table for non-existent language')
  assert(next(no_alternatives) == nil, 'Should be empty table')

  print('✓ Alternative servers verified')
  teardown_test()
  return true
end

-- Test 10: Edge cases and error handling
function M.test_edge_cases()
  setup_test()

  local registry = test_state.registry

  -- Test with nil inputs
  assert(registry.get_by_filetype(nil) == nil, 'Should handle nil filetype')
  assert(registry.get_by_server_name(nil) == nil, 'Should handle nil server name')
  assert(registry.get_by_container_client_name(nil) == nil, 'Should handle nil client name')

  -- Test with empty string inputs
  assert(registry.get_by_filetype('') == nil, 'Should handle empty filetype')
  assert(registry.get_by_server_name('') == nil, 'Should handle empty server name')

  -- Test file pattern matching with edge cases
  local empty_matches = registry.match_file_pattern('')
  assert(#empty_matches == 0, 'Should handle empty filename')

  local nil_matches = registry.match_file_pattern(nil)
  assert(#nil_matches == 0, 'Should handle nil filename')

  print('✓ Edge cases verified')
  teardown_test()
  return true
end

-- Test runner function
function M.run_tests()
  print('=== LSP Language Registry Tests ===')

  local tests = {
    'test_module_loading',
    'test_language_mappings',
    'test_server_name_queries',
    'test_container_client_queries',
    'test_supported_languages',
    'test_file_pattern_matching',
    'test_project_detection',
    'test_language_registration',
    'test_alternative_servers',
    'test_edge_cases',
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
    print('All language registry tests passed! ✓')
  else
    print('Some language registry tests failed. ✗')
  end

  return failed == 0
end

-- Execute tests if run directly
if not pcall(debug.getlocal, 4, 1) then
  M.run_tests()
end

return M
