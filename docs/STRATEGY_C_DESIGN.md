# Strategy C: ホスト側インターセプト方式 設計書

## 概要

Strategy Cは、ホスト側でLSP通信を完全に制御し、すべてのメッセージをインターセプトしてパス変換を行う新しいアプローチです。

## 背景と課題

### 既存戦略の限界

1. **従来のパス変換方式**: LspAttach時の変換では`textDocument/didOpen`のタイミング問題が解決できない
2. **Strategy A (シンボリックリンク)**: システムパスの差異により実用性に限界
3. **Strategy B (LSPプロキシ)**: コンテナ内Lua実行の前提が実現不可能

### Strategy Cが解決する問題

- textDocument/didOpen を含む**すべてのLSPメッセージ**をインターセプト可能
- ホスト側での完全制御により環境依存性を排除
- Neovim標準APIを使用するため高い互換性

## アーキテクチャ

### 基本構成

```
┌─────────────────┐    ┌──────────────────────┐    ┌─────────────────┐
│   Neovim        │    │   Host Interceptor   │    │  LSP Server     │
│   (LSP Client)  │    │   (Path Transform)   │    │  (Container)    │
└─────────────────┘    └──────────────────────┘    └─────────────────┘
         │                         │                         │
         │ 1. LSP Messages         │                         │
         │ ─────────────────────→  │                         │
         │                         │ 2. Transform Paths      │
         │                         │ (Host → Container)      │
         │                         │                         │
         │                         │ 3. Forward to Container │
         │                         │ ─────────────────────→  │
         │                         │                         │
         │                         │ 4. Response             │
         │                         │ ←─────────────────────  │
         │                         │                         │
         │                         │ 5. Transform Paths      │
         │                         │ (Container → Host)      │
         │ 6. Forward to Neovim    │                         │
         │ ←─────────────────────  │                         │
```

### インターセプトポイント

Strategy Cでは、すべてのLSP通信をインターセプト：

1. **送信メッセージ** (Client → Server):
   - `initialize` (rootUri, workspaceFolders)
   - `textDocument/didOpen` (uri)
   - `textDocument/definition` (textDocument.uri)
   - その他すべてのリクエスト・通知

2. **受信メッセージ** (Server → Client):
   - `textDocument/publishDiagnostics` (uri)
   - `textDocument/definition` response (uri, targetUri)
   - その他すべてのレスポンス・通知

## 実装アプローチ

### Phase 1: vim.lsp.rpc カスタムハンドラー方式

最も現実的で実装が容易な方法：

```lua
-- LSPクライアント設定でカスタムRPCハンドラーを使用
local function create_intercepting_client(container_id, server_name)
  return {
    name = 'container_' .. server_name,
    cmd = { 'docker', 'exec', '-i', container_id, server_name },

    -- カスタムRPCハンドラーでメッセージインターセプト
    on_init = function(client, initialize_result)
      -- 既存のrequest/notifyメソッドをオーバーライド
      setup_message_interception(client, container_id)
    end
  }
end
```

### Phase 2: 完全カスタムRPCスタック方式

より高度な制御が必要な場合：

```lua
-- vim.lsp.rpc.start() を直接使用
local rpc_handler = vim.lsp.rpc.start(cmd, {
  on_request = function(method, params, callback)
    -- すべてのリクエストをインターセプト
    params = transform_request_paths(method, params)
    -- レスポンスコールバックもラップ
    local wrapped_callback = function(err, result)
      result = transform_response_paths(method, result)
      callback(err, result)
    end
    return method, params, wrapped_callback
  end,

  on_notification = function(method, params)
    params = transform_notification_paths(method, params)
    return method, params
  end
})
```

## パス変換ルール

### 基本変換規則

```lua
-- Host → Container 変換
local function host_to_container_path(path)
  local host_workspace = vim.fn.getcwd()
  return path:gsub("^" .. vim.pesc(host_workspace), "/workspace")
end

-- Container → Host 変換  
local function container_to_host_path(path)
  local host_workspace = vim.fn.getcwd()
  return path:gsub("^/workspace", host_workspace)
end

-- URI変換
local function transform_uri(uri, direction)
  if uri:match("^file://") then
    local path = uri:gsub("^file://", "")
    if direction == "to_container" then
      path = host_to_container_path(path)
    else
      path = container_to_host_path(path)
    end
    return "file://" .. path
  end
  return uri
end
```

