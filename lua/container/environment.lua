-- lua/devcontainer/environment.lua
-- Environment variable management for devcontainer execution contexts

local M = {}

local log = require('container.utils.log')

-- Default environment paths for common languages
local language_presets = {
  go = {
    PATH = '/home/vscode/.local/bin:/usr/local/go/bin:/go/bin:$PATH',
    GOPATH = '/go',
    GOROOT = '/usr/local/go',
  },
  python = {
    PATH = '/home/vscode/.local/bin:/usr/local/python/current/bin:$PATH',
    PYTHONPATH = '/workspace',
  },
  node = {
    PATH = '/home/vscode/.local/bin:/usr/local/nodejs/bin:$PATH',
    NODE_ENV = 'development',
  },
  rust = {
    PATH = '/home/vscode/.local/bin:/home/vscode/.cargo/bin:$PATH',
    CARGO_HOME = '/home/vscode/.cargo',
    RUSTUP_HOME = '/home/vscode/.rustup',
  },
  -- Default paths if no language preset is specified
  default = {
    PATH = '/home/vscode/.local/bin:$PATH',
  },
}

-- Get environment variables supporting both standard and custom formats
local function get_environment(config, context_type)
  if not config then
    return {}
  end

  local env = {}

  -- 1. Start with standard devcontainer environment variables
  if config.containerEnv then
    env = vim.tbl_deep_extend('force', env, config.containerEnv)
    log.debug('Applied standard containerEnv')
  end

  if config.remoteEnv then
    env = vim.tbl_deep_extend('force', env, config.remoteEnv)
    log.debug('Applied standard remoteEnv')
  end

  -- 2. Apply language presets (for backward compatibility)
  if config.customizations and config.customizations['container.nvim'] then
    local customizations = config.customizations['container.nvim']

    if customizations.languagePreset and language_presets[customizations.languagePreset] then
      env = vim.tbl_deep_extend('force', env, language_presets[customizations.languagePreset])
      log.debug('Applied language preset: %s', customizations.languagePreset)
    end

    -- 3. Apply legacy context-specific environment (with deprecation warning)
    local context_env_key = context_type .. 'Environment'
    if customizations[context_env_key] then
      log.warn('DEPRECATED: %s is deprecated, use standard containerEnv/remoteEnv instead', context_env_key)
      env = vim.tbl_deep_extend('force', env, customizations[context_env_key])
      log.debug('Applied legacy %s environment overrides', context_type)
    end

    -- 4. Apply additional environment variables (legacy)
    if customizations.additionalEnvironment then
      log.warn('DEPRECATED: additionalEnvironment is deprecated, use standard containerEnv/remoteEnv instead')
      env = vim.tbl_deep_extend('force', env, customizations.additionalEnvironment)
      log.debug('Applied legacy additional environment variables')
    end
  end

  -- 5. Apply default language preset if no environment configured
  if vim.tbl_isempty(env) then
    env = vim.tbl_deep_extend('force', env, language_presets.default)
    log.debug('Applied default language preset')
  end

  return env
end

-- Expand environment variables (like $PATH)
local function expand_env_vars(value)
  -- Simple expansion for $PATH - replace with basic system PATH
  value = value:gsub('%$PATH', '/usr/local/bin:/usr/bin:/bin')
  return value
end

-- Build environment variable arguments for docker exec
function M.build_env_args(config, context_type)
  local env = get_environment(config, context_type)
  local args = {}

  -- Use the user specified in devcontainer.json
  -- Check both camelCase and snake_case variants
  local user = config.remoteUser or config.remote_user
  if user then
    log.debug('Using specified user for exec: %s', user)
    table.insert(args, '-u')
    table.insert(args, user)
  else
    log.debug('No remoteUser specified, using container default user')
    -- Don't specify -u flag, let Docker use the container's default user
  end

  -- Add environment variables with expansion
  for key, value in pairs(env) do
    table.insert(args, '-e')
    local expanded_value = expand_env_vars(value)
    table.insert(args, key .. '=' .. expanded_value)
    log.debug('Environment: %s=%s', key, expanded_value)
  end

  return args
