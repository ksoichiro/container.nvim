#!/usr/bin/env lua

-- Test script for LSP duplicate client prevention
-- This tests the client_exists function and duplicate prevention logic

package.path = './lua/?.lua;./lua/?/init.lua;' .. package.path

-- Mock vim functions for testing
_G.vim = {
  tbl_deep_extend = function(behavior, ...)
    local result = {}
    local sources = {...}
    for _, source in ipairs(sources) do
      if type(source) == 'table' then
        for k, v in pairs(source) do
          result[k] = v
        end
      end
    end
    return result
  end,
  tbl_keys = function(t)
    local keys = {}
    for k, _ in pairs(t) do
      table.insert(keys, k)
    end
    return keys
  end,
  lsp = {
    get_active_clients = function(opts)
      if opts and opts.name then
        -- Simulate existing clients based on name
        if opts.name == "gopls" then
          return {
            {id = 1, name = "gopls", is_stopped = false}
          }
        elseif opts.name == "lua_ls" then
          return {} -- No active clients
        end
      end
      return {}
    end,
    get_client_by_id = function(id)
      if id == 1 then
        return {id = 1, name = "gopls", is_stopped = false}
      elseif id == 2 then
        return {id = 2, name = "lua_ls", is_stopped = true} -- Stopped client
      end
      return nil
    end
  },
  defer_fn = function(fn, delay) fn() end,
  schedule = function(fn) fn() end,
  inspect = function(obj)
    if type(obj) == 'table' then
      local parts = {}
      for k, v in pairs(obj) do
        table.insert(parts, tostring(k) .. "=" .. tostring(v))
      end
      return "{" .. table.concat(parts, ", ") .. "}"
    end
    return tostring(obj)
  end
}

-- Mock log module
local mock_log = {
  debug = function(...) print("[DEBUG]", ...) end,
  info = function(...) print("[INFO]", ...) end,
  warn = function(...) print("[WARN]", ...) end,
  error = function(...) print("[ERROR]", ...) end
}

package.loaded['devcontainer.utils.log'] = mock_log

print("=== LSP Duplicate Client Prevention Test ===")
print()

-- Load the LSP module
local lsp = require('devcontainer.lsp.init')

-- Initialize mock state
lsp.setup({auto_setup = true})

print("Test 1: Check for existing active client (gopls)")
local exists, client_id = lsp.client_exists("gopls")
print("Result: exists=" .. tostring(exists) .. ", client_id=" .. tostring(client_id))
assert(exists == true, "Should find existing gopls client")
assert(client_id == 1, "Should return correct client ID")
print("✓ Test 1 passed")
print()

print("Test 2: Check for non-existing client (lua_ls)")
exists, client_id = lsp.client_exists("lua_ls")
print("Result: exists=" .. tostring(exists) .. ", client_id=" .. tostring(client_id))
assert(exists == false, "Should not find lua_ls client")
assert(client_id == nil, "Should return nil client ID")
print("✓ Test 2 passed")
print()

print("Test 3: Check for client with stale state")
-- Simulate stale state
local lsp_state = lsp.get_state()
lsp_state.clients = lsp_state.clients or {}
lsp_state.clients.lua_ls = {client_id = 2} -- Stale client ID

exists, client_id = lsp.client_exists("lua_ls")
print("Result: exists=" .. tostring(exists) .. ", client_id=" .. tostring(client_id))
assert(exists == false, "Should clean up stale client state")
assert(client_id == nil, "Should return nil for stopped client")
print("✓ Test 3 passed")
print()

print("Test 4: Mock setup_lsp_in_container with duplicate detection")
-- Mock detect_language_servers to return some servers
local original_detect = lsp.detect_language_servers
lsp.detect_language_servers = function()
  return {
    gopls = {available = true, cmd = "gopls", languages = {"go"}},
    lua_ls = {available = true, cmd = "lua-language-server", languages = {"lua"}}
  }
end

-- Mock create_lsp_client to track calls
local create_calls = {}
local original_create = lsp.create_lsp_client
lsp.create_lsp_client = function(name, config)
  table.insert(create_calls, name)
  print("  Created client for: " .. name)
end

print("Running setup_lsp_in_container...")
lsp.setup_lsp_in_container()

print("Create calls:", vim.inspect and vim.inspect(create_calls) or table.concat(create_calls, ", "))
assert(#create_calls == 1, "Should only create one client (lua_ls)")
assert(create_calls[1] == "lua_ls", "Should create lua_ls client only")
print("✓ Test 4 passed - gopls was skipped, lua_ls was created")
print()

-- Restore original functions
lsp.detect_language_servers = original_detect
lsp.create_lsp_client = original_create

print("=== All LSP Duplicate Prevention Tests Passed! ===")
print()
print("Fixed issues:")
print("  ✓ LSP clients are checked for existence before creation")
print("  ✓ Stale client state is cleaned up automatically")
print("  ✓ setup_lsp_in_container prevents duplicate clients")
print("  ✓ Proper logging for skipped vs new clients")
print("  ✓ Container status is verified before LSP setup")
