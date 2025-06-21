# LSP Investigation Plan

## 問題の概要

container_gopls が自動起動するようになったが、以下の問題が残っている：

1. **初期診断問題**: container_gopls 起動直後に誤った診断が表示される
   - "No packages found for open file /Users/ksoichiro/..." (ローカルパス)
   - "undefined: NewCalculator" など、他ファイルの定義を見つけられない
   - `:e` で再読み込みすると正常になる

2. **ホストLSP並行起動**: ホストの gopls も同時に起動し、定義ジャンプで複数候補が表示される

## 判明している技術的事実

### タイミング
- ホスト gopls: 0.36秒で起動
- container_gopls: 約7-9秒で起動
- パス変換は LspAttach で設定されるため、初期化後に適用される

### 動作状況
- パス変換システム自体は正常に動作している（手動 `:e` で確認済み）
- container_gopls は自動起動するようになった
- 定義ジャンプはパス変換適用後は正常に動作する

### 現在の実装
- LspAttach イベントでパス変換を設定
- on_attach でバッファ再読み込みを試行（効果は限定的）
- ホストLSP停止の自動化（副作用で通知量が増大）

## 改善計画

### フェーズ1: container_gopls の初期診断問題の原因究明

**調査目標:**
1. LSP初期化シーケンスの詳細記録
   - `initialize` → `initialized` → `textDocument/didOpen` の順序
   - 各メッセージでのパスの形式
   - パス変換が適用されるタイミング

2. workspace設定の検証
   - container_gopls が認識している workspace フォルダ
   - 実際のファイルパスとの整合性

3. パス変換のタイミング問題
   - LspAttach より前に送信されるメッセージの存在
   - 初期メッセージが変換されずに送信されている可能性

**期待される結果:**
- 初期診断エラーの根本原因を特定
- パス変換が適用されないメッセージを特定

### フェーズ2: 診断問題の解決

**解決策候補:**
- パス変換のタイミング調整（より早期の適用）
- 初期化メッセージの再送信
- workspace設定の修正
- 初期診断のクリア機能

### フェーズ3: ホストLSP の起動制御

**アプローチ:**
- lspconfig の autostart を動的に制御
- FileType autocmd より前に介入
- 案1（起動防止）+ 案3（lspconfig制御）の組み合わせ

## 技術的詳細

### 現在のアーキテクチャ
```
lua/container/lsp/
├── init.lua          # メイン制御、自動起動、状態管理
├── transform.lua     # LspAttachでのパス変換
├── configs.lua       # 言語固有設定
└── path.lua          # パス変換ユーティリティ
```

### パス変換の仕組み
- ローカル: `/Users/ksoichiro/src/.../examples/go-test-example`
- コンテナ: `/workspace`
- LspAttach時に `client.request` と `client.notify` をオーバーライド

### 自動起動の仕組み
- メイン setup() で LSP モジュールを初期化
- FileType 'go' イベントでコンテナ状態をチェック
- ContainerStarted/ContainerOpened イベントでもチェック

## 注意事項

- デバッグ用の大量ログ出力は削除する
- 有効な機能のみをコミットする
- 複雑な状態管理は避ける
- パフォーマンスへの影響を考慮する

## 次のアクション

1. ✅ 計画をファイルに記録
2. 🔄 現在の変更を整理・コミット
3. 📊 フェーズ1: LSP初期化シーケンスの詳細調査
4. 🔧 フェーズ2: 診断問題の解決
5. 🛡️ フェーズ3: ホストLSP制御

## 進捗記録

### 2025-06-21
- 問題分析、計画策定完了
- 基本システム実装（transform.lua, configs.lua）
- クリーンなブランチ作成、有効な変更をコミット

### 2025-06-22 - フェーズ1: 初期化シーケンス調査

#### 重要な発見 ⚠️

**監視結果 (15秒間):**
- `[9.401s]` ホスト gopls がアタッチ（client_id: 1）
- **container_gopls は全く起動していない**
- 診断変化は3回発生したが、診断数は常に0

#### 判明した問題