end

-- Get environment for postCreateCommand execution
function M.get_postcreate_environment(config)
  return get_environment(config, 'postCreate')
end

-- Get environment for DevcontainerExec execution
function M.get_exec_environment(config)
  return get_environment(config, 'exec')
end

-- Get environment for LSP-related execution
function M.get_lsp_environment(config)
  return get_environment(config, 'lsp')
end

-- Build docker exec arguments for postCreateCommand
function M.build_postcreate_args(config)
  return M.build_env_args(config, 'postCreate')
end

-- Build docker exec arguments for DevcontainerExec
function M.build_exec_args(config)
  return M.build_env_args(config, 'exec')
end

-- Build docker exec arguments for LSP
function M.build_lsp_args(config)
  return M.build_env_args(config, 'lsp')
end

-- Detect language from devcontainer configuration
function M.detect_language(config)
  if not config then
    return nil
  end

  -- Check if language preset is explicitly specified
  if
    config.customizations
    and config.customizations['container.nvim']
    and config.customizations['container.nvim'].languagePreset
  then
    return config.customizations['container.nvim'].languagePreset
  end

  -- Try to detect from image name
  if config.image then
    local image = config.image:lower()
    if image:match('go') then
      return 'go'
    elseif image:match('python') then
      return 'python'
    elseif image:match('node') or image:match('javascript') or image:match('typescript') then
      return 'node'
    elseif image:match('rust') then
      return 'rust'
    end
  end

  -- Try to detect from features
  if config.features then
    for feature, _ in pairs(config.features) do
      if feature:match('go') then
        return 'go'
      elseif feature:match('python') then
        return 'python'
      elseif feature:match('node') then
        return 'node'
      elseif feature:match('rust') then
        return 'rust'
      end
    end
  end

  return nil
end

-- Get all available language presets
function M.get_available_presets()
  local presets = {}
  for name, _ in pairs(language_presets) do
    if name ~= 'default' then
      table.insert(presets, name)
    end
  end
  table.sort(presets)
  return presets
end

-- Validate environment configuration
function M.validate_environment(config)
  local errors = {}

  -- Validate standard environment variables
  local standard_env_contexts = { 'containerEnv', 'remoteEnv' }
  for _, context in ipairs(standard_env_contexts) do
    if config[context] then
      for key, value in pairs(config[context]) do
        -- Check for valid environment variable names
        if not key:match('^[A-Za-z_][A-Za-z0-9_]*$') then
          table.insert(errors, string.format('Invalid environment variable name in %s: %s', context, key))
        end
        -- Check for string values
        if type(value) ~= 'string' then
          table.insert(
            errors,
            string.format('Environment variable value must be a string in %s: %s=%s', context, key, tostring(value))
          )
        end
      end
    end
  end

  -- Validate legacy custom environment variables
  if config.customizations and config.customizations['container.nvim'] then
    local customizations = config.customizations['container.nvim']

    -- Validate language preset
    if customizations.languagePreset and not language_presets[customizations.languagePreset] then
      table.insert(
        errors,
        string.format(
          'Unknown language preset: %s. Available presets: %s',
          customizations.languagePreset,
          table.concat(M.get_available_presets(), ', ')
        )
      )
    end

    -- Validate legacy environment variable names
    local env_contexts = { 'postCreateEnvironment', 'execEnvironment', 'lspEnvironment', 'additionalEnvironment' }
    for _, context in ipairs(env_contexts) do
      if customizations[context] then
        for key, value in pairs(customizations[context]) do
          -- Check for valid environment variable names
          if not key:match('^[A-Za-z_][A-Za-z0-9_]*$') then
            table.insert(errors, string.format('Invalid environment variable name in %s: %s', context, key))
          end
          -- Check for string values
          if type(value) ~= 'string' then
            table.insert(
              errors,
              string.format('Environment variable value must be a string in %s: %s=%s', context, key, tostring(value))
            )
          end
        end
      end
    end
  end

  return errors
end

return M
