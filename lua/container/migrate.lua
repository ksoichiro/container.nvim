-- lua/container/migrate.lua
-- Configuration migration utilities for standards compliance

local M = {}

local log = require('container.utils.log')

-- Check if config has legacy environment settings
local function has_legacy_env_settings(config)
  if not config or not config.customizations or not config.customizations['container.nvim'] then
    return false
  end

  local customizations = config.customizations['container.nvim']
  return customizations.postCreateEnvironment
    or customizations.execEnvironment
    or customizations.lspEnvironment
    or customizations.additionalEnvironment
end

-- Migrate legacy environment settings to standard format
local function migrate_environment_settings(config)
  if not has_legacy_env_settings(config) then
    return config, {}
  end

  local migrated = vim.deepcopy(config)
  local changes = {}
  local customizations = config.customizations['container.nvim']

  -- Initialize standard environment variables if not present
  migrated.containerEnv = migrated.containerEnv or {}
  migrated.remoteEnv = migrated.remoteEnv or {}

  -- Migrate postCreateEnvironment to containerEnv (used during container creation)
  if customizations.postCreateEnvironment then
    for key, value in pairs(customizations.postCreateEnvironment) do
      if not migrated.containerEnv[key] then
        migrated.containerEnv[key] = value
      end
    end
    -- Remove from customizations
    migrated.customizations['container.nvim'].postCreateEnvironment = nil
    table.insert(changes, 'Migrated postCreateEnvironment to containerEnv')
  end

  -- Migrate execEnvironment and lspEnvironment to remoteEnv (used during runtime)
  if customizations.execEnvironment then
    for key, value in pairs(customizations.execEnvironment) do
      if not migrated.remoteEnv[key] then
        migrated.remoteEnv[key] = value
      end
    end
    migrated.customizations['container.nvim'].execEnvironment = nil
    table.insert(changes, 'Migrated execEnvironment to remoteEnv')
  end

  if customizations.lspEnvironment then
    for key, value in pairs(customizations.lspEnvironment) do
      if not migrated.remoteEnv[key] then
        migrated.remoteEnv[key] = value
      end
    end
    migrated.customizations['container.nvim'].lspEnvironment = nil
    table.insert(changes, 'Migrated lspEnvironment to remoteEnv')
  end

  -- Migrate additionalEnvironment to remoteEnv
  if customizations.additionalEnvironment then
    for key, value in pairs(customizations.additionalEnvironment) do
      if not migrated.remoteEnv[key] then
        migrated.remoteEnv[key] = value
      end
    end
    migrated.customizations['container.nvim'].additionalEnvironment = nil
    table.insert(changes, 'Migrated additionalEnvironment to remoteEnv')
  end

  -- Clean up empty customizations
  if vim.tbl_isempty(migrated.customizations['container.nvim']) then
    migrated.customizations['container.nvim'] = nil
  end
  if vim.tbl_isempty(migrated.customizations) then
    migrated.customizations = nil
  end

  return migrated, changes
end

-- Auto-migrate configuration to standards-compliant format
function M.auto_migrate_config(config)
  if not config then
    return config, {}
  end

  local migrated = vim.deepcopy(config)
  local all_changes = {}

  -- Migrate environment settings
  local env_migrated, env_changes = migrate_environment_settings(migrated)
  migrated = env_migrated
  vim.list_extend(all_changes, env_changes)

  -- Mark as migrated to avoid repeated warnings
  if #all_changes > 0 then
    migrated._auto_migrated = true
    log.info('Auto-migrated configuration to standards-compliant format')
    for _, change in ipairs(all_changes) do
      log.debug('Migration: %s', change)
    end
  end

  return migrated, all_changes
end

-- Generate migration suggestions
function M.generate_migration_suggestions(config)
  if not config then
    return {}
  end

  local suggestions = {}

  if has_legacy_env_settings(config) then
    table.insert(suggestions, {
      type = 'environment',
      message = 'Consider migrating custom environment settings to standard containerEnv/remoteEnv',
      priority = 'high',
      action = 'Use :ContainerMigrateConfig command to auto-migrate',
    })
  end

  return suggestions
end

-- Check if configuration needs migration
function M.needs_migration(config)
  return has_legacy_env_settings(config)
end

-- Get migration status message
function M.get_migration_status(config)
  if not config then
    return 'No configuration found'
  end

  if config._auto_migrated then
    return 'Configuration was auto-migrated to standards-compliant format'
  end

  if M.needs_migration(config) then
    return 'Configuration uses legacy format - consider migrating to standards-compliant format'
  end

  return 'Configuration uses standards-compliant format'
end

return M
