-- Strategy B 機能テスト
-- 実際のLSP機能（定義ジャンプ、ホバー、補完）をテスト

print("=== STRATEGY B LSP FUNCTIONALITY TEST ===")

-- テスト用のGoコードを準備
local function setup_test_files()
  -- main.go の内容を確認
  local main_content = vim.fn.readfile('main.go')
  if #main_content > 0 then
    print("✅ main.go exists with " .. #main_content .. " lines")
    print("First line: " .. (main_content[1] or "empty"))
  else
    print("❌ main.go not found or empty")
    return false
  end

  return true
end

-- LSPクライアントの状態確認
local function check_lsp_clients()
  print("\n=== LSP CLIENT STATUS ===")

  local clients = vim.lsp.get_clients()
  if #clients == 0 then
    print("❌ No LSP clients found")
    return nil
  end

  for _, client in ipairs(clients) do
    print(string.format("Client: %s (ID: %d)", client.name, client.id))
    print(string.format("  - Initialized: %s", tostring(client.initialized)))
    print(string.format("  - Root Dir: %s", tostring(client.config.root_dir)))
    print(string.format("  - Command: %s", table.concat(client.config.cmd or {}, " ")))

    if client.name == 'container_gopls' then
      return client
    end
  end

  print("❌ container_gopls not found")
  return nil
end

-- 定義ジャンプのテスト
local function test_definition_jump(client)
  print("\n=== TESTING DEFINITION JUMP ===")

  -- main.goを開く
  vim.cmd('edit main.go')
  local bufnr = vim.api.nvim_get_current_buf()

  print("Buffer: " .. bufnr .. " (main.go)")

  -- バッファをLSPクライアントにアタッチ
  if not vim.lsp.buf_is_attached(bufnr, client.id) then
    vim.lsp.buf_attach_client(bufnr, client.id)
    print("✅ Attached buffer to LSP client")

    -- 少し待機してアタッチメントが完了するのを待つ
    vim.wait(2000)
  else
    print("✅ Buffer already attached to LSP client")
  end

  -- main関数の位置を探す
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local main_line = nil
  local main_col = nil

  for i, line in ipairs(lines) do
    local col = line:find('main%(%)') -- main() 関数を探す
    if col then
      main_line = i - 1  -- 0-indexed
      main_col = col - 1  -- 0-indexed
      print(string.format("Found main() at line %d, col %d", main_line + 1, main_col + 1))
      break
    end
  end

  if not main_line then
    print("❌ Could not find main() function in file")
    return false
  end

  -- カーソルをmain関数に移動
  vim.api.nvim_win_set_cursor(0, {main_line + 1, main_col})

  -- 定義ジャンプをテスト
  print("Attempting definition jump...")

  local definition_found = false
  local definition_timeout = false

  -- タイムアウト設定
  local timer = vim.loop.new_timer()
  timer:start(5000, 0, function()
    definition_timeout = true
    timer:close()
  end)

  -- 定義リクエスト
  local params = vim.lsp.util.make_position_params()
  client.request('textDocument/definition', params, function(err, result, context)
    definition_timeout = false
    timer:close()

    print("Definition request completed")
    print("Error: " .. tostring(err))
    print("Result: " .. vim.inspect(result))
    print("Context: " .. vim.inspect(context))

    if err then
      print("❌ Definition request failed: " .. tostring(err))
    elseif result and #result > 0 then
      print("✅ Definition found: " .. vim.inspect(result[1]))
      definition_found = true
    else
      print("⚠️  Definition request succeeded but no results")
    end
  end)

  -- 結果を待つ
  local start_time = vim.loop.now()
  while not definition_found and not definition_timeout and (vim.loop.now() - start_time) < 5000 do
    vim.wait(100)
  end

  if definition_timeout then
    print("❌ Definition request timed out")
    return false
  elseif definition_found then
    print("✅ Definition jump test passed")
    return true
  else
    print("❌ Definition jump test failed")
    return false
  end
end

-- ホバー情報のテスト
local function test_hover(client)
  print("\n=== TESTING HOVER ===")

  local bufnr = vim.api.nvim_get_current_buf()

  -- hover リクエスト
  local params = vim.lsp.util.make_position_params()

  local hover_found = false
  local hover_timeout = false

  local timer = vim.loop.new_timer()
  timer:start(3000, 0, function()
    hover_timeout = true
    timer:close()
  end)

  client.request('textDocument/hover', params, function(err, result, context)
    hover_timeout = false
    timer:close()

    print("Hover request completed")
    print("Error: " .. tostring(err))

    if err then
      print("❌ Hover request failed: " .. tostring(err))
    elseif result and result.contents then
      print("✅ Hover information found")
      print("Contents: " .. vim.inspect(result.contents))
      hover_found = true
    else
      print("⚠️  Hover request succeeded but no content")
    end
  end)

  -- 結果を待つ
  local start_time = vim.loop.now()
  while not hover_found and not hover_timeout and (vim.loop.now() - start_time) < 3000 do
    vim.wait(100)
  end

  if hover_timeout then
    print("❌ Hover request timed out")
    return false
  elseif hover_found then
    print("✅ Hover test passed")
    return true
  else
    print("❌ Hover test failed")
    return false
  end
end

-- 実行
local function run_tests()
  if not setup_test_files() then
    return false
  end

  local client = check_lsp_clients()
  if not client then
    return false
  end

  local results = {}
  results.definition = test_definition_jump(client)
  results.hover = test_hover(client)

  print("\n=== TEST SUMMARY ===")
  print("Definition Jump: " .. (results.definition and "✅ PASS" or "❌ FAIL"))
  print("Hover: " .. (results.hover and "✅ PASS" or "❌ FAIL"))

  local total_tests = 2
  local passed_tests = 0
  if results.definition then passed_tests = passed_tests + 1 end
  if results.hover then passed_tests = passed_tests + 1 end

  print(string.format("\nResults: %d/%d tests passed", passed_tests, total_tests))

  if passed_tests == total_tests then
    print("\n🎉 All Strategy B LSP functionality tests PASSED!")
    print("Strategy B is working correctly.")
  else
    print("\n⚠️  Some Strategy B functionality tests FAILED.")
    print("Further investigation needed.")
  end

  return passed_tests == total_tests
end

-- 実行
local success = run_tests()
return success
