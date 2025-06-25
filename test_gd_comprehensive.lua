-- Comprehensive GD Override Testing
-- Tests various scenarios for the working gd implementation

print("=== COMPREHENSIVE GD TESTING ===")

-- Test environment setup
local function setup_test_env()
  local bufnr = vim.api.nvim_get_current_buf()
  local current_file = vim.fn.expand('%:p')

  print("Test Environment:")
  print("  Current file:", current_file)
  print("  Buffer:", bufnr)

  -- Check LSP clients
  local clients = vim.lsp.get_clients({bufnr = bufnr})
  print("  LSP clients:")
  for _, client in ipairs(clients) do
    print("    -", client.name, "(ID:", client.id, ")")
  end

  -- Find container_gopls
  local container_client = nil
  for _, client in ipairs(clients) do
    if client.name == 'container_gopls' then
      container_client = client
      break
    end
  end

  if container_client then
    print("  ✅ container_gopls found (ID:", container_client.id, ")")
    print("  Root dir:", container_client.config.root_dir)
  else
    print("  ❌ container_gopls not found")
    return false
  end

  return true
end

-- Test the gd mapping multiple times
local function test_repeated_gd()
  print("\n=== TEST: REPEATED GD JUMPS ===")
  print("Manual test required:")
  print("1. Place cursor on a function name")
  print("2. Press 'gd' multiple times")
  print("3. Verify no errors occur")
  print("4. Check that cursor position updates correctly")
  print("5. Verify LSP client remains connected")
end

-- Test same-file vs different-file jumps
local function test_jump_scenarios()
  print("\n=== TEST: JUMP SCENARIOS ===")
  print("Test cases to verify manually:")
  print("1. Same file jumps (function to its implementation)")
  print("2. Cross-file jumps (if multiple Go files exist)")
  print("3. Standard library jumps (should show error - expected)")
  print("4. Non-existent definitions")
end

-- Test error handling
local function test_error_handling()
  print("\n=== TEST: ERROR HANDLING ===")
  print("1. Place cursor on undefined symbol")
  print("2. Press 'gd' - should show 'No definition found'")
  print("3. Place cursor outside any symbol")
  print("4. Press 'gd' - should handle gracefully")
end

-- Test performance
local function test_performance()
  print("\n=== TEST: PERFORMANCE ===")
  print("Monitor response times:")
  print("1. Time from 'gd' press to jump completion")
  print("2. Check for any noticeable delays")
  print("3. Verify no memory leaks with repeated use")
end

-- Run all tests
local function run_tests()
  if not setup_test_env() then
    print("❌ Test environment setup failed")
    return
  end

  -- Apply the working gd override (load from correct path)
  local script_dir = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h")
  local working_gd_path = script_dir .. '/working_gd_override.lua'
  local working_gd = dofile(working_gd_path)
  working_gd.apply_gd_override()

  test_repeated_gd()
  test_jump_scenarios()
  test_error_handling()
  test_performance()

  print("\n=== TEST COMPLETION ===")
  print("All tests set up. Please perform manual verification.")
  print("Report any issues or unexpected behavior.")
end

-- Execute tests
run_tests()
