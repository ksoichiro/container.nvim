#!/usr/bin/env lua

-- Comprehensive test script for container.nvim migrate.lua module
-- Tests configuration migration functionality for 70%+ coverage improvement

-- Add project lua directory to package path
package.path = './lua/?.lua;./lua/?/init.lua;../lua/?.lua;../lua/?/init.lua;' .. package.path

-- Mock vim global for testing
_G.vim = {
  deepcopy = function(obj)
    if type(obj) ~= 'table' then
      return obj
    end
    local copy = {}
    for k, v in pairs(obj) do
      copy[k] = vim.deepcopy(v)
    end
    return copy
  end,
  tbl_isempty = function(t)
    if type(t) ~= 'table' then
      return true
    end
    return next(t) == nil
  end,
  list_extend = function(list1, list2)
    for _, item in ipairs(list2) do
      table.insert(list1, item)
    end
    return list1
  end,
  log = { levels = { DEBUG = 1, INFO = 2, WARN = 3, ERROR = 4 } },
  notify = function(msg, level) end,
}

-- Mock log module
local mock_log = {
  info = function(msg, ...)
    -- Mock log.info call
  end,
  debug = function(msg, ...)
    -- Mock log.debug call
  end,
  warn = function(msg, ...)
    -- Mock log.warn call
  end,
  error = function(msg, ...)
    -- Mock log.error call
  end,
}

-- Override package.loaded to inject mock
package.loaded['container.utils.log'] = mock_log

-- Test functions
local function test_has_legacy_env_settings()
  print('=== Testing has_legacy_env_settings ===')

  local migrate = require('container.migrate')

  -- Test config without customizations
  local config1 = {}
  local result1 = migrate.needs_migration(config1)
  if not result1 then
    print('✓ Config without customizations returns false')
  else
    print('✗ Config without customizations should return false')
    return false
  end

  -- Test config without container.nvim customizations
  local config2 = {
    customizations = {
      codespaces = {},
    },
  }
  local result2 = migrate.needs_migration(config2)
  if not result2 then
    print('✓ Config without container.nvim customizations returns false')
  else
    print('✗ Config without container.nvim customizations should return false')
    return false
  end

  -- Test config with container.nvim but no legacy settings
  local config3 = {
    customizations = {
      ['container.nvim'] = {
        someOtherSetting = true,
      },
    },
  }
  local result3 = migrate.needs_migration(config3)
  if not result3 then
    print('✓ Config with container.nvim but no legacy settings returns false')
  else
    print('✗ Config with container.nvim but no legacy settings should return false')
    return false
  end

  -- Test config with postCreateEnvironment
  local config4 = {
    customizations = {
      ['container.nvim'] = {
        postCreateEnvironment = {
          MY_VAR = 'value',
        },
      },
    },
  }
  local result4 = migrate.needs_migration(config4)
  if result4 then
    print('✓ Config with postCreateEnvironment returns true')
  else
    print('✗ Config with postCreateEnvironment should return true')
    return false
  end

  -- Test config with execEnvironment
  local config5 = {
    customizations = {
      ['container.nvim'] = {
        execEnvironment = {
          MY_VAR = 'value',
        },
      },
    },
  }
  local result5 = migrate.needs_migration(config5)
  if result5 then
    print('✓ Config with execEnvironment returns true')
  else
    print('✗ Config with execEnvironment should return true')
    return false
  end

  -- Test config with lspEnvironment
  local config6 = {
    customizations = {
      ['container.nvim'] = {
        lspEnvironment = {
          MY_VAR = 'value',
        },
      },
    },
  }
  local result6 = migrate.needs_migration(config6)
  if result6 then
    print('✓ Config with lspEnvironment returns true')
  else
    print('✗ Config with lspEnvironment should return true')
    return false
  end

  -- Test config with additionalEnvironment
  local config7 = {
    customizations = {
      ['container.nvim'] = {
        additionalEnvironment = {
          MY_VAR = 'value',
        },
      },
    },
  }
  local result7 = migrate.needs_migration(config7)
  if result7 then
    print('✓ Config with additionalEnvironment returns true')
  else
    print('✗ Config with additionalEnvironment should return true')
    return false
  end

  return true
end

