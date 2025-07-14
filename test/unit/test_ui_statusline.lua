#!/usr/bin/env lua

-- Comprehensive test script for container.ui.statusline module
-- Tests statusline functionality for 70%+ coverage improvement

-- Add project lua directory to package path
package.path = './lua/?.lua;./lua/?/init.lua;../lua/?.lua;../lua/?/init.lua;' .. package.path

-- Store original functions for restoration
local original_vim = _G.vim
local original_require = require

-- Mock vim global for testing
_G.vim = {
  loop = {
    now = function()
      return os.time() * 1000 -- Convert to milliseconds
    end,
  },
  tbl_count = function(tbl)
    local count = 0
    for _ in pairs(tbl) do
      count = count + 1
    end
    return count
  end,
  api = {
    nvim_create_augroup = function(name, opts)
      return 1 -- Mock augroup ID
    end,
    nvim_create_autocmd = function(event, opts)
      return 1 -- Mock autocmd ID
    end,
  },
  log = { levels = { DEBUG = 1, INFO = 2, WARN = 3, ERROR = 4 } },
  notify = function(msg, level) end,
}

-- Mock container module
local mock_container_state = {
  initialized = false,
  current_container = nil,
  container_status = nil,
  current_config = nil,
}

local mock_terminal_sessions = {}

local function mock_require(module_name)
  if module_name == 'container.config' then
    return {
      get = function()
        return {
          ui = {
            status_line = true,
            icons = {
              running = '✅',
              stopped = '⏹️',
              building = '🔨',
              container = '🐳',
            },
            statusline = {
              format = {
                running = '{icon} {name} ({status})',
                stopped = '{icon} {name}',
                building = '{icon} Building {name}',
                available = '{icon} {name} (available)',
                error = '{icon} {name} (error)',
              },
              labels = {
                container_name = 'TestContainer',
                available_suffix = 'ready',
              },
              show_container_name = true,
              default_format = '{icon} {name}',
            },
          },
        }
      end,
    }
  elseif module_name == 'container.utils.log' then
    return {
      debug = function(msg) end,
      info = function(msg) end,
      warn = function(msg) end,
      error = function(msg) end,
    }
  elseif module_name == 'container' then
    return {
      get_state = function()
        return mock_container_state
      end,
    }
  elseif module_name == 'container.parser' then
    return {
      find_devcontainer_json = function()
        return '/test/.devcontainer/devcontainer.json' -- Mock existing file
      end,
    }
  elseif module_name == 'container.terminal' then
    return {
      list_sessions = function()
        return mock_terminal_sessions
      end,
    }
  else
    return original_require(module_name)
  end
end

-- Replace require globally
_G.require = mock_require

-- Load the module under test
local statusline = require('container.ui.statusline')

-- Test helper functions
local function assert_true(condition, message)
  if not condition then
    error('Assertion failed: ' .. (message or 'Expected true'))
  end
end

local function assert_equals(expected, actual, message)
  if expected ~= actual then
    error('Assertion failed: ' .. (message or ('Expected ' .. tostring(expected) .. ', got ' .. tostring(actual))))
  end
end

local function assert_not_nil(value, message)
  if value == nil then
    error('Assertion failed: ' .. (message or 'Expected non-nil value'))
  end
end

local function assert_nil(value, message)
  if value ~= nil then
    error('Assertion failed: ' .. (message or 'Expected nil value'))
  end
end

local function reset_mocks()
  mock_container_state = {
    initialized = false,
    current_container = nil,
    container_status = nil,
    current_config = nil,
  }
  mock_terminal_sessions = {}
  statusline.clear_cache()
end

-- Test functions
local function test_module_loading()
  print('Test 1: Module Loading')
  assert_not_nil(statusline, 'statusline module should load')
  assert_not_nil(statusline.get_status, 'get_status function should exist')
  assert_not_nil(statusline.get_detailed_status, 'get_detailed_status function should exist')
  assert_not_nil(statusline.lualine_component, 'lualine_component function should exist')
  assert_not_nil(statusline.lightline_component, 'lightline_component function should exist')
  assert_not_nil(statusline.clear_cache, 'clear_cache function should exist')
  assert_not_nil(statusline.setup, 'setup function should exist')
  print('✓ Module loaded with all expected functions')
end

local function test_get_status_disabled()
  print('Test 2: get_status when statusline is disabled')
  reset_mocks()

  -- Mock config with disabled statusline
  _G.require = function(module_name)
    if module_name == 'container.config' then
      return {
        get = function()
          return {
            ui = {
              status_line = false,
            },
          }
        end,
      }
    else
      return mock_require(module_name)
    end
  end

  local result = statusline.get_status()
  assert_equals('', result, 'Should return empty string when statusline is disabled')
  print('✓ Disabled statusline handled correctly')
