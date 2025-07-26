-- Language-specific LSP server registry and configuration
local M = {}

-- Default language to LSP server mappings
M.language_mappings = {
  go = {
    server_name = 'gopls',
    filetype = 'go',
    file_patterns = { '*.go', 'go.mod', 'go.sum' },
    root_patterns = { 'go.mod', 'go.sum', '.git' },
    container_client_name = 'container_gopls',
    host_client_name = 'gopls',
  },
  python = {
    server_name = 'pylsp',
    filetype = 'python',
    file_patterns = { '*.py', 'requirements.txt', 'setup.py', 'pyproject.toml' },
    root_patterns = { 'requirements.txt', 'setup.py', 'pyproject.toml', '.git' },
    container_client_name = 'container_pylsp',
    host_client_name = 'pylsp',
  },
  typescript = {
    server_name = 'tsserver',
    filetype = 'typescript',
    file_patterns = { '*.ts', '*.tsx', 'package.json', 'tsconfig.json' },
    root_patterns = { 'package.json', 'tsconfig.json', '.git' },
    container_client_name = 'container_tsserver',
    host_client_name = 'tsserver',
  },
  javascript = {
    server_name = 'tsserver',
    filetype = 'javascript',
    file_patterns = { '*.js', '*.jsx', 'package.json' },
    root_patterns = { 'package.json', '.git' },
    container_client_name = 'container_tsserver',
    host_client_name = 'tsserver',
  },
  rust = {
    server_name = 'rust_analyzer',
    filetype = 'rust',
    file_patterns = { '*.rs', 'Cargo.toml', 'Cargo.lock' },
    root_patterns = { 'Cargo.toml', 'Cargo.lock', '.git' },
    container_client_name = 'container_rust_analyzer',
    host_client_name = 'rust_analyzer',
  },
  c = {
    server_name = 'clangd',
    filetype = 'c',
    file_patterns = { '*.c', '*.h', 'CMakeLists.txt', 'compile_commands.json' },
    root_patterns = { 'CMakeLists.txt', 'compile_commands.json', '.git' },
    container_client_name = 'container_clangd',
    host_client_name = 'clangd',
  },
  cpp = {
    server_name = 'clangd',
    filetype = 'cpp',
    file_patterns = { '*.cpp', '*.cxx', '*.cc', '*.hpp', '*.hxx', 'CMakeLists.txt', 'compile_commands.json' },
    root_patterns = { 'CMakeLists.txt', 'compile_commands.json', '.git' },
    container_client_name = 'container_clangd',
    host_client_name = 'clangd',
  },
  lua = {
    server_name = 'lua_ls',
    filetype = 'lua',
    file_patterns = { '*.lua' },
    root_patterns = { '.luarc.json', '.luarc.jsonc', '.git' },
    container_client_name = 'container_lua_ls',
    host_client_name = 'lua_ls',
  },
}

-- Alternative server configurations for languages with multiple LSP options
M.alternative_servers = {
  python = {
    pyright = {
      server_name = 'pyright',
      container_client_name = 'container_pyright',
      host_client_name = 'pyright',
    },
  },
}

-- Get language configuration by filetype
function M.get_by_filetype(filetype)
  for _, config in pairs(M.language_mappings) do
    if config.filetype == filetype then
      return config
    end
  end
  return nil
end

-- Get language configuration by server name
function M.get_by_server_name(server_name)
  for _, config in pairs(M.language_mappings) do
    if config.server_name == server_name then
      return config
    end
  end
  return nil
end

-- Get language configuration by container client name
function M.get_by_container_client_name(client_name)
  for _, config in pairs(M.language_mappings) do
    if config.container_client_name == client_name then
      return config
    end
  end
  return nil
end

-- Get all supported languages
function M.get_supported_languages()
  return vim.tbl_keys(M.language_mappings)
end

-- Get all container client names
function M.get_all_container_clients()
  local clients = {}
  for _, config in pairs(M.language_mappings) do
    table.insert(clients, config.container_client_name)
  end
  return clients
end

-- Check if a file pattern matches any language
function M.match_file_pattern(filename)
  if not filename or filename == '' then
    return {}
  end

  local matched_languages = {}
  for lang, config in pairs(M.language_mappings) do
    for _, pattern in ipairs(config.file_patterns) do
      -- Convert glob pattern to lua pattern
      local lua_pattern = pattern:gsub('%*', '.*'):gsub('%.', '%%.')
      if filename:match(lua_pattern .. '$') then
        table.insert(matched_languages, { language = lang, config = config })
      end
    end
  end
  return matched_languages
end

-- Check if current directory has files matching language patterns
function M.detect_project_languages()
  local detected = {}
  local fs = require('container.utils.fs')

  for lang, config in pairs(M.language_mappings) do
    for _, pattern in ipairs(config.file_patterns) do
      local files = fs.find_files(pattern, vim.fn.getcwd(), { limit = 1 })
      if #files > 0 then
        detected[lang] = config
        break
      end
    end
  end

  return detected
end

-- Add or update language mapping
function M.register_language(language, config)
  M.language_mappings[language] = vim.tbl_deep_extend('force', M.language_mappings[language] or {}, config)
end

-- Add alternative server for a language
function M.register_alternative_server(language, server_key, config)
  M.alternative_servers[language] = M.alternative_servers[language] or {}
  M.alternative_servers[language][server_key] = config
end

-- Get alternative servers for a language
function M.get_alternative_servers(language)
  return M.alternative_servers[language] or {}
end

return M
