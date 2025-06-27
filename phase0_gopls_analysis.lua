-- Phase 0: gopls動作分析スクリプト
-- 目的: goplsがワークスペース認識でどのパスを使用するか確認

print("=== PHASE 0: GOPLS BEHAVIOR ANALYSIS ===")

-- コンテナID取得
local function get_container_id()
  local handle = io.popen("docker ps -q | head -1")
  local container_id = handle:read("*line")
  handle:close()
  return container_id
end

local container_id = get_container_id()
print("Container ID:", container_id)

-- Test 1: コンテナ内でgoplsをトレースモードで起動
print("\n=== TEST 1: GOPLS TRACE MODE ===")
print("Manually run in container:")
print("docker exec -it " .. container_id .. " bash")
print("cd /workspace")
print("/go/bin/gopls -logfile=/tmp/gopls_trace.log -v -rpc.trace serve")
print("(Then test with various file paths)")

-- Test 2: 最小LSPリクエストでのパス確認
print("\n=== TEST 2: MINIMAL LSP REQUEST TEST ===")

local function test_path_resolution(uri_path, description)
  print("\n--- Testing: " .. description .. " ---")
  print("URI: " .. uri_path)

  -- 手動テスト用のLSPメッセージ例
  local lsp_message = {
    jsonrpc = "2.0",
    method = "textDocument/didOpen",
    params = {
      textDocument = {
        uri = uri_path,
        languageId = "go",
        version = 1,
        text = "package main\n\nimport \"./calculator\"\n\nfunc main() {\n\tcalc := calculator.NewCalculator()\n\tresult := calc.Add(1, 2)\n\tprintln(result)\n}"
      }
    }
  }

  -- LSP Message structure (would be vim.inspect in neovim)
  print("LSP Message structure defined for: " .. description)
  print("Expected: gopls should " .. (uri_path:match("^file:///workspace") and "SUCCEED" or "FAIL") .. " in workspace recognition")
end

-- Test cases
test_path_resolution("file:///Users/ksoichiro/src/github.com/ksoichiro/container.nvim/main.go", "Host path (current behavior)")
test_path_resolution("file:///workspace/main.go", "Container path (Strategy B)")

-- Test 3: ワークスペースフォルダーでの動作確認
print("\n=== TEST 3: WORKSPACE FOLDER BEHAVIOR ===")

local workspace_test_host = {
  jsonrpc = "2.0",
  method = "initialize",
  params = {
    rootUri = "file:///Users/ksoichiro/src/github.com/ksoichiro/container.nvim",
    workspaceFolders = {
      {
        uri = "file:///Users/ksoichiro/src/github.com/ksoichiro/container.nvim",
        name = "container.nvim"
      }
    }
  }
}

local workspace_test_container = {
  jsonrpc = "2.0",
  method = "initialize",
  params = {
    rootUri = "file:///workspace",
    workspaceFolders = {
      {
        uri = "file:///workspace",
        name = "workspace"
      }
    }
  }
}

print("Host workspace initialize message defined")
print("Container workspace initialize message defined")

-- Test 4: ファイルシステムアクセス確認
print("\n=== TEST 4: FILESYSTEM ACCESS PATTERNS ===")
print("Check the following in container:")
print("1. Does /workspace/go.mod exist?")
print("2. Can gopls read /workspace/calculator.go?")
print("3. What happens with /Users/.../go.mod?")

-- Manual verification commands
print("\n=== MANUAL VERIFICATION COMMANDS ===")
print("# In container:")
print("docker exec -it " .. container_id .. " bash")
print("cd /workspace")
print("echo '--- go.mod exists? ---'")
print("ls -la go.mod")
print("echo '--- calculator.go exists? ---'")
print("ls -la calculator.go")
print("echo '--- Host path exists? ---'")
print("ls -la /Users/ksoichiro/ 2>/dev/null || echo 'Host path not accessible'")

print("\n=== EXPECTED RESULTS ===")
print("✅ /workspace files should be accessible")
print("❌ /Users/... paths should be inaccessible")
print("→ This confirms our hypothesis: gopls needs /workspace paths to function")

print("\n=== NEXT STEPS ===")
print("1. Run the manual commands above")
print("2. Start gopls in trace mode")
print("3. Send both host and container path requests")
print("4. Compare the behavior and error messages")
print("5. Document findings for GO/NO-GO decision")