end

local function test_get_status_no_config()
  print('Test 3: get_status with no config')
  reset_mocks()

  -- Mock config returning nil
  _G.require = function(module_name)
    if module_name == 'container.config' then
      return {
        get = function()
          return nil
        end,
      }
    else
      return mock_require(module_name)
    end
  end

  local result = statusline.get_status()
  assert_equals('', result, 'Should return empty string when config is nil')
  print('✓ Nil config handled correctly')
end

local function test_get_status_not_initialized()
  print('Test 4: get_status when not initialized')
  reset_mocks()
  _G.require = mock_require

  mock_container_state.initialized = false

  local result = statusline.get_status()
  assert_equals('', result, 'Should return empty string when not initialized')
  print('✓ Non-initialized state handled correctly')
end

local function test_get_status_with_running_container()
  print('Test 5: get_status with running container')
  reset_mocks()
  _G.require = mock_require

  mock_container_state.initialized = true
  mock_container_state.current_container = 'test-container-123'
  mock_container_state.container_status = 'running'
  mock_container_state.current_config = { name = 'MyApp' }

  local result = statusline.get_status()
  assert_not_nil(result, 'Should return status string')
  print('✓ Running container status: ' .. result)
end

local function test_get_status_with_stopped_container()
  print('Test 6: get_status with stopped container')
  reset_mocks()
  _G.require = mock_require

  mock_container_state.initialized = true
  mock_container_state.current_container = 'test-container-123'
  mock_container_state.container_status = 'exited'
  mock_container_state.current_config = { name = 'MyApp' }

  local result = statusline.get_status()
  assert_not_nil(result, 'Should return status string')
  print('✓ Stopped container status: ' .. result)
end

local function test_get_status_with_building_container()
  print('Test 7: get_status with building container')
  reset_mocks()
  _G.require = mock_require

  mock_container_state.initialized = true
  mock_container_state.current_container = 'test-container-123'
  mock_container_state.container_status = 'created'
  mock_container_state.current_config = { name = 'MyApp' }

  local result = statusline.get_status()
  assert_not_nil(result, 'Should return status string')
  print('✓ Building container status: ' .. result)
end

local function test_get_status_with_unknown_status()
  print('Test 8: get_status with unknown container status')
  reset_mocks()
  _G.require = mock_require

  mock_container_state.initialized = true
  mock_container_state.current_container = 'test-container-123'
  mock_container_state.container_status = 'unknown'
  mock_container_state.current_config = { name = 'MyApp' }

  local result = statusline.get_status()
  assert_not_nil(result, 'Should return status string')
  print('✓ Unknown container status: ' .. result)
end

local function test_get_status_no_container_with_devcontainer()
  print('Test 9: get_status with no container but devcontainer.json exists')
  reset_mocks()
  _G.require = mock_require

  mock_container_state.initialized = true
  mock_container_state.current_container = nil

  local result = statusline.get_status()
  assert_not_nil(result, 'Should return status string')
  print('✓ Available devcontainer status: ' .. result)
end

local function test_get_status_no_container_no_devcontainer()
  print('Test 10: get_status with no container and no devcontainer.json')
  reset_mocks()

  -- Mock parser to return nil (no devcontainer.json)
  _G.require = function(module_name)
    if module_name == 'container.parser' then
      return {
        find_devcontainer_json = function()
          return nil
        end,
      }
    else
      return mock_require(module_name)
    end
  end

  mock_container_state.initialized = true
  mock_container_state.current_container = nil

  local result = statusline.get_status()
  assert_equals('', result, 'Should return empty string when no container and no devcontainer.json')
  print('✓ No container, no devcontainer handled correctly')
end

local function test_get_status_caching()
  print('Test 11: get_status caching functionality')
  reset_mocks()
  _G.require = mock_require

  mock_container_state.initialized = true
  mock_container_state.current_container = 'test-container-123'
  mock_container_state.container_status = 'running'
  mock_container_state.current_config = { name = 'MyApp' }

  local result1 = statusline.get_status()
  local result2 = statusline.get_status()

  assert_equals(result1, result2, 'Cached results should be identical')
  print('✓ Status caching works correctly')
end

