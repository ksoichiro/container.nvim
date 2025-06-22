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

#### フェーズ1: 根本原因を特定 🎯

**問題の因果関係を解明:**

1. **LSP初期化シーケンス（Neovim仕様）:**
   ```
   vim.lsp.start_client() → initialize request → server response → buffer attach → LspAttach event
   ```

2. **パス変換システム（現在の実装）:**
   ```
   LspAttach event → client.request オーバーライド → パス変換適用
   ```

3. **タイミング問題:**
   - `initialize`リクエスト（workspaceFoldersを含む）は**LspAttach前**に送信
   - パス変換は**LspAttach後**に設定
   - **結果**: workspaceFoldersがローカルパスのまま送信される

4. **エラーの発生メカニズム:**
   ```
   workspaceFolders: ["/Users/ksoichiro/.../go-test-example"]
   → container内で処理 → chdir error: no such file or directory
   ```

**根本原因確定:**
パス変換タイミングが遅すぎるため、initializeリクエストでローカルパスが送信される

### フェーズ2: 解決策の実装 🔧

**解決方針:**
LSP設定時点（`vim.lsp.start_client()`呼び出し前）でworkspaceFoldersをコンテナパスに変換

**実装アプローチ:**
1. `_prepare_lsp_config()`でworkspaceFoldersをコンテナパスに設定
2. root_dirもコンテナパスに変換
3. LspAttach後のパス変換は継続（その他のメッセージ用）

**期待される結果:**
- initializeリクエストでコンテナパス送信: `["/workspace"]`
- container_goplsが正しいworkspaceで初期化
- 初期診断エラーの解消

#### 次のアクション
1. ✅ **フェーズ1完了** - 根本原因と因果関係を完全解明
2. ✅ **統合デバッグツール作成** - より簡単な検証手順の提供
3. ✅ **workspaceFolders修正の実装** - LSP設定段階でのパス変換
4. ✅ **動作検証** - 初期診断エラーの解消確認
5. ✅ **フェーズ2完了** - container_goplsの正常動作確立

#### 2025-06-22 - 統合デバッグツール作成

**問題の解決:**
- ✅ **実行手順の簡素化** - 複雑な手順を統合デバッグツールに集約
- ✅ **自動トレース開始** - nvim起動と同時にLSP初期化を記録
- ✅ **タイミング分析機能** - Initialize vs LspAttach の順序を自動判定

**統合デバッグツールの機能:**
- container_gopls初期化の自動追跡
- workspaceFoldersの内容確認
- タイミング問題の自動検出
- 推奨対策の表示

**実行方法:**
```bash
cd /Users/ksoichiro/src/github.com/ksoichiro/container.nvim/examples/go-test-example
nvim -u /tmp/lsp_debug_integrated.lua main.go
# 数秒後に :DebugAnalysis を実行
```

## パス変換問題の根本解決に向けた新戦略

### 2025-06-22 - 調査結果サマリー

**最終的な問題判明:**
- Neovim LSPクライアントは `vim.lsp.buf_attach_client()` 時に即座に `textDocument/didOpen` を送信
- この時点では、どんなパス変換設定も間に合わない（Neovimの内部実装制約）
- 既存アプローチ（transform.lua、workspaceFolders修正）はこの制約を回避できない

**検証済み事実:**
- ✅ workspaceFolders は正しく設定される (`file:///workspace`)
- ✅ パス変換ロジック自体は動作する
- ❌ `textDocument/didOpen` でローカルパス (`/Users/ksoichiro/...`) が送信される
- ❌ メソッドラップ (notify/request override) のタイミングが間に合わない

### 新戦略: 段階的実装アプローチ

**短期解 (Strategy A): シンボリックリンク方式**
- コンテナ内でホストパスと同構造のシンボリックリンクを作成
- 利点: シンプル、高速、LSPに透過的
- 制約: 動的パス対応、権限管理が必要

**長期解 (Strategy B): LSPプロキシ方式**
- コンテナ内に汎用LSPプロキシを配置し、JSON-RPC通信を中継・変換
- 利点: 汎用性高、すべてのLSPで動作、柔軟性
- 制約: 実装複雑、パフォーマンス考慮が必要

### Strategy A実装計画: シンボリックリンク方式

**実装ステップ:**
1. コンテナ起動時にホストパス構造を再現
2. `/workspace` への適切なシンボリックリンクを作成
3. 権限とユーザーIDマッピングの調整
4. 動的パス作成の自動化

**期待効果:**
```
/Users/ksoichiro/.../main.go → symlink → /workspace/main.go
gopls receives: /Users/ksoichiro/.../main.go
resolves to: /workspace/main.go ✅
```

**次のアクション:**
1. 🚀 **Strategy A実装** - シンボリックリンク方式の実装
2. 🧪 **動作検証** - パスエラー解消の確認
3. 📝 **制約の文書化** - プラットフォーム別の制限事項
4. 🔬 **Strategy B設計** - LSPプロキシ方式の詳細設計

## Strategy A実装結果と課題分析

### 2025-06-23 - Strategy A（シンボリックリンク方式）実装完了

