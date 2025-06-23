# Strategy B リスク分析と早期検証戦略

## 想定される重大リスク

### 1. 根本的な技術制約リスク

#### リスク1: Neovim LSPクライアントの制約
**問題**: vim.lsp.start_client()がプロキシ経由の通信をサポートしない可能性

**具体的懸念**:
- `docker exec`によるstdio接続の制限
- パイプチェーンの深さによる問題
- バッファリング・フラッシュの問題

**検証方法**:
```lua
-- 最小検証コード（ホスト側）
local client_id = vim.lsp.start_client({
  name = "test_proxy",
  cmd = {"docker", "exec", "-i", container_id, "cat"},  -- エコーバックテスト
  on_attach = function() print("Attached!") end,
})
```

**判定基準**:
- ❌ 失敗: stdio通信が確立できない → Strategy B断念
- ✅ 成功: 基本的な双方向通信が可能 → 継続

#### リスク2: Docker exec の制限
**問題**: コンテナ内プロセスとの安定したstdio通信が困難

**具体的懸念**:
- TTY割り当ての問題
- シグナル伝播の問題
- プロセス終了検出の困難性

**検証方法**:
```bash
# 単純なエコーバックテスト
echo '{"test": "message"}' | docker exec -i container_id cat

# 長時間接続テスト
docker exec -i container_id sh -c 'while read line; do echo "$line"; done'
```

**判定基準**:
- ❌ 失敗: 接続が不安定・データロス発生 → 代替通信方式検討
- ✅ 成功: 安定した双方向通信 → 継続

### 2. アーキテクチャ上の根本問題

#### リスク3: プロキシ実装言語の選択
**問題**: Lua実装では性能・機能面で限界がある可能性

**具体的懸念**:
- Luaでの高速JSON処理の困難性
- 非同期I/O処理の複雑性
- バイナリプロトコル処理の制限

**検証方法**:
```lua
-- Luaでの基本的なJSON-RPC処理性能テスト
local start = os.clock()
for i = 1, 10000 do
  local msg = parse_jsonrpc('Content-Length: 100\r\n\r\n{"id":1,"method":"test"}')
end
local elapsed = os.clock() - start
print("10000 messages in " .. elapsed .. "s")
```

**判定基準**:
- ❌ 失敗: 1メッセージ>1ms → 他言語実装検討（Go/Rust）
- ✅ 成功: 十分な性能 → Lua実装継続

#### リスク4: メッセージ順序・整合性保証
**問題**: 非同期双方向通信でメッセージ順序が崩れる

**具体的懸念**:
- リクエスト/レスポンスのマッチング失敗
- 通知メッセージの順序逆転
- 並行リクエストでの競合状態

**検証方法**:
```lua
-- 並行リクエストテスト
for i = 1, 100 do
  send_request({id = i, method = "test"})
end
-- レスポンスが正しい順序で返ってくるか確認
```

### 3. 実用性の根本問題  

#### リスク5: 遅延によるUX劣化
**問題**: プロキシ経由により体感速度が実用に耐えない

**具体的懸念**:
- 補完の遅延（>100ms）
- ホバー情報の遅延
- 診断情報の更新遅延

**検証方法**:
```lua
-- エンドツーエンド遅延測定
local start = vim.loop.hrtime()
vim.lsp.buf.hover()  -- プロキシ経由
local elapsed = (vim.loop.hrtime() - start) / 1000000  -- ms
```

**判定基準**:
- ❌ 失敗: 基本操作で>200ms遅延 → Strategy B断念
- ⚠️  警告: 50-200ms → 最適化必須
- ✅ 成功: <50ms → 実用的

## 早期検証戦略

### Phase 0: 技術検証（実装前）

**目的**: Strategy Bの技術的実現可能性を確認

#### 検証項目1: 最小通信テスト
```lua
-- test_minimal_proxy.lua
-- 1. docker exec経由でcatコマンドに接続
-- 2. 簡単なテキストをエコーバック
-- 3. vim.lsp.start_clientで接続可能か確認

local client_id = vim.lsp.start_client({
  name = "echo_test",
  cmd = {"docker", "exec", "-i", container_id, "cat"},
  on_attach = function(client)
    print("✅ Connection established!")
    -- 簡単なJSON-RPCメッセージを送信
    client.request("test", {}, function(err, result)
      print("Response:", vim.inspect(result))
    end)
  end,
  handlers = {
    ["test"] = function(err, result)
      print("Handler called!")
      return result
    end
  }
})
```