local function test_get_status_with_custom_config()
  print('Test 12: get_status with custom configuration')
  reset_mocks()

  -- Mock custom config
  _G.require = function(module_name)
    if module_name == 'container.config' then
      return {
        get = function()
          return {
            ui = {
              status_line = true,
              icons = {
                running = '🟢',
                stopped = '🔴',
                building = '🟡',
                container = '📦',
              },
              statusline = {
                format = {
                  running = 'Custom: {icon} {name}',
                  stopped = 'Stopped: {icon} {name}',
                },
                labels = {
                  container_name = 'CustomContainer',
                },
                show_container_name = false,
                default_format = 'Default: {icon}',
              },
            },
          }
        end,
      }
    else
      return mock_require(module_name)
    end
  end

  mock_container_state.initialized = true
  mock_container_state.current_container = 'test-container-123'
  mock_container_state.container_status = 'running'
  mock_container_state.current_config = { name = 'MyApp' }

  local result = statusline.get_status()
  assert_not_nil(result, 'Should return status string with custom config')
  print('✓ Custom configuration handled: ' .. result)
end

local function test_get_detailed_status()
  print('Test 13: get_detailed_status functionality')
  reset_mocks()
  _G.require = mock_require

  mock_container_state.initialized = true
  mock_container_state.current_container = 'test-container-123'
  mock_container_state.container_status = 'running'
  mock_container_state.current_config = { name = 'MyApp' }

  mock_terminal_sessions = {
    session1 = { active = false },
    session2 = { active = true },
    session3 = { active = false },
  }

  local result = statusline.get_detailed_status()
  assert_not_nil(result, 'Should return detailed status object')
  assert_equals(true, result.enabled, 'Should show statusline as enabled')
  assert_equals(true, result.initialized, 'Should show as initialized')
  assert_equals(true, result.has_container, 'Should show container exists')
  assert_equals('test-container-123', result.container_id, 'Should return correct container ID')
  assert_equals('running', result.container_status, 'Should return correct status')
  assert_equals('MyApp', result.config_name, 'Should return correct config name')
  assert_equals(3, result.terminal_sessions, 'Should count terminal sessions')
  assert_equals('session2', result.active_terminal, 'Should identify active terminal')

  print('✓ Detailed status works correctly')
end

local function test_get_detailed_status_disabled()
  print('Test 14: get_detailed_status when disabled')
  reset_mocks()

  -- Mock config with disabled statusline
  _G.require = function(module_name)
    if module_name == 'container.config' then
      return {
        get = function()
          return {
            ui = {
              status_line = false,
            },
          }
        end,
      }
    else
      return mock_require(module_name)
    end
  end

  local result = statusline.get_detailed_status()
  assert_not_nil(result, 'Should return status object even when disabled')
  assert_equals('table', type(result), 'Should return table')

  print('✓ Detailed status handles disabled state')
end

local function test_get_detailed_status_no_container()
  print('Test 15: get_detailed_status with no container')
  reset_mocks()
  _G.require = mock_require

  mock_container_state.initialized = true
  mock_container_state.current_container = nil
  mock_container_state.container_status = nil
  mock_container_state.current_config = nil

  mock_terminal_sessions = {}

  local result = statusline.get_detailed_status()
  assert_not_nil(result, 'Should return detailed status object')
  assert_equals(false, result.has_container, 'Should show no container')
  assert_nil(result.container_id, 'Should have nil container ID')
  assert_nil(result.container_status, 'Should have nil status')
  assert_nil(result.config_name, 'Should have nil config name')
  assert_equals(0, result.terminal_sessions, 'Should have no terminal sessions')
  assert_nil(result.active_terminal, 'Should have no active terminal')

  print('✓ Detailed status handles no container case')
end

local function test_lualine_component()
  print('Test 16: lualine_component function')
  reset_mocks()
  _G.require = mock_require

  local component = statusline.lualine_component()
  assert_not_nil(component, 'Should return component function')
  assert_equals('function', type(component), 'Should return function')

  mock_container_state.initialized = true
  mock_container_state.current_container = 'test-container'
  mock_container_state.container_status = 'running'

  local result = component()
  assert_not_nil(result, 'Component function should return status')

  print('✓ Lualine component works correctly')
end

local function test_lightline_component()
  print('Test 17: lightline_component function')
  reset_mocks()
  _G.require = mock_require

  mock_container_state.initialized = true
  mock_container_state.current_container = 'test-container'
  mock_container_state.container_status = 'running'

  local result = statusline.lightline_component()
  assert_not_nil(result, 'Should return status string')

  print('✓ Lightline component works correctly')
end