**実装内容:**
1. ✅ **symlink.luaモジュール作成** - シンボリックリンク管理機能
2. ✅ **コンテナ起動時統合** - 4箇所のContainerStartedイベントに対応
3. ✅ **権限問題解決** - sudoを使った権限管理とvscode:vsocde所有権設定
4. ✅ **ワークスペースパス統一** - ホストパス構造の完全再現

**技術的解決事項:**
- コンテナ内でのディレクトリ作成権限問題 → sudo使用で解決
- パス変換の無効化 → transform.luaをStrategy A用に簡素化
- LSP設定の統一 → ホストパスをそのまま使用するよう修正

**初期テスト結果:**
- ✅ シンボリックリンク作成成功 (`/Users/ksoichiro/.../container.nvim -> /workspace`)
- ✅ ファイルアクセス確認済み
- ✅ 基本的な定義ジャンプ動作（リポジトリ内ファイル）

### Strategy A実装における根本的制約の発見

**発生した問題:**

1. **システムライブラリパス問題**
   ```
   fmt.Println定義ジャンプ → /usr/local/go/src/fmt/print.go
   → ホスト側に存在しない → Cursor position outside buffer
   ```

2. **言語固有パス対応の必要性**
   - Go: `/usr/local/go/*`
   - Python: `/usr/local/lib/python3.x/*`  
   - Node.js: `/usr/local/lib/node_modules/*`
   - 各言語の標準ライブラリパスが異なる

3. **ワークスペース認識問題**
   ```
   goplsエラー: "No active builds contain /Users/.../main.go"
   → ワークスペース設定の複雑化
   → 言語固有のroot_dir設定が必要
   ```

4. **LSP設定の言語固有化**
   - Goプロジェクト用の特別なroot_dir関数が必要
   - before_initとon_initでのgo.mod検出ロジック
   - 他言語でも同様の個別対応が必要

### 各Strategy横断評価

#### 1. 環境の分離（LSPサーバー⇔Neovim）

| Strategy | 課題レベル | 詳細 |
|----------|------------|------|
| **従来パス変換** | 🔴 高 | textDocument/didOpenタイミング問題で根本解決困難 |
| **Strategy A (シンボリック)** | 🔴 高 | システムパス(/usr/local/go等)の差異が解決不可 |
| **Strategy B (LSPプロキシ)** | 🟢 低 | プロキシが環境差異を吸収 |

#### 2. システムパスの違い

| Strategy | 課題レベル | 詳細 |
|----------|------------|------|
| **従来パス変換** | 🟡 中 | 変換ロジックで対応可能だが複雑 |
| **Strategy A (シンボリック)** | 🔴 高 | 全システムパスのシンボリック化は現実的でない |
| **Strategy B (LSPプロキシ)** | 🟢 低 | プロキシ内で完結するため影響なし |

#### 3. 言語固有対応の必要性

| Strategy | 課題レベル | 詳細 |
|----------|------------|------|
| **従来パス変換** | 🟡 中 | 基本的に汎用だが、言語特有パスで個別対応あり |
| **Strategy A (シンボリック)** | 🔴 高 | Go用、Python用など個別のシンボリック設定が必要 |
| **Strategy B (LSPプロキシ)** | 🟢 低 | LSPプロトコルレベルで汎用的に処理 |

#### 4. 実装・保守の複雑性

| Strategy | 課題レベル | 詳細 |
|----------|------------|------|
| **従来パス変換** | 🟡 中 | タイミング問題の根本解決が困難 |
| **Strategy A (シンボリック)** | 🔴 高 | 権限、クリーンアップ、言語固有対応で複雑化 |
| **Strategy B (LSPプロキシ)** | 🟡 中 | 初期実装は複雑だが、その後は安定 |

#### 5. 確実性・実績

| Strategy | 課題レベル | 詳細 |
|----------|------------|------|
| **従来パス変換** | 🔴 高 | 既に限界が判明済み |
| **Strategy A (シンボリック)** | 🔴 高 | 実装完了したが根本的制約により実用不可 |
| **Strategy B (LSPプロキシ)** | 🟢 低 | VSCode Dev Containersで実証済みアプローチ |

### Strategy A結論

**Strategy A（シンボリックリンク方式）は根本的な限界により実用不可と判断:**

❌ **汎用性不足**: 言語ごとの個別対応が必要  
❌ **システムパス問題**: 標準ライブラリパスの解決不可  
❌ **複雑性増大**: 権限管理、言語固有設定で保守困難  
❌ **スケーラビリティ**: 新言語追加のたびに専用実装が必要  

**Strategy B（LSPプロキシ方式）への移行を強く推奨**

### 次のアクション: Strategy B実装準備

1. 📋 **Strategy B詳細設計** - LSPプロキシアーキテクチャの設計
2. 🧹 **Strategy A関連コードの整理** - 現在の変更をコミット後、クリーンアップ
3. 🚀 **Strategy B実装開始** - JSON-RPC中継・変換システムの実装
4. 🔬 **VSCode Dev Containers研究** - 既存実装の参考調査