**所要時間**: 1-2時間
**Go/No-Go判定**: 接続不可なら即座にStrategy B断念

#### 検証項目2: シンプルプロキシ実装
```lua
-- simple_proxy.lua (コンテナ内で実行)
-- stdin → 変換 → stdout の最小実装

while true do
  local line = io.read("*l")
  if line then
    -- 単純にエコーバック（後でパス変換追加）
    print(line)
    io.flush()
  end
end
```

**検証内容**:
- Neovim → simple_proxy → cat のチェーン接続
- 基本的なメッセージ通過確認
- バッファリング問題の有無

### Phase 0.5: 最小JSON-RPC中継

**目的**: LSPプロトコルレベルでの基本動作確認

#### 実装内容（最小限）
```lua
-- minimal_jsonrpc_proxy.lua
local function parse_content_length(header)
  return tonumber(header:match("Content%-Length:%s*(%d+)"))
end

local function read_message()
  local line = io.read("*l")
  if not line then return nil end

  local content_length = parse_content_length(line)
  if not content_length then return nil end

  -- Skip empty line
  io.read("*l")

  -- Read body
  local body = io.read(content_length)
  return body
end

-- メインループ
while true do
  local msg = read_message()
  if msg then
    -- とりあえずそのまま転送
    io.write("Content-Length: " .. #msg .. "\r\n\r\n" .. msg)
    io.flush()
  end
end
```

**検証シナリオ**:
1. initialize リクエストが通過するか
2. initialized 通知が返ってくるか
3. 基本的なLSPハンドシェイク成立

**判定基準**:
- ❌ 失敗: LSP初期化失敗 → プロトコル処理に根本問題
- ✅ 成功: 初期化成功 → Phase 1へ

### リスク早期検出のためのメトリクス

#### 必須メトリクス（Phase 0で測定）

1. **接続確立時間**
   - 目標: <1秒
   - 限界: >5秒なら実用性なし

2. **メッセージ往復時間（RTT）**
   - 目標: <10ms  
   - 限界: >50msなら要再検討

3. **メモリ使用量**
   - 目標: <50MB
   - 限界: >200MBなら要最適化

4. **CPU使用率**
   - 目標: <5%（アイドル時）
   - 限界: >20%なら実装見直し

### 撤退条件（Strategy B断念基準）

以下のいずれかが発生した場合、Strategy Bを断念：

1. **技術的不可能**
   - vim.lsp.start_client()がdocker exec接続を受け付けない
   - stdio通信が根本的に不安定
   - メッセージ順序保証が不可能

2. **性能的限界**
   - 基本操作（補完・ホバー）で200ms以上の遅延
   - メモリリーク・CPU高負荷が解決不能
   - 大規模プロジェクトで実用的でない

3. **保守性問題**
   - デバッグが極めて困難
   - エラー原因の特定が不可能
   - ユーザーサポートが現実的でない

### 代替戦略（Strategy B失敗時）

#### Plan C: ネイティブ拡張方式
- C/Rust製のNeovimプラグイン
- より低レベルでの通信制御

#### Plan D: 設定ベース回避策
- ユーザーによる手動パス設定
- 言語別の個別対応
- 完全自動化は諦める

## 実装進行判断フロー

```
[Phase 0: 技術検証]
    ↓
  成功？ → No → Strategy B断念 → 代替戦略検討
    ↓ Yes
[Phase 0.5: 最小JSON-RPC]
    ↓
  成功？ → No → アーキテクチャ見直し
    ↓ Yes
[Phase 1: 基本実装]
    ↓
  継続的な性能・安定性監視
```

## まとめ

Strategy Bの成功は**Phase 0の技術検証**で80%決まる。最初の数時間で根本的な実現可能性を見極め、早期撤退の判断を可能にする。

**推奨アクション**:
1. まずPhase 0の検証コードを1-2時間で実装
2. 基本的な接続が確立できなければ即座に方針転換
3. 小さな成功を積み重ねながら段階的に複雑性を増す

この approach により、大規模実装後の手戻りリスクを最小化できる。
