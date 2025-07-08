-- lua/container/lsp/strategy.lua
-- LSP Strategy Selector
-- Chooses the appropriate LSP strategy based on configuration

local M = {}
local log = require('container.utils.log')

-- Available LSP strategies
local STRATEGIES = {
  INTERCEPT = 'intercept', -- Strategy C: Host-side message interception
}

-- Default strategy configuration
local DEFAULT_STRATEGY_CONFIG = {
  -- Global default strategy
  default = STRATEGIES.INTERCEPT,

  -- Server-specific strategy overrides
  servers = {
    gopls = STRATEGIES.INTERCEPT, -- Go: Use interception for reliable path handling
    pylsp = STRATEGIES.INTERCEPT, -- Python: Use interception
    tsserver = STRATEGIES.INTERCEPT, -- TypeScript: Use interception
    rust_analyzer = STRATEGIES.INTERCEPT, -- Rust: Use interception
  },

  -- Fallback behavior when strategy fails
  fallback = {
    enabled = true,
    strategy = STRATEGIES.INTERCEPT, -- Fall back to intercept if primary fails
    max_retries = 2,
  },

  -- Feature flags for strategy selection
  features = {
    auto_detection = true, -- Auto-detect best strategy
    prefer_performance = true, -- Prefer faster strategy when available
    enable_hybrid = false, -- Allow mixed strategies (future)
  },
}

-- Current strategy configuration
local strategy_config = vim.tbl_deep_extend('force', {}, DEFAULT_STRATEGY_CONFIG)

-- Strategy implementation modules
local strategy_implementations = {}

-- Initialize strategy selector
-- @param config table|nil: strategy configuration overrides
function M.setup(config)
  -- Load configuration from configs.lua first
  local configs = require('container.lsp.configs')
  local config_from_file = configs.get_strategy_config()

  -- Merge: default -> file config -> user config
  strategy_config = vim.tbl_deep_extend('force', DEFAULT_STRATEGY_CONFIG, config_from_file, config or {})

  -- Load strategy implementations
  strategy_implementations = {
    [STRATEGIES.INTERCEPT] = require('container.lsp.strategies.intercept'),
  }

  log.info('Strategy Selector: Initialized with default strategy: %s', strategy_config.default)
  log.info(
    'Strategy Selector: Loaded strategy implementations: %s',
    vim.inspect(vim.tbl_keys(strategy_implementations))
  )
  log.debug('Strategy Selector: Final strategy config: %s', vim.inspect(strategy_config))
end

-- Determine the best strategy for a given LSP server
-- @param server_name string: LSP server name (e.g., 'gopls', 'pylsp')
-- @param container_id string: target container ID
-- @param config table|nil: additional configuration
-- @return string: chosen strategy name
-- @return table: strategy-specific configuration
function M.select_strategy(server_name, container_id, config)
  log.info('Strategy Selector: Selecting strategy for %s in container %s', server_name, container_id)
  log.debug('Strategy Selector: Available strategies: %s', vim.inspect(vim.tbl_keys(strategy_implementations)))
  log.debug('Strategy Selector: Current strategy config: %s', vim.inspect(strategy_config))

  local chosen_strategy = strategy_config.default
  local strategy_specific_config = {}

  log.info('Strategy Selector: Default strategy: %s', chosen_strategy)

  -- Check server-specific override
  if strategy_config.servers[server_name] then
    chosen_strategy = strategy_config.servers[server_name]
    log.info('Strategy Selector: Using server-specific strategy for %s: %s', server_name, chosen_strategy)
  end

  -- Auto-detection logic (if enabled)
  if strategy_config.features.auto_detection then
    log.debug('Strategy Selector: Auto-detection enabled, checking...')
    local detected_strategy = M._auto_detect_strategy(server_name, container_id)
    if detected_strategy then
      chosen_strategy = detected_strategy
      log.info('Strategy Selector: Auto-detected strategy for %s: %s', server_name, chosen_strategy)
    else
      log.debug('Strategy Selector: No auto-detected strategy for %s', server_name)
    end
  end

  -- Validate strategy availability
  if not strategy_implementations[chosen_strategy] then
    log.error(
      'Strategy Selector: Strategy %s not available, falling back to %s',
      chosen_strategy,
      strategy_config.fallback.strategy
    )
    chosen_strategy = strategy_config.fallback.strategy
  else
    log.info('Strategy Selector: Strategy %s is available', chosen_strategy)
  end

  -- Get strategy-specific configuration
  strategy_specific_config = M._get_strategy_config(chosen_strategy, server_name, config)

  log.info(
    'Strategy Selector: Final selected %s strategy for %s in container %s',
    chosen_strategy,
    server_name,
    container_id
  )

  return chosen_strategy, strategy_specific_config
end