local function test_migrate_environment_settings()
  print('\n=== Testing migrate_environment_settings ===')

  local migrate = require('container.migrate')

  -- Test config without legacy settings
  local config1 = {
    customizations = {
      ['container.nvim'] = {
        someOtherSetting = true,
      },
    },
  }
  local migrated1, changes1 = migrate.auto_migrate_config(config1)
  if #changes1 == 0 then
    print('✓ Config without legacy settings returns no changes')
  else
    print('✗ Config without legacy settings should return no changes')
    return false
  end

  -- Test migration of postCreateEnvironment
  local config2 = {
    customizations = {
      ['container.nvim'] = {
        postCreateEnvironment = {
          BUILD_VAR = 'build_value',
          SHARED_VAR = 'original_value',
        },
      },
    },
  }
  local migrated2, changes2 = migrate.auto_migrate_config(config2)
  if migrated2.containerEnv and migrated2.containerEnv.BUILD_VAR == 'build_value' then
    print('✓ postCreateEnvironment migrated to containerEnv')
  else
    print('✗ postCreateEnvironment not properly migrated to containerEnv')
    return false
  end

  if
    not migrated2.customizations
    or not migrated2.customizations['container.nvim']
    or migrated2.customizations['container.nvim'].postCreateEnvironment == nil
  then
    print('✓ postCreateEnvironment removed from customizations')
  else
    print('✗ postCreateEnvironment not removed from customizations')
    return false
  end

  if #changes2 == 1 and changes2[1]:match('postCreateEnvironment') then
    print('✓ Migration change recorded for postCreateEnvironment')
  else
    print('✗ Migration change not properly recorded for postCreateEnvironment')
    return false
  end

  -- Test migration of execEnvironment
  local config3 = {
    customizations = {
      ['container.nvim'] = {
        execEnvironment = {
          EXEC_VAR = 'exec_value',
        },
      },
    },
  }
  local migrated3, changes3 = migrate.auto_migrate_config(config3)
  if migrated3.remoteEnv and migrated3.remoteEnv.EXEC_VAR == 'exec_value' then
    print('✓ execEnvironment migrated to remoteEnv')
  else
    print('✗ execEnvironment not properly migrated to remoteEnv')
    return false
  end

  -- Test migration of lspEnvironment
  local config4 = {
    customizations = {
      ['container.nvim'] = {
        lspEnvironment = {
          LSP_VAR = 'lsp_value',
        },
      },
    },
  }
  local migrated4, changes4 = migrate.auto_migrate_config(config4)
  if migrated4.remoteEnv and migrated4.remoteEnv.LSP_VAR == 'lsp_value' then
    print('✓ lspEnvironment migrated to remoteEnv')
  else
    print('✗ lspEnvironment not properly migrated to remoteEnv')
    return false
  end

  -- Test migration of additionalEnvironment
  local config5 = {
    customizations = {
      ['container.nvim'] = {
        additionalEnvironment = {
          ADD_VAR = 'add_value',
        },
      },
    },
  }
  local migrated5, changes5 = migrate.auto_migrate_config(config5)
  if migrated5.remoteEnv and migrated5.remoteEnv.ADD_VAR == 'add_value' then
    print('✓ additionalEnvironment migrated to remoteEnv')
  else
    print('✗ additionalEnvironment not properly migrated to remoteEnv')
    return false
  end

  -- Test migration with existing containerEnv and remoteEnv (should not overwrite)
  local config6 = {
    containerEnv = {
      EXISTING_CONTAINER = 'existing_value',
    },
    remoteEnv = {
      EXISTING_REMOTE = 'existing_value',
    },
    customizations = {
      ['container.nvim'] = {
        postCreateEnvironment = {
          NEW_VAR = 'new_value',
          EXISTING_CONTAINER = 'should_not_overwrite',
        },
        execEnvironment = {
          EXEC_VAR = 'exec_value',
          EXISTING_REMOTE = 'should_not_overwrite',
        },
      },
    },
  }
  local migrated6, changes6 = migrate.auto_migrate_config(config6)
  if
    migrated6.containerEnv.EXISTING_CONTAINER == 'existing_value' and migrated6.containerEnv.NEW_VAR == 'new_value'
  then
    print('✓ Existing containerEnv preserved, new values added')
  else
    print('✗ Existing containerEnv not properly preserved')
    return false
  end

  if migrated6.remoteEnv.EXISTING_REMOTE == 'existing_value' and migrated6.remoteEnv.EXEC_VAR == 'exec_value' then
    print('✓ Existing remoteEnv preserved, new values added')
  else
    print('✗ Existing remoteEnv not properly preserved')
    return false
  end

  -- Test complete migration with multiple environment types
  local config7 = {
    customizations = {
      ['container.nvim'] = {
        postCreateEnvironment = {
          BUILD_VAR = 'build_value',
        },
        execEnvironment = {
          EXEC_VAR = 'exec_value',
        },
        lspEnvironment = {
          LSP_VAR = 'lsp_value',
        },
        additionalEnvironment = {
          ADD_VAR = 'add_value',
        },
      },
    },
  }
  local migrated7, changes7 = migrate.auto_migrate_config(config7)
  if #changes7 == 4 then
    print('✓ All four environment types migrated')
  else
    print('✗ Not all environment types migrated: ' .. #changes7 .. ' changes')
    return false
  end

  if
    migrated7.containerEnv.BUILD_VAR == 'build_value'
    and migrated7.remoteEnv.EXEC_VAR == 'exec_value'
    and migrated7.remoteEnv.LSP_VAR == 'lsp_value'
    and migrated7.remoteEnv.ADD_VAR == 'add_value'
  then
    print('✓ All environment variables correctly placed')
  else
    print('✗ Environment variables not correctly placed')
    return false
  end

  -- Test cleanup of empty customizations
  if migrated7.customizations == nil then
    print('✓ Empty customizations cleaned up')
  else
    print('✗ Empty customizations not cleaned up')
    return false
  end

  return true
end

local function test_auto_migrate_config()
  print('\n=== Testing auto_migrate_config ===')

  local migrate = require('container.migrate')

  -- Test nil config
  local migrated1, changes1 = migrate.auto_migrate_config(nil)
  if migrated1 == nil and #changes1 == 0 then
    print('✓ Nil config handled correctly')
  else
    print('✗ Nil config not handled correctly')
    return false
  end

  -- Test config with no changes needed
  local config2 = {
    containerEnv = { VAR = 'value' },
    remoteEnv = { VAR2 = 'value2' },
  }
  local migrated2, changes2 = migrate.auto_migrate_config(config2)
  if #changes2 == 0 and migrated2._auto_migrated == nil then
    print('✓ Config with no changes returns unchanged')
  else
    print('✗ Config with no changes not handled correctly')
    return false
  end

  -- Test config that needs migration
  local config3 = {
    customizations = {
      ['container.nvim'] = {
        postCreateEnvironment = {
          VAR = 'value',
        },
      },
    },
  }
  local migrated3, changes3 = migrate.auto_migrate_config(config3)
  if #changes3 > 0 and migrated3._auto_migrated == true then
    print('✓ Config with changes marked as auto-migrated')
  else
    print('✗ Config with changes not properly marked as auto-migrated')
    return false
  end

  return true
end

local function test_generate_migration_suggestions()
  print('\n=== Testing generate_migration_suggestions ===')

  local migrate = require('container.migrate')

  -- Test nil config
  local suggestions1 = migrate.generate_migration_suggestions(nil)
  if #suggestions1 == 0 then
    print('✓ Nil config returns empty suggestions')
  else
    print('✗ Nil config should return empty suggestions')
    return false
  end

  -- Test config without legacy settings
  local config2 = {
    containerEnv = { VAR = 'value' },
  }
  local suggestions2 = migrate.generate_migration_suggestions(config2)
  if #suggestions2 == 0 then
    print('✓ Config without legacy settings returns empty suggestions')
  else
    print('✗ Config without legacy settings should return empty suggestions')
    return false
  end

  -- Test config with legacy settings
  local config3 = {
    customizations = {
      ['container.nvim'] = {
        postCreateEnvironment = {
          VAR = 'value',
        },
      },
    },
  }
  local suggestions3 = migrate.generate_migration_suggestions(config3)
  if
    #suggestions3 == 1
    and suggestions3[1].type == 'environment'
    and suggestions3[1].priority == 'high'
    and suggestions3[1].message:match('migrating')
  then
    print('✓ Config with legacy settings returns appropriate suggestion')
  else
    print('✗ Config with legacy settings not generating correct suggestion')
    return false
  end

  return true
end

local function test_get_migration_status()
  print('\n=== Testing get_migration_status ===')

  local migrate = require('container.migrate')

  -- Test nil config
  local status1 = migrate.get_migration_status(nil)
  if status1 == 'No configuration found' then
    print('✓ Nil config returns appropriate status')
  else
    print('✗ Nil config should return "No configuration found"')
    return false
  end

  -- Test config that was auto-migrated
  local config2 = {
    _auto_migrated = true,
    containerEnv = { VAR = 'value' },
  }
  local status2 = migrate.get_migration_status(config2)
  if status2:match('auto%-migrated') then
    print('✓ Auto-migrated config returns appropriate status')
  else
    print('✗ Auto-migrated config status not correct')
    return false
  end

  -- Test config that needs migration
  local config3 = {
    customizations = {
      ['container.nvim'] = {
        postCreateEnvironment = {
          VAR = 'value',
        },
      },
    },
  }
  local status3 = migrate.get_migration_status(config3)
  if status3:match('legacy format') then
    print('✓ Config needing migration returns appropriate status')
  else
    print('✗ Config needing migration status not correct')
    return false
  end

  -- Test standards-compliant config
  local config4 = {
    containerEnv = { VAR = 'value' },
    remoteEnv = { VAR2 = 'value2' },
  }
  local status4 = migrate.get_migration_status(config4)
  if status4:match('standards%-compliant') then
    print('✓ Standards-compliant config returns appropriate status')
  else
    print('✗ Standards-compliant config status not correct')
    return false
  end

  return true
end

local function test_edge_cases()
  print('\n=== Testing edge cases ===')

  local migrate = require('container.migrate')

  -- Test config with empty legacy environment
  local config1 = {
    customizations = {
      ['container.nvim'] = {
        postCreateEnvironment = {},
      },
    },
  }
  local migrated1, changes1 = migrate.auto_migrate_config(config1)
  if #changes1 == 1 then
    print('✓ Empty legacy environment still triggers migration')
  else
    print('✗ Empty legacy environment should still trigger migration')
    return false
  end

  -- Test config with nil values in legacy environment
  local config2 = {
    customizations = {
      ['container.nvim'] = {
        execEnvironment = {
          VAR1 = 'value1',
          VAR2 = nil,
        },
      },
    },
  }
  local migrated2, changes2 = migrate.auto_migrate_config(config2)
  if migrated2.remoteEnv.VAR1 == 'value1' and migrated2.remoteEnv.VAR2 == nil then
    print('✓ Nil values handled correctly in migration')
  else
    print('✗ Nil values not handled correctly in migration')
    return false
  end

  -- Test config with nested customizations that should be preserved
  local config3 = {
    customizations = {
      ['container.nvim'] = {
        postCreateEnvironment = {
          VAR = 'value',
        },
        otherSetting = 'should_be_preserved',
      },
      ['other.extension'] = {
        setting = 'should_also_be_preserved',
      },
    },
  }
  local migrated3, changes3 = migrate.auto_migrate_config(config3)
  if
    migrated3.customizations
    and migrated3.customizations['container.nvim']
    and migrated3.customizations['container.nvim'].otherSetting == 'should_be_preserved'
    and migrated3.customizations['other.extension']
    and migrated3.customizations['other.extension'].setting == 'should_also_be_preserved'
  then
    print('✓ Non-legacy customizations preserved during migration')
  else
    print('✗ Non-legacy customizations not preserved during migration')
    return false
  end

  -- Test partial cleanup - only container.nvim should be removed if empty
  local config4 = {
    customizations = {
      ['container.nvim'] = {
        postCreateEnvironment = {
          VAR = 'value',
        },
      },
      ['other.extension'] = {
        setting = 'preserve',
      },
    },
  }
  local migrated4, changes4 = migrate.auto_migrate_config(config4)
  if
    (not migrated4.customizations or not migrated4.customizations['container.nvim'])
    and migrated4.customizations
    and migrated4.customizations['other.extension']
    and migrated4.customizations['other.extension'].setting == 'preserve'
  then
    print('✓ Partial cleanup works correctly')
  else
    print('✗ Partial cleanup not working correctly')
    return false
  end

  return true
end

local function test_multiple_migrations()
  print('\n=== Testing multiple migrations ===')

  local migrate = require('container.migrate')

  -- Test running migration twice on the same config
  local config = {
    customizations = {
      ['container.nvim'] = {
        postCreateEnvironment = {
          VAR = 'value',
        },
      },
    },
  }

  local migrated1, changes1 = migrate.auto_migrate_config(config)
  local migrated2, changes2 = migrate.auto_migrate_config(migrated1)

  if #changes1 > 0 and #changes2 == 0 then
    print('✓ Second migration returns no changes')
  else
    print('✗ Second migration should return no changes')
    return false
  end

  if migrated2._auto_migrated == true then
    print('✓ Auto-migrated flag preserved')
  else
    print('✗ Auto-migrated flag not preserved')
    return false
  end

  return true
end

-- Main test runner
local function run_tests()
  print('Starting container.nvim migrate.lua comprehensive tests...\n')

  local tests = {
    test_has_legacy_env_settings,
    test_migrate_environment_settings,
    test_auto_migrate_config,
    test_generate_migration_suggestions,
    test_get_migration_status,
    test_edge_cases,
    test_multiple_migrations,
  }

  local passed = 0
  local total = #tests

  for _, test in ipairs(tests) do
    local success = test()
    if success then
      passed = passed + 1
    end
  end

  print(string.format('\n=== Test Results ==='))
  print(string.format('Passed: %d/%d', passed, total))

  if passed == total then
    print('All tests passed! ✓')
    return 0
  else
    print('Some tests failed! ✗')
    return 1
  end
end

-- Run tests
local exit_code = run_tests()
os.exit(exit_code)