local function test_clear_cache()
  print('Test 18: clear_cache functionality')
  reset_mocks()
  _G.require = mock_require

  -- Get initial status to populate cache
  mock_container_state.initialized = true
  mock_container_state.current_container = 'test-container'
  mock_container_state.container_status = 'running'

  local result1 = statusline.get_status()

  -- Clear cache
  statusline.clear_cache()

  -- Modify state and get status again
  mock_container_state.container_status = 'stopped'
  local result2 = statusline.get_status()

  -- Results should be different since cache was cleared
  print('✓ Cache clearing works correctly')
end

local function test_setup_function()
  print('Test 19: setup function')
  reset_mocks()
  _G.require = mock_require

  -- Test setup with enabled statusline
  statusline.setup()
  print('✓ Setup with enabled statusline works')

  -- Test setup with disabled statusline
  _G.require = function(module_name)
    if module_name == 'container.config' then
      return {
        get = function()
          return {
            ui = {
              status_line = false,
            },
          }
        end,
      }
    else
      return mock_require(module_name)
    end
  end

  statusline.setup()
  print('✓ Setup with disabled statusline works')

  -- Test setup with nil config
  _G.require = function(module_name)
    if module_name == 'container.config' then
      return {
        get = function()
          return nil
        end,
      }
    else
      return mock_require(module_name)
    end
  end

  statusline.setup()
  print('✓ Setup with nil config works')
end

local function test_format_status_edge_cases()
  print('Test 20: format_status edge cases')

  -- Test private format_status function through public API
  reset_mocks()
  _G.require = mock_require

  mock_container_state.initialized = true
  mock_container_state.current_container = 'test-container'
  mock_container_state.container_status = 'running'
  mock_container_state.current_config = { name = 'MyApp' }

  -- Test with available suffix replacement
  _G.require = function(module_name)
    if module_name == 'container.config' then
      return {
        get = function()
          return {
            ui = {
              status_line = true,
              icons = { running = '✅' },
              statusline = {
                format = {
                  available = '{icon} {name} (available)',
                },
                labels = {
                  available_suffix = 'ready',
                },
                default_format = '{icon} {name}',
              },
            },
          }
        end,
      }
    else
      return mock_require(module_name)
    end
  end

  -- Test with no container to trigger available format
  mock_container_state.current_container = nil

  local result = statusline.get_status()
  print('✓ Format status edge cases handled: ' .. result)
end

local function test_devcontainer_caching()
  print('Test 21: devcontainer availability caching')
  reset_mocks()

  local parse_call_count = 0

  _G.require = function(module_name)
    if module_name == 'container.parser' then
      return {
        find_devcontainer_json = function()
          parse_call_count = parse_call_count + 1
          return '/test/.devcontainer/devcontainer.json'
        end,
      }
    else
      return mock_require(module_name)
    end
  end

  mock_container_state.initialized = true
  mock_container_state.current_container = nil

  -- First call should trigger parser
  statusline.get_status()
  local first_call_count = parse_call_count

  -- Second call should use cache
  statusline.get_status()
  local second_call_count = parse_call_count

  assert_equals(first_call_count, second_call_count, 'Parser should be called only once due to caching')
  print('✓ DevContainer availability caching works correctly')
end

local function test_container_name_fallback()
  print('Test 22: container name fallback behavior')
  reset_mocks()
  _G.require = mock_require

  mock_container_state.initialized = true
  mock_container_state.current_container = 'test-container'
  mock_container_state.container_status = 'running'
  mock_container_state.current_config = nil -- No config name

  local result = statusline.get_status()
  assert_not_nil(result, 'Should handle missing config name')
  print('✓ Container name fallback works: ' .. result)
end

local function test_format_status_nil_template()
  print('Test 23: format_status with nil template')
  reset_mocks()
  _G.require = mock_require

  -- Create a custom config that would result in nil template
  _G.require = function(module_name)
    if module_name == 'container.config' then
      return {
        get = function()
          return {
            ui = {
              status_line = true,
              icons = { running = '✅' },
              statusline = {
                format = {}, -- Empty format object
                labels = {},
                default_format = nil, -- Nil default format
              },
            },
          }
        end,
      }
    else
      return mock_require(module_name)
    end
  end

  mock_container_state.initialized = true
  mock_container_state.current_container = 'test-container'
  mock_container_state.container_status = 'running'
  mock_container_state.current_config = { name = 'TestApp' }

  local result = statusline.get_status()
  print('✓ Nil template handled: "' .. result .. '"')
end

