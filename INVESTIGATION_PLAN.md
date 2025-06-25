# Strategy B 問題調査計画

## 目的
定義ジャンプ時に `/workspace/main.go` が開かれる問題の根本原因特定

## Phase 1: 現状把握（影響なし）

### 調査1-A: ハンドラー実行確認
```vim
:lua
local clients = vim.lsp.get_clients()
for _, client in ipairs(clients) do
  if client.name == 'container_gopls' then
    print("=== CLIENT HANDLERS ===")
    if client.config.handlers then
      for method, handler in pairs(client.config.handlers) do
        print(method .. ": " .. type(handler))
      end
    else
      print("No client handlers")
    end
    break
  end
end

print("=== GLOBAL HANDLERS ===")
for method, handler in pairs(vim.lsp.handlers) do
  if method:match('definition') then
    print(method .. ": " .. type(handler))
  end
end
```

### 調査1-B: 生のLSPレスポンス確認
```vim
:lua
local params = vim.lsp.util.make_position_params()
print("Position params:", vim.inspect(params))

local clients = vim.lsp.get_clients()
for _, client in ipairs(clients) do
  if client.name == 'container_gopls' then
    client.request('textDocument/definition', params, function(err, result)
      print("=== RAW LSP RESPONSE ===")
      print("Error:", vim.inspect(err))
      print("Result:", vim.inspect(result))

      if result and #result > 0 then
        local uri = result[1].uri
        print("URI from LSP:", uri)
        print("vim.uri_to_fname result:", vim.uri_to_fname(uri))
        print("File exists:", vim.fn.filereadable(vim.uri_to_fname(uri)))
      end
    end, 0)
    break
  end
end
```

### 調査1-C: before_init パラメータ確認
```vim
:lua
local clients = vim.lsp.get_clients()
for _, client in ipairs(clients) do
  if client.name == 'container_gopls' then
    print("=== CLIENT CONFIG ===")
    print("Root dir:", client.config.root_dir)
    print("Workspace folders:", vim.inspect(client.config.workspace_folders))
    print("Initial params workspace:", vim.inspect(client.workspace_folders))
    break
  end
end
```

## Phase 2: 問題特定後の最小修正

### パターンA: ハンドラー未実行の場合
- client.config.handlersの設定方法を見直し
- LSP設定のタイミング問題を確認

### パターンB: URI変換問題の場合  
- vim.uri_to_fname()の動作確認
- パス変換ロジックの見直し

### パターンC: ワークスペース設定問題の場合
- before_initパラメータの詳細確認
- 初期化シーケンスの見直し

## Phase 3: 検証テスト

### 最小テストケース作成
- 他の修正の影響を排除した単純なテスト
- 問題の再現性確認
- 修正効果の検証

## 実行ルール

1. **Phase 1完了まで新しい修正は行わない**
2. **各調査結果を記録してから次に進む**  
3. **問題の根本原因を特定してから修正戦略を決定**
4. **修正は最小限から開始し、影響範囲を慎重に評価**

## 期待される成果

- 問題の根本原因の明確化
- 最小限の修正による問題解決
- 既存機能への影響の最小化
- 安定したStrategy B実装の完成