### メッセージ別変換ルール

```lua
local MESSAGE_TRANSFORM_RULES = {
  -- 初期化メッセージ
  ["initialize"] = {
    request = {
      "rootUri",
      "rootPath",
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
  }
}
```

## 実装詳細

### 1. コアインターセプター

```lua
-- lua/container/lsp/interceptor.lua
local M = {}

function M.setup_client_interception(client, container_id)
  local original_request = client.request
  local original_notify = client.notify

  -- request メソッドのインターセプト
  client.request = function(method, params, handler, bufnr)
    params = M.transform_request_params(method, params, "to_container")

    local wrapped_handler = handler
    if handler and M.should_transform_response(method) then
      wrapped_handler = function(err, result, ctx)
        result = M.transform_response(method, result, "to_host")
        return handler(err, result, ctx)
      end
    end

    return original_request(method, params, wrapped_handler, bufnr)
  end

  -- notify メソッドのインターセプト
  client.notify = function(method, params)
    params = M.transform_request_params(method, params, "to_container")
    return original_notify(method, params)
  end
end
```

### 2. Strategy C統合

```lua
-- lua/container/lsp/strategies/intercept.lua
local M = {}

function M.create_client(server_name, container_id, server_config, strategy_config)
  local interceptor = require('container.lsp.interceptor')

  local client_config = {
    name = 'container_' .. server_name,
    cmd = { 'docker', 'exec', '-i', container_id, server_name },
    root_dir = server_config.root_dir or vim.fn.getcwd(),
    capabilities = vim.lsp.protocol.make_client_capabilities(),

    on_init = function(client, initialize_result)
      -- インターセプターを設定
      interceptor.setup_client_interception(client, container_id)

      if strategy_config.on_init then
        strategy_config.on_init(client, initialize_result)
      end
    end
  }

  return client_config
end
```

## 期待される効果

### 解決される問題

1. **textDocument/didOpenのタイミング問題**
   - すべてのメッセージをインターセプトするため、送信前に確実に変換

2. **初期診断エラーの解消**
   - 初期化時からすべてのパスが正しく変換される

3. **汎用性の確保**
   - すべてのLSPサーバーで同一のメカニズムが適用可能

4. **環境依存性の排除**
   - ホスト側完全制御により、コンテナ環境に依存しない

### パフォーマンス特性

- **レイテンシ増加**: 最小限（文字列置換のみ）
- **メモリ使用量**: 軽微な増加（変換処理のため）
- **安定性**: 高い（Neovim標準APIを使用）

## 実装スケジュール

### Phase 1: 基本実装 (1-2日)
1. コアインターセプター実装
2. 基本パス変換ロジック
3. Strategy C統合
4. Go LSPでの動作確認

### Phase 2: 機能拡張 (2-3日)
1. 全LSPメッセージ対応
2. エラーハンドリング強化
3. デバッグ機能追加
4. 複数言語での検証

### Phase 3: 最適化・統合 (1-2日)
1. パフォーマンス最適化
2. container.nvim統合
3. ドキュメント整備
4. テスト完備

## リスク評価

### 技術リスク: 低
- Neovim標準APIを使用
- 実績のあるパターン（リクエスト/レスポンスインターセプト）
- 段階的実装・検証が可能

### 互換性リスク: 低
- LSPプロトコル準拠
- 既存機能への影響最小限
- フォールバック機構実装可能

### 保守性リスク: 低
- シンプルなアーキテクチャ
- テスタブルな設計
- 明確な責任分離

## 結論

Strategy Cは、従来の課題を根本的に解決する実現可能で効果的なアプローチです。
ホスト側での完全制御により、確実で安定したLSP通信を実現できます。

---

*設計日: 2025-06-27*  
*実装対象: container.nvim v2.0*  
*想定実装期間: 5-7日*