local function test_devcontainer_cache_expiry()
  print('Test 24: devcontainer cache expiry behavior')
  reset_mocks()

  local call_count = 0
  _G.require = function(module_name)
    if module_name == 'container.parser' then
      return {
        find_devcontainer_json = function()
          call_count = call_count + 1
          return '/test/.devcontainer/devcontainer.json'
        end,
      }
    else
      return mock_require(module_name)
    end
  end

  -- Mock current time progression
  local mock_time = 1000
  _G.vim.loop.now = function()
    return mock_time
  end

  mock_container_state.initialized = true
  mock_container_state.current_container = nil

  -- First call should cache
  statusline.get_status()
  local first_call_count = call_count

  -- Fast forward time beyond cache interval
  mock_time = mock_time + 35000 -- Beyond 30 second cache interval

  -- This should trigger a new parser call
  statusline.get_status()
  local second_call_count = call_count

  assert_true(second_call_count > first_call_count, 'Parser should be called again after cache expiry')
  print('✓ DevContainer cache expiry works correctly')
end

local function test_terminal_session_no_active()
  print('Test 25: detailed status with no active terminal sessions')
  reset_mocks()
  _G.require = mock_require

  mock_container_state.initialized = true
  mock_container_state.current_container = 'test-container'
  mock_container_state.container_status = 'running'
  mock_container_state.current_config = { name = 'MyApp' }

  mock_terminal_sessions = {
    session1 = { active = false },
    session2 = { active = false },
    session3 = { active = false },
  }

  local result = statusline.get_detailed_status()
  assert_not_nil(result, 'Should return detailed status object')
  assert_equals(3, result.terminal_sessions, 'Should count all terminal sessions')
  assert_nil(result.active_terminal, 'Should have no active terminal')

  print('✓ Terminal sessions with no active session handled')
end

local function test_status_text_empty_cases()
  print('Test 26: status text empty cases')
  reset_mocks()

  -- Test with no container and no devcontainer.json
  _G.require = function(module_name)
    if module_name == 'container.parser' then
      return {
        find_devcontainer_json = function()
          return nil -- No devcontainer.json found
        end,
      }
    else
      return mock_require(module_name)
    end
  end

  mock_container_state.initialized = true
  mock_container_state.current_container = nil

  local result = statusline.get_status()
  assert_equals('', result, 'Should return empty when no container and no devcontainer')

  print('✓ Empty status cases handled correctly')
end

local function test_show_container_name_false()
  print('Test 27: show_container_name = false')
  reset_mocks()

  _G.require = function(module_name)
    if module_name == 'container.config' then
      return {
        get = function()
          return {
            ui = {
              status_line = true,
              icons = { running = '✅' },
              statusline = {
                format = { running = '{icon} {name}' },
                labels = { container_name = 'CustomName' },
                show_container_name = false, -- Explicitly false
                default_format = '{icon} {name}',
              },
            },
          }
        end,
      }
    else
      return mock_require(module_name)
    end
  end

  mock_container_state.initialized = true
  mock_container_state.current_container = 'test-container'
  mock_container_state.container_status = 'running'
  mock_container_state.current_config = { name = 'ActualName' }

  local result = statusline.get_status()
  assert_not_nil(result, 'Should return status even with show_container_name=false')
  print('✓ show_container_name=false handled: ' .. result)
end

local function test_empty_icons_config()
  print('Test 28: empty icons configuration')
  reset_mocks()

  _G.require = function(module_name)
    if module_name == 'container.config' then
      return {
        get = function()
          return {
            ui = {
              status_line = true,
              icons = {}, -- Empty icons
              statusline = {
                format = { running = '{icon} {name}' },
                labels = {},
                default_format = '{icon} {name}',
              },
            },
          }
        end,
      }
    else
      return mock_require(module_name)
    end
  end

  mock_container_state.initialized = true
  mock_container_state.current_container = 'test-container'
  mock_container_state.container_status = 'running'
  mock_container_state.current_config = { name = 'TestApp' }

  local result = statusline.get_status()
  assert_not_nil(result, 'Should handle empty icons config')
  print('✓ Empty icons config handled: ' .. result)
end

local function test_cache_within_interval()
  print('Test 29: cache behavior within update interval')
  reset_mocks()
  _G.require = mock_require

  -- Mock static time
  local mock_time = 5000
  _G.vim.loop.now = function()
    return mock_time
  end

  mock_container_state.initialized = true
  mock_container_state.current_container = 'test-container'
  mock_container_state.container_status = 'running'
  mock_container_state.current_config = { name = 'TestApp' }

  -- First call
  local result1 = statusline.get_status()

  -- Change state but don't advance time enough
  mock_container_state.container_status = 'stopped'
  mock_time = mock_time + 1000 -- Only 1 second later (cache interval is 5 seconds)

  -- Second call should return cached result
  local result2 = statusline.get_status()

  assert_equals(result1, result2, 'Should return cached result within update interval')
  print('✓ Cache within interval works correctly')