-- Create LSP client using the selected strategy
-- @param strategy string: strategy name
-- @param server_name string: LSP server name
-- @param container_id string: container ID
-- @param server_config table: LSP server configuration
-- @param strategy_config table: strategy-specific configuration
-- @return table|nil: LSP client configuration or nil on error
function M.create_client_with_strategy(strategy, server_name, container_id, server_config, strategy_config)
  local implementation = strategy_implementations[strategy]
  if not implementation then
    log.error('Strategy Selector: Implementation not found for strategy: %s', strategy)
    return nil
  end

  log.debug('Strategy Selector: Creating client with %s strategy', strategy)

  -- Attempt to create client with chosen strategy
  local client_config, err = implementation.create_client(server_name, container_id, server_config, strategy_config)

  if client_config then
    -- Add strategy metadata to client config
    client_config._container_strategy = strategy
    client_config._container_metadata = {
      strategy = strategy,
      server_name = server_name,
      container_id = container_id,
      created_at = os.time(),
    }

    log.info('Strategy Selector: Successfully created client with %s strategy', strategy)
    return client_config
  end

  -- Handle strategy failure
  log.error('Strategy Selector: Failed to create client with %s strategy: %s', strategy, err or 'unknown error')

  -- Attempt fallback if enabled
  if strategy_config.fallback.enabled and strategy ~= strategy_config.fallback.strategy then
    log.info('Strategy Selector: Attempting fallback to %s strategy', strategy_config.fallback.strategy)
    return M.create_client_with_strategy(
      strategy_config.fallback.strategy,
      server_name,
      container_id,
      server_config,
      strategy_config
    )
  end

  return nil
end

-- Setup path transformation for a client using its strategy
-- @param client table: LSP client object
-- @param server_name string: LSP server name
-- @param container_id string: container ID
function M.setup_path_transformation(client, server_name, container_id)
  local strategy = client.config._container_strategy
  if not strategy then
    log.warn('Strategy Selector: No strategy metadata found for client, skipping path transformation')
    return
  end

  local implementation = strategy_implementations[strategy]
  if not implementation or not implementation.setup_path_transformation then
    log.warn('Strategy Selector: Path transformation not supported for strategy: %s', strategy)
    return
  end

  log.debug('Strategy Selector: Setting up path transformation with %s strategy', strategy)
  implementation.setup_path_transformation(client, server_name, container_id)
end

-- Get health information for all strategies
-- @return table: health status for each strategy
function M.health_check()
  local health = {
    current_config = strategy_config,
    strategies = {},
    overall_healthy = true,
  }

  for strategy_name, implementation in pairs(strategy_implementations) do
    local strategy_health = {
      available = true,
      healthy = true,
      issues = {},
    }

    -- Check if implementation has health check
    if implementation.health_check then
      local impl_health = implementation.health_check()
      strategy_health = vim.tbl_extend('force', strategy_health, impl_health)
    end

    health.strategies[strategy_name] = strategy_health

    if not strategy_health.healthy then
      health.overall_healthy = false
    end
  end

  return health
end

-- Private: Auto-detect the best strategy for a server
-- @param server_name string: LSP server name
-- @param container_id string: container ID
-- @return string|nil: detected strategy or nil
function M._auto_detect_strategy(server_name, container_id)
  -- Auto-detection logic based on server capabilities and container environment

  -- Currently prefer intercept strategy for most reliable behavior
  -- The intercept strategy provides the most comprehensive path transformation
  -- and is compatible with all LSP servers

  if server_name == 'gopls' then
    -- Use intercept strategy for Go projects - provides better diagnostics handling
    return STRATEGIES.INTERCEPT
  end

  -- For other servers, also use intercept strategy by default
  -- as it's the most reliable and well-tested approach
  return STRATEGIES.INTERCEPT
end

-- Private: Get strategy-specific configuration
-- @param strategy string: strategy name
-- @param server_name string: LSP server name
-- @param config table|nil: additional configuration
-- @return table: strategy configuration
function M._get_strategy_config(strategy, server_name, config)
  local base_config = {
    server_name = server_name,
    strategy = strategy,
  }

  -- No strategy-specific configuration needed for intercept

  return vim.tbl_deep_extend('force', base_config, config or {})
end

-- Update strategy configuration
-- @param config table: new configuration
function M.update_config(config)
  strategy_config = vim.tbl_deep_extend('force', strategy_config, config)
  log.info('Strategy Selector: Configuration updated')
end

-- Get current strategy configuration
-- @return table: current configuration
function M.get_config()
  return vim.tbl_deep_extend('force', {}, strategy_config)
end

-- Get available strategies
-- @return table: list of available strategy names
function M.get_available_strategies()
  return vim.tbl_keys(strategy_implementations)
end

-- Check if a strategy is available
-- @param strategy string: strategy name
-- @return boolean: true if available
function M.is_strategy_available(strategy)
  return strategy_implementations[strategy] ~= nil
end

-- Constants for external use
M.STRATEGIES = STRATEGIES

return M