1. **container_gopls が自動起動していない**
   - 15秒の監視期間中、container_gopls のアタッチイベントなし
   - ホスト gopls のみが起動（9.4秒後）
   - 自動起動機能が動作していない可能性

2. **LSP通信が記録されていない**
   - `initialize`, `textDocument/didOpen`, `publishDiagnostics` などのメッセージが捕捉されていない
   - LSPメッセージインターセプトが正しく動作していない可能性

3. **パス変換が発生していない**
   - PATH_TRANSFORM_TO_CONTAINER/LOCAL イベントなし
   - container_gopls が起動していないため変換も発生しない

#### 根本原因を特定 🎯

**コンテナ状態の詳細調査結果:**
- `Connected: nil` ← **問題の核心**
- `Current Container: 899f5760a239` ← コンテナIDは検出済み
- `LSP Container ID: nil` ← LSPモジュールに未設定

**原因分析:**
container.nvim は以下の条件で LSP を自動起動する設計：
```lua
local is_connected = state.connected or (state.current_container ~= nil)
```

しかし、現在の状態では `state.connected` が `nil` のため、自動起動条件を満たしていない。
`current_container` はあるが、`connected` フラグが設定されていない。

**修正方針:**
1. `connected` フラグが設定されない原因を調査
2. または自動起動条件を `current_container` の存在のみに簡素化

#### 実装の不整合を発見 🐛

**`connected` フラグの調査結果:**

1. **`get_state()` の実際の return:**
   ```lua
   return {
     initialized = state.initialized,
     current_container = state.current_container,
     current_config = state.current_config,
     container_status = container_status,
   }
   ```

2. **`connected` フィールドが存在しない**
   - `get_state()` には `connected` フィールドが含まれていない
   - LSP自動起動コードが存在しないフィールドをチェックしている
   - `state.connected` は常に `nil` になる

3. **現在の状況は妥当**
   - `connected: nil` は正常（フィールドが存在しないため）
   - `current_container: 899f5760a239` は正常（コンテナが検出されている）

**結論:**
自動起動条件を `current_container` の存在のみに修正するのが適切。
`connected` フラグは削除するか、正しく実装する必要がある。

#### 新たな問題を発見 🔍

**自動初期化テスト結果:**
- ✅ 自動初期化ロジックは動作している
- ✅ gopls はコンテナ内で検出されている  
- ❌ **ホストの gopls と名前が競合している**

**問題の詳細:**
```
[DEBUG] LSP: Found existing active client for gopls
```

`client_exists()` 関数が `gopls` 名前でホストクライアントを検出し、container_gopls のセットアップをスキップ。
しかし、container_gopls は `container_gopls` という名前で作成されるべき。

**修正が必要な箇所:**
1. `client_exists()` で正しい名前（`container_gopls`）をチェック
2. または、ホストクライアントと区別する仕組み

#### フェーズ1 継続中 🔄

**名前競合問題の修正結果:**
- ✅ **名前競合問題を解決** - `container_` 接頭辞追加
- ✅ **手動起動で問題再現可能** - デバッグスクリプト経由  
- ❌ **自動起動は未実装** - 通常の `nvim main.go` では起動しない

**タイミング問題の解決 ⚡**
- ✅ **根本原因を特定** - BufEnter が container 検出より先に実行される
- ✅ **新アプローチ実装** - イベント駆動型の自動初期化
- ✅ **ContainerDetected イベント追加** - container 検出時に User イベント発火
- 🔄 **テスト待ち** - 新しい実装の動作確認

**新しい実装の仕組み:**
1. container 検出時に `ContainerDetected` イベント発火
2. LSP モジュールが `ContainerDetected` をリッスン
3. イベント受信時に Go バッファをチェックして container_gopls を起動
4. フォールバック機能: FileType イベントでも1秒遅延で再試行

**発見された問題 🚨**
- ✅ **自動起動は成功** - container_gopls が起動するように
- ❌ **異常終了の問題** - "Client container_gopls quit with exit code 1 and signal 0"
- ❌ **lspconfig エラー** - "container_gopls does not have a configuration"
- ❌ **通信エラー** - "context canceled", "EOF" などのRPC通信問題