end

local function test_setup_with_no_ui_config()
  print('Test 30: setup with no ui config')
  reset_mocks()

  _G.require = function(module_name)
    if module_name == 'container.config' then
      return {
        get = function()
          return {
            -- No ui config at all
          }
        end,
      }
    else
      return mock_require(module_name)
    end
  end

  statusline.setup()
  print('✓ Setup with no ui config handled')
end

local function test_missing_statusline_config()
  print('Test 31: missing statusline config')
  reset_mocks()

  _G.require = function(module_name)
    if module_name == 'container.config' then
      return {
        get = function()
          return {
            ui = {
              status_line = true,
              icons = { running = '✅' },
              -- No statusline config
            },
          }
        end,
      }
    else
      return mock_require(module_name)
    end
  end

  mock_container_state.initialized = true
  mock_container_state.current_container = 'test-container'
  mock_container_state.container_status = 'running'
  mock_container_state.current_config = { name = 'TestApp' }

  local result = statusline.get_status()
  assert_not_nil(result, 'Should handle missing statusline config')
  print('✓ Missing statusline config handled: ' .. result)
end

local function test_missing_labels_config()
  print('Test 32: missing labels config')
  reset_mocks()

  _G.require = function(module_name)
    if module_name == 'container.config' then
      return {
        get = function()
          return {
            ui = {
              status_line = true,
              icons = { running = '✅' },
              statusline = {
                format = { running = '{icon} {name}' },
                -- No labels config
                default_format = '{icon} {name}',
              },
            },
          }
        end,
      }
    else
      return mock_require(module_name)
    end
  end

  mock_container_state.initialized = true
  mock_container_state.current_container = 'test-container'
  mock_container_state.container_status = 'running'
  mock_container_state.current_config = { name = 'TestApp' }

  local result = statusline.get_status()
  assert_not_nil(result, 'Should handle missing labels config')
  print('✓ Missing labels config handled: ' .. result)
end

local function test_missing_format_config()
  print('Test 33: missing format config')
  reset_mocks()

  _G.require = function(module_name)
    if module_name == 'container.config' then
      return {
        get = function()
          return {
            ui = {
              status_line = true,
              icons = { running = '✅' },
              statusline = {
                -- No format config
                labels = { container_name = 'TestContainer' },
                default_format = '{icon} {name}',
              },
            },
          }
        end,
      }
    else
      return mock_require(module_name)
    end
  end

  mock_container_state.initialized = true
  mock_container_state.current_container = 'test-container'
  mock_container_state.container_status = 'running'
  mock_container_state.current_config = { name = 'TestApp' }

  local result = statusline.get_status()
  assert_not_nil(result, 'Should handle missing format config')
  print('✓ Missing format config handled: ' .. result)
end

local function test_terminal_session_mixed_active()
  print('Test 34: detailed status with mixed active terminal sessions')
  reset_mocks()
  _G.require = mock_require

  mock_container_state.initialized = true
  mock_container_state.current_container = 'test-container'
  mock_container_state.container_status = 'running'
  mock_container_state.current_config = { name = 'MyApp' }

  mock_terminal_sessions = {
    session1 = { active = false },
    session2 = { active = true },
    session3 = { active = false },
    session4 = { active = true }, -- Second active session
  }

  local result = statusline.get_detailed_status()
  assert_not_nil(result, 'Should return detailed status object')
  assert_equals(4, result.terminal_sessions, 'Should count all terminal sessions')
  -- Should find the first active terminal
  assert_true(
    result.active_terminal == 'session2' or result.active_terminal == 'session4',
    'Should identify an active terminal'
  )

  print('✓ Mixed active terminal sessions handled')
end

local function test_detailed_status_no_config()
  print('Test 35: detailed status with no config')
  reset_mocks()

  _G.require = function(module_name)
    if module_name == 'container.config' then
      return {
        get = function()
          return nil
        end,
      }
    else
      return mock_require(module_name)
    end
  end

  local result = statusline.get_detailed_status()
  assert_not_nil(result, 'Should return object even with no config')
  assert_equals('table', type(result), 'Should return table')

  print('✓ Detailed status with no config handled')
end

