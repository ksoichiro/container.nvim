# Strategy B: LSPプロキシ方式 技術設計書

## JSON-RPC処理モジュール詳細設計

### 概要

LSPプロキシの中核となるJSON-RPC処理システムの設計。Language Server Protocol (LSP 3.17)準拠の双方向通信を実現し、パス変換を透過的に実行する。

### JSON-RPC処理フロー

```
┌─────────────────┐    ┌──────────────────────┐    ┌─────────────────┐
│   Neovim        │    │    LSP Proxy         │    │  LSP Server     │
│   (Host)        │    │   (Container)        │    │  (Container)    │
└─────────────────┘    └──────────────────────┘    └─────────────────┘
         │                         │                         │
         │ 1. Request              │                         │
         │ ─────────────────────→  │                         │
         │                         │ 2. Path Transform       │
         │                         │ (Host → Container)      │
         │                         │                         │
         │                         │ 3. Forward Request      │
         │                         │ ─────────────────────→  │
         │                         │                         │
         │                         │ 4. Response             │
         │                         │ ←─────────────────────  │
         │                         │                         │
         │                         │ 5. Path Transform       │
         │                         │ (Container → Host)      │
         │ 6. Forward Response     │                         │
         │ ←─────────────────────  │                         │
```

### モジュール構成

#### 1. jsonrpc.lua - JSON-RPC メッセージ処理

**主要機能:**
```lua
local jsonrpc = {}

-- JSON-RPC メッセージのパース
function jsonrpc.parse(raw_message)
  -- 入力: "Content-Length: 123\r\n\r\n{...}"
  -- 出力: { id, method, params, result, error }
end

-- JSON-RPC メッセージのシリアライズ
function jsonrpc.serialize(message)
  -- 入力: { id, method, params }
  -- 出力: "Content-Length: 123\r\n\r\n{...}"
end

-- メッセージタイプの判定
function jsonrpc.get_message_type(message)
  -- 出力: "request", "response", "notification", "error"
end
```

**JSON-RPC仕様サポート:**
- LSP準拠のContent-Length形式
- JSON-RPC 2.0準拠（id, method, params構造）
- リクエスト・レスポンス・通知・エラーメッセージ対応
- 一括メッセージ（配列）サポート

#### 2. transport.lua - 通信レイヤー

**主要機能:**
```lua
local transport = {}

-- stdio通信の初期化
function transport.create_stdio(read_fd, write_fd)
  return {
    read = function() end,     -- 非同期読み取り
    write = function(data) end, -- 非同期書き込み
    close = function() end      -- 接続終了
  }
end

-- TCP通信の初期化（オプション）
function transport.create_tcp(host, port)
  -- TCP接続作成・管理
end
```

**通信方式:**
- **Primary**: stdio (stdin/stdout)
- **Alternative**: TCP socket (デバッグ・ネットワーク対応)
- **非同期I/O**: vim.loop.new_pipe() ベース
- **エラーハンドリング**: 接続断・タイムアウト対応

#### 3. transform.lua - パス変換エンジン

**パス変換ルール:**

```lua
local transform = {}

-- 基本パス変換設定
local PATH_MAPPINGS = {
  host_root = "/Users/ksoichiro/src/project",
  container_root = "/workspace"
}

-- 双方向パス変換
function transform.host_to_container(path)
  -- /Users/ksoichiro/src/project/file.go → /workspace/file.go
end

function transform.container_to_host(path)
  -- /workspace/file.go → /Users/ksoichiro/src/project/file.go  
end

-- URI変換
function transform.host_uri_to_container(uri)
  -- file:///Users/.../file.go → file:///workspace/file.go
end

function transform.container_uri_to_host(uri)
  -- file:///workspace/file.go → file:///Users/.../file.go
end
```

**変換対象フィールド特定:**

```lua
-- LSPメッセージ種別ごとの変換ルール
local TRANSFORM_RULES = {
  -- 初期化
  ["initialize"] = {
    request = {
      "rootUri",
      "workspaceFolders[].uri"
    }
  },

  -- ドキュメント操作
  ["textDocument/didOpen"] = {
    request = { "textDocument.uri" }
  },

  ["textDocument/definition"] = {
    request = { "textDocument.uri" },
    response = { "uri", "targetUri", "[].uri" }
  },

  -- 診断
  ["textDocument/publishDiagnostics"] = {
    notification = { "uri" }
  },

  -- ワークスペース
  ["workspace/didChangeWatchedFiles"] = {
    notification = { "changes[].uri" }
  }
}
```

#### 4. server.lua - プロキシサーバー実装

**メイン処理ループ:**

```lua
local server = {}

function server.start(config)
  local state = {
    lsp_process = nil,        -- LSPサーバープロセス
    client_transport = nil,   -- Neovim接続
    server_transport = nil,   -- LSPサーバー接続
    path_mapper = nil,        -- パス変換器
    message_queue = {},       -- メッセージキュー
    running = true
  }

  -- 1. LSPサーバー起動
  state.lsp_process = spawn_lsp_server(config.server_cmd)

  -- 2. 通信チャネル設定
  state.client_transport = setup_client_connection()
  state.server_transport = setup_server_connection(state.lsp_process)

  -- 3. メッセージ処理ループ
  while state.running do
    process_messages(state)
  end
end

function process_messages(state)
  -- Neovim → LSPサーバー方向の処理
  local client_msg = state.client_transport:read_async()
  if client_msg then
    local transformed = transform_client_message(client_msg)
    state.server_transport:write(transformed)
  end

  -- LSPサーバー → Neovim方向の処理  
  local server_msg = state.server_transport:read_async()
  if server_msg then
    local transformed = transform_server_message(server_msg)
    state.client_transport:write(transformed)
  end
end
```