**問題の根本原因:**
1. **lspconfig 設定不備**: `container_gopls` の設定がlspconfigに登録されていない
2. **Docker 通信問題**: 長時間実行のgoplsプロセスが予期せず終了
3. **環境変数・パス問題**: コンテナ内のGo環境設定の不備

**修正実装 🔧**
- ❌ **カスタムlspconfig登録** - lspconfigエラーが大量発生、パフォーマンス劣化
- ✅ **vim.lsp.start_client直接使用** - lspconfigを回避してクライアントを直接起動
- ✅ **Docker exec の改善** - シグナルハンドリング、ログ出力の追加
- ✅ **Go環境変数の修正** - GOROOT, GOPATH, PATHの明示的設定

**アーキテクチャの変更:**
- lspconfigへの依存を削除
- `vim.lsp.start_client()` による直接クライアント作成
- 手動でのバッファアタッチメント管理

**新たな問題発見 🔍**
- ❌ **container_gopls が起動していない** - 自動起動ロジックに問題
- ❌ **ホスト gopls が残存** - コンテナ環境でローカルパスにアクセス
- ❌ **パス不整合エラー** - `/Users/ksoichiro/...` が container 内に存在しない

**具体的なエラー:**
```
Error loading workspace folders (expected 1, got 0)
chdir /Users/ksoichiro/...: no such file or directory
No active builds contain /Users/ksoichiro/...: consider opening a new workspace folder
```

**デバッグ結果による新発見 🔍**
- ✅ **container_gopls は起動していた** - 2つのインスタンス（id: 5, 6）が動作中
- ❌ **重複起動問題** - container_gopls が複数起動している
- ❌ **バッファアタッチメント問題** - container_gopls がバッファに正しくアタッチされていない
- ❌ **ホスト gopls が残存** - 停止後に再起動されている可能性

**根本原因の特定 🎯**
- ✅ **container_gopls がローカルパスを受信** - パス変換が機能していない
- ✅ **重複起動が深刻** - 3つのcontainer_goplsが同時実行
- ✅ **エラーの発生源確定** - container_goplsがローカルパス処理でエラー

**エラーメッセージの分析:**
```
Error loading workspace folders (expected 1, got 0)
chdir /Users/ksoichiro/.../go-test-example: no such file or directory
```
→ container_goplsがローカルパス（`/Users/ksoichiro/...`）を受信、コンテナ内で処理失敗

**対策実装 🛠️**
- ✅ **コンテナ単位の重複防止** - `container_init_status[container_id]` でコンテナ毎に制御
- ✅ **積極的な重複削除** - 既存クライアント検出時に即座に重複削除
- ✅ **状態管理の改善** - 複数プロジェクト対応、適切なクリーンアップ機能
- 🔄 **パス変換の調査** - なぜcontainer_goplsがローカルパスを受信するのか

**実装された機能:**
- コンテナ毎の初期化状態管理（"in_progress" | "completed"）
- 異なるコンテナでの独立したcontainer_gopls起動対応
- 状態のクリーンアップ機能（コンテナ停止時）

#### フェーズ1 完了状況 ✅

**解決済みの問題:**
- ✅ **重複起動問題を完全解決** - 3つ → 1つのcontainer_goplsに
- ✅ **バッファアタッチメント確認** - container_goplsが正常にアタッチ
- ✅ **安全な状態管理実装** - コンテナ単位の制御、複数プロジェクト対応
- ✅ **診断メッセージの重複解消** - 複数の診断 → 単一の診断に

**残りのタスク:**
1. 🔄 **パス変換問題の調査** - container_goplsがローカルパス受信の原因特定
2. 📊 **初期診断エラーの解決** - パス変換修正後の診断内容確認
3. 🎯 **フェーズ2への移行準備** - 正常なcontainer_gopls動作の確立

#### 次のアクション
1. ✅ **重複起動解決の成果をコミット** - 安定したLSP状態管理の実装
2. 🔄 **パス変換システムの調査開始** - LspAttachタイミングとworkspace設定の検証
3. 📊 **初期診断エラーの根本解決** - パス変換修正によるエラー解消