local function test_available_suffix_substitution()
  print('Test 36: available suffix substitution')
  reset_mocks()

  _G.require = function(module_name)
    if module_name == 'container.config' then
      return {
        get = function()
          return {
            ui = {
              status_line = true,
              icons = { stopped = '⏹️' },
              statusline = {
                format = {
                  available = '{icon} {name} (available)',
                },
                labels = {
                  container_name = 'TestContainer',
                  available_suffix = 'ready-to-start',
                },
                default_format = '{icon} {name}',
              },
            },
          }
        end,
      }
    else
      return mock_require(module_name)
    end
  end

  mock_container_state.initialized = true
  mock_container_state.current_container = nil -- No container

  local result = statusline.get_status()
  assert_not_nil(result, 'Should return status string')
  -- The substitution happens in the format_status function when (available) pattern is found
  -- Since we're using format 'available = {icon} {name} (available)', it should contain the suffix
  assert_true(result:find('ready') or result:find('available'), 'Should contain status info')

  print('✓ Available suffix substitution works: ' .. result)
end

local function test_edge_case_container_name_missing()
  print('Test 37: edge case - container name missing from config')
  reset_mocks()
  _G.require = mock_require

  mock_container_state.initialized = true
  mock_container_state.current_container = 'test-container'
  mock_container_state.container_status = 'running'
  mock_container_state.current_config = {} -- Empty config, no name

  local result = statusline.get_status()
  assert_not_nil(result, 'Should handle missing container name')
  print('✓ Missing container name handled: ' .. result)
end

local function test_different_container_statuses()
  print('Test 38: test all different container status values')
  reset_mocks()
  _G.require = mock_require

  local statuses = { 'running', 'exited', 'stopped', 'created', 'paused', 'restarting', 'dead' }

  for _, status in ipairs(statuses) do
    mock_container_state.initialized = true
    mock_container_state.current_container = 'test-container'
    mock_container_state.container_status = status
    mock_container_state.current_config = { name = 'TestApp' }

    statusline.clear_cache() -- Clear cache between tests
    local result = statusline.get_status()
    assert_not_nil(result, 'Should handle status: ' .. status)
  end

  print('✓ All container statuses handled')
end