### エラーハンドリング戦略

#### 1. 通信エラー対応

```lua
-- 接続断対応
function handle_connection_error(error_type, details)
  if error_type == "client_disconnect" then
    -- Neovim接続断 → LSPサーバー終了
    terminate_lsp_server()
  elseif error_type == "server_crash" then
    -- LSPサーバークラッシュ → Neovimに通知
    notify_client_error("LSP server crashed: " .. details)
  end
end

-- タイムアウト対応
function handle_timeout(message_id, elapsed_time)
  log.warn("LSP message timeout: id=%s, elapsed=%dms", message_id, elapsed_time)
  -- タイムアウトエラーレスポンスを返す
end
```

#### 2. パス変換エラー対応

```lua
-- 変換失敗時の処理
function handle_transform_error(message, error_detail)
  log.error("Path transformation failed: %s", error_detail)

  -- エラー情報を追加してそのまま転送
  message._path_transform_error = error_detail
  return message
end

-- 不正パス検出
function validate_path(path)
  -- セキュリティチェック
  if path:match("%.%.") then
    return false, "Path traversal detected"
  end

  -- 存在チェック（ホスト側）
  if not file_exists(path) then
    return false, "File not found"
  end

  return true
end
```

### パフォーマンス最適化

#### 1. メッセージ処理の最適化

```lua
-- メッセージキューイング
local message_buffer = {
  client_to_server = {},
  server_to_client = {},
  max_buffer_size = 1000
}

-- バッチ処理
function process_message_batch(messages)
  local transformed_batch = {}
  for _, msg in ipairs(messages) do
    table.insert(transformed_batch, transform_message(msg))
  end
  return transformed_batch
end
```

#### 2. パス変換キャッシュ

```lua
-- 変換結果キャッシュ
local path_cache = {
  host_to_container = {},
  container_to_host = {},
  max_entries = 10000
}

function transform.cached_convert(path, direction)
  local cache = path_cache[direction]
  if cache[path] then
    return cache[path]  -- キャッシュヒット
  end

  local result = perform_transform(path, direction)
  cache[path] = result  -- キャッシュ更新
  return result
end
```

### デバッグ・監視機能

#### 1. 詳細ログ

```lua
-- メッセージトレース
function log_message_flow(direction, message_type, content)
  if config.debug_level >= 2 then
    log.debug("[%s] %s: %s", direction, message_type, vim.inspect(content))
  end
end

-- パフォーマンス測定
function measure_transform_time(transform_func, ...)
  local start_time = vim.loop.hrtime()
  local result = transform_func(...)
  local elapsed = (vim.loop.hrtime() - start_time) / 1000000  -- ms

  if elapsed > 5 then  -- 5ms以上は警告
    log.warn("Slow path transformation: %dms", elapsed)
  end

  return result
end
```

#### 2. ヘルスチェック

```lua
-- プロキシ状態監視
function health_check()
  return {
    proxy_running = state.running,
    lsp_server_alive = is_process_alive(state.lsp_process),
    client_connected = state.client_transport:is_connected(),
    message_queue_size = #state.message_queue,
    transform_cache_size = get_cache_size(),
    uptime_seconds = os.time() - state.start_time
  }
end
```

### 設定システム

```lua
-- プロキシ設定
local DEFAULT_CONFIG = {
  -- 基本設定
  server_cmd = { "gopls", "serve" },
  server_args = {},

  -- パス設定  
  host_workspace = "/Users/ksoichiro/src/project",
  container_workspace = "/workspace",

  -- 通信設定
  transport_type = "stdio",  -- "stdio" | "tcp"
  tcp_port = 9999,

  -- パフォーマンス
  message_buffer_size = 1000,
  path_cache_size = 10000,
  transform_timeout_ms = 100,

  -- デバッグ
  debug_level = 1,  -- 0=none, 1=basic, 2=verbose
  log_file = "/tmp/lsp_proxy.log",
  trace_messages = false
}
```

### テスト戦略

#### 1. 単体テスト

```lua
-- JSON-RPC処理テスト
describe("jsonrpc.parse", function()
  it("should parse valid LSP message", function()
    local input = 'Content-Length: 59\r\n\r\n{"jsonrpc":"2.0","method":"initialize","id":1}'
    local result = jsonrpc.parse(input)
    assert.equals("initialize", result.method)
    assert.equals(1, result.id)
  end)
end)

-- パス変換テスト  
describe("transform", function()
  it("should convert host path to container path", function()
    local result = transform.host_to_container("/Users/test/file.go")
    assert.equals("/workspace/file.go", result)
  end)
end)
```

#### 2. 統合テスト

```lua
-- エンドツーエンドテスト
describe("LSP Proxy Integration", function()
  it("should handle textDocument/definition request", function()
    local proxy = create_test_proxy()
    local request = create_definition_request("/Users/test/main.go", 10, 5)

    local response = proxy:process_request(request)

    assert.not_nil(response.result)
    assert.matches("/Users/test/", response.result.uri)
  end)
end)
```

## 次のステップ

1. **プロトタイプ実装**: 基本的なJSON-RPC中継機能
2. **パス変換実装**: 双方向変換ロジック
3. **統合テスト**: container.nvimとの連携
4. **パフォーマンス検証**: レスポンス時間・安定性測定

Strategy Bの技術設計が完了。実装フェーズへ移行可能。