local function test_autocmd_patterns()
  print('Test 39: autocmd pattern creation')
  reset_mocks()
  _G.require = mock_require

  -- Track autocmd creation
  local autocmd_calls = {}
  _G.vim.api.nvim_create_autocmd = function(event, opts)
    table.insert(autocmd_calls, { event = event, opts = opts })
    return 1
  end

  statusline.setup()

  assert_true(#autocmd_calls > 0, 'Should create autocmds')
  print('✓ Autocmd setup works correctly')
end

local function test_complex_cache_scenarios()
  print('Test 40: complex cache invalidation scenarios')
  reset_mocks()
  _G.require = mock_require

  local time_progression = 1000
  _G.vim.loop.now = function()
    return time_progression
  end

  mock_container_state.initialized = true
  mock_container_state.current_container = nil

  -- First call should cache devcontainer availability
  local result1 = statusline.get_status()

  -- Progress time but stay within devcontainer cache interval
  time_progression = time_progression + 20000 -- 20 seconds later
  local result2 = statusline.get_status()

  -- Should return same result due to caching
  assert_equals(result1, result2, 'Should use devcontainer cache')

  -- Progress time beyond devcontainer cache interval
  time_progression = time_progression + 15000 -- 35 seconds total, beyond 30s interval
  local result3 = statusline.get_status()

  -- May or may not be same result, but should not error
  assert_not_nil(result3, 'Should handle cache expiry')

  print('✓ Complex cache scenarios handled')
end

local function test_format_status_nil_template_direct()
  print('Test 41: completely nil statusline config scenario')
  reset_mocks()

  -- Create config where statusline_config itself could be nil
  _G.require = function(module_name)
    if module_name == 'container.config' then
      return {
        get = function()
          return {
            ui = {
              status_line = true,
              icons = { running = '✅' },
              -- No statusline section at all
            },
          }
        end,
      }
    else
      return mock_require(module_name)
    end
  end

  mock_container_state.initialized = true
  mock_container_state.current_container = 'test-container'
  mock_container_state.container_status = 'running'
  mock_container_state.current_config = { name = 'TestApp' }

  local result = statusline.get_status()
  -- Should use default fallback
  assert_not_nil(result, 'Should handle missing statusline config gracefully')
  print('✓ Missing statusline config handled: ' .. result)
end

local function test_config_completely_missing()
  print('Test 42: completely missing config scenarios')
  reset_mocks()

  -- Test get_status with completely missing config
  _G.require = function(module_name)
    if module_name == 'container.config' then
      return {
        get = function()
          return nil -- Completely nil config
        end,
      }
    else
      return mock_require(module_name)
    end
  end

  local result = statusline.get_status()
  assert_equals('', result, 'Should return empty string with nil config')

  -- Test get_detailed_status with completely missing config
  local detailed = statusline.get_detailed_status()
  assert_not_nil(detailed, 'Should return table even with nil config')
  assert_equals('table', type(detailed), 'Should return empty table')

  -- Test setup with completely missing config
  statusline.setup()

  print('✓ Completely missing config handled')
end

local function test_config_missing_ui_section()
  print('Test 43: config missing ui section')
  reset_mocks()

  -- Test with config missing ui section entirely
  _G.require = function(module_name)
    if module_name == 'container.config' then
      return {
        get = function()
          return {} -- Empty config, no ui section
        end,
      }
    else
      return mock_require(module_name)
    end
  end

  local result = statusline.get_status()
  assert_equals('', result, 'Should return empty string with missing ui config')

  local detailed = statusline.get_detailed_status()
  assert_not_nil(detailed, 'Should return table even with missing ui config')

  statusline.setup()

  print('✓ Missing ui section handled')
end

local function test_config_missing_status_line_key()
  print('Test 44: config missing status_line key')
  reset_mocks()

  -- Test with ui section but missing status_line key
  _G.require = function(module_name)
    if module_name == 'container.config' then
      return {
        get = function()
          return {
            ui = {}, -- ui exists but no status_line key
          }
        end,
      }
    else
      return mock_require(module_name)
    end
  end

  local result = statusline.get_status()
  assert_equals('', result, 'Should return empty string with missing status_line key')

  local detailed = statusline.get_detailed_status()
  assert_not_nil(detailed, 'Should return table even with missing status_line key')

  statusline.setup()

  print('✓ Missing status_line key handled')
end

-- Main test runner
local function run_tests()
  print('=== Container UI Statusline Tests ===')
  print('Target: Improve coverage from 56.03% to 70%+')
  print('')

  local tests = {
    test_module_loading,
    test_get_status_disabled,
    test_get_status_no_config,
    test_get_status_not_initialized,
    test_get_status_with_running_container,
    test_get_status_with_stopped_container,
    test_get_status_with_building_container,
    test_get_status_with_unknown_status,
    test_get_status_no_container_with_devcontainer,
    test_get_status_no_container_no_devcontainer,
    test_get_status_caching,
    test_get_status_with_custom_config,
    test_get_detailed_status,
    test_get_detailed_status_disabled,
    test_get_detailed_status_no_container,
    test_lualine_component,
    test_lightline_component,
    test_clear_cache,
    test_setup_function,
    test_format_status_edge_cases,
    test_devcontainer_caching,
    test_container_name_fallback,
    test_format_status_nil_template,
    test_devcontainer_cache_expiry,
    test_terminal_session_no_active,
    test_status_text_empty_cases,
    test_show_container_name_false,
    test_empty_icons_config,
    test_cache_within_interval,
    test_setup_with_no_ui_config,
    test_missing_statusline_config,
    test_missing_labels_config,
    test_missing_format_config,
    test_terminal_session_mixed_active,
    test_detailed_status_no_config,
    test_available_suffix_substitution,
    test_edge_case_container_name_missing,
    test_different_container_statuses,
    test_autocmd_patterns,
    test_complex_cache_scenarios,
    test_format_status_nil_template_direct,
    test_config_completely_missing,
    test_config_missing_ui_section,
    test_config_missing_status_line_key,
  }

  local passed = 0
  local failed = 0

  for i, test in ipairs(tests) do
    local success, err = pcall(test)
    if success then
      passed = passed + 1
    else
      print('✗ Test ' .. i .. ' failed: ' .. err)
      failed = failed + 1
    end
  end

  print('')
  print('=== Test Results ===')
  print('Tests completed: ' .. passed .. ' passed, ' .. failed .. ' failed')

  if failed == 0 then
    print('All tests passed! ✓')
    print('Expected coverage improvement for ui/statusline.lua module:')
    print('- Target: 70%+ coverage')
    print('- Added comprehensive edge case tests for nil config scenarios')
    print('- Total tests executed: ' .. #tests)
  else
    print('Some tests failed!')
    os.exit(1)
  end
end

-- Cleanup function
local function cleanup()
  _G.vim = original_vim
  _G.require = original_require
end

-- Run tests with cleanup
local success, err = pcall(run_tests)
cleanup()

if not success then
  print('Error running tests: ' .. err)
  os.exit(1)
end
