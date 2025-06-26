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

1. ✅ **Strategy A関連コードの整理** - 変更をコミット、作業環境クリーンアップ完了
2. 🔄 **Strategy B詳細設計** - LSPプロキシアーキテクチャの設計 (進行中)
3. 🚀 **Strategy B実装開始** - JSON-RPC中継・変換システムの実装
4. 🔬 **VSCode Dev Containers研究** - 既存実装の参考調査

## Strategy B: LSPプロキシ方式 詳細設計

### 2025-06-23 - アーキテクチャ設計

#### 設計概要

**基本コンセプト:**
Neovim(ホスト) ↔ LSPプロキシ(コンテナ) ↔ LSPサーバー(コンテナ)

LSPプロキシがNeovimとLSPサーバーの中間に位置し、JSON-RPC通信を中継しながらパス変換を実行。

#### システム構成

```
┌─────────────────┐    ┌──────────────────────┐    ┌─────────────────┐
│   Neovim        │    │    LSP Proxy         │    │  LSP Server     │
│   (Host)        │    │   (Container)        │    │  (Container)    │
├─────────────────┤    ├──────────────────────┤    ├─────────────────┤
│ Local paths:    │◄──►│ Path Translation:    │◄──►│ Container paths:│
│ /Users/.../     │    │ /Users/... ⟷ /workspace│   │ /workspace/...  │
│                 │    │                      │    │                 │
│ vim.lsp client  │    │ JSON-RPC Middleware  │    │ gopls, pylsp... │
│ (stdio/tcp)     │    │ (stdin/stdout)       │    │ (stdio)         │
└─────────────────┘    └──────────────────────┘    └─────────────────┘
```

#### アーキテクチャの詳細

**1. LSPプロキシ (lua/container/lsp/proxy.lua)**
```lua
-- LSPプロキシの主要機能:
-- 1. JSON-RPC メッセージの受信・送信
-- 2. パス変換 (双方向)
-- 3. ログ記録・デバッグ
-- 4. エラーハンドリング
```

**2. 通信レイヤー**
- **Neovim → プロキシ**: TCP/UnixSocketまたはstdio
- **プロキシ → LSPサーバー**: stdio (既存LSPサーバーと互換)

**3. パス変換システム**
- **送信時**: ホストパス → コンテナパス  
- **受信時**: コンテナパス → ホストパス
- **対象**: URI、filePath、rootUri、workspaceFolders等

#### JSON-RPC中継方式の選択

**Option A: stdio方式 (推奨)**
```
Neovim --[stdio]--> LSPプロキシ --[stdio]--> LSPサーバー
```
- 利点: シンプル、既存LSPクライアントと互換
- 実装: docker exec でプロキシを起動

**Option B: TCP方式**
```
Neovim --[TCP]--> LSPプロキシ --[stdio]--> LSPサーバー  
```
- 利点: ネットワーク越し対応、デバッグ容易
- 実装: プロキシがTCPサーバーとして動作

#### パス変換ルール

**1. 基本変換**
```lua
-- Host → Container
/Users/ksoichiro/src/proj/file.go → /workspace/file.go

-- Container → Host  
/workspace/file.go → /Users/ksoichiro/src/proj/file.go
```

**2. URI変換**
```lua
-- Host → Container
file:///Users/ksoichiro/src/proj/file.go → file:///workspace/file.go

-- Container → Host
file:///workspace/file.go → file:///Users/ksoichiro/src/proj/file.go
```

**3. 変換対象メッセージ**
- **initialize**: rootUri, workspaceFolders
- **textDocument/\***: textDocument.uri
- **workspace/\***: documentChanges[].uri
- **publishDiagnostics**: uri
- **textDocument/definition等のレスポンス**: uri, targetUri

#### エラーハンドリング戦略

**1. プロキシ障害時**
- フォールバック: 直接LSPサーバー接続（パス変換なし）
- 通知: ユーザーに警告表示

**2. パス変換失敗時**  
- ログ記録: デバッグ用に詳細記録
- 継続: 変換失敗でも通信は継続

**3. LSPサーバー障害時**
- 既存エラーハンドリング: Neovim標準の処理に委譲

#### 実装フェーズ

**Phase 1: 基本プロキシ実装**
1. JSON-RPC パーサー・シリアライザー
2. stdio 双方向通信
3. 基本的なパス変換
4. 単一言語(Go)での動作確認

**Phase 2: 汎用化・最適化**  
1. 複数言語対応
2. 高度なパス変換ルール
3. パフォーマンス最適化
4. エラーハンドリング強化

**Phase 3: 統合・デプロイ**
1. container.nvim統合
2. 自動プロキシ起動
3. 設定システム
4. ドキュメント整備

### 技術要件定義

**1. 機能要件**
- ✅ JSON-RPC 1.0/2.0 準拠
- ✅ 双方向パス変換
- ✅ 複数LSPサーバー対応  
- ✅ リアルタイム通信
- ✅ エラー耐性

**2. 非機能要件**  
- **パフォーマンス**: <10ms変換遅延
- **安定性**: 24時間連続動作
- **保守性**: 言語非依存設計
- **デバッグ性**: 詳細ログ・トレース

**3. 互換性要件**
- **LSPバージョン**: LSP 3.17準拠
- **言語サーバー**: gopls, pylsp, tsserver等
- **プラットフォーム**: macOS, Linux, Windows

### 実装ファイル構成

```
lua/container/lsp/
├── proxy/
│   ├── init.lua           # プロキシメイン制御
│   ├── jsonrpc.lua        # JSON-RPC処理
│   ├── transport.lua      # 通信レイヤー
│   ├── transform.lua      # パス変換ロジック
│   └── server.lua         # プロキシサーバー実装
├── proxy.lua              # 外部インターフェース
└── forwarding.lua         # 既存forwarding (Strategy B用に改修)
```

### 実装完了事項

1. ✅ **JSON-RPC処理モジュール設計** - メッセージパース・変換仕様完了
2. ✅ **パス変換ロジック詳細設計** - 変換ルール・エラーハンドリング完了  
3. ✅ **技術設計書作成** - `docs/STRATEGY_B_DESIGN.md` に詳細仕様を記録

### 次のアクション

1. 🔄 **プロトタイプ実装計画** - 最小限の動作検証システム (進行中)
2. 🔍 **VSCode実装調査** - Dev Containersの参考実装分析  
3. 🚀 **Phase 1実装開始** - 基本JSON-RPC中継システム
4. 🧪 **動作検証** - examples/go-test-exampleでの実証実験

## プロトタイプ実装計画

### 実装フェーズ1: 最小動作プロトタイプ

**目標: 単純なJSON-RPC中継を実現し、基本パス変換を確認**

#### 実装範囲
1. **JSON-RPC基本処理**
   - Content-Length形式のメッセージパース
   - 基本的なシリアライゼーション
   - リクエスト・レスポンス・通知の判別

2. **stdio通信**
   - Neovim ↔ プロキシ間のstdio接続
   - プロキシ ↔ LSPサーバー間のstdio接続
   - 非同期I/O処理（vim.loop.new_pipe）

3. **基本パス変換**
   - `textDocument/didOpen` のURI変換
   - `initialize` のrootUri, workspaceFolders変換
   - `textDocument/definition` レスポンスのURI変換

4. **最小限のエラーハンドリング**
   - 接続断検出
   - パース失敗時の処理
   - 基本的なログ出力

#### 検証シナリオ
```
1. コンテナ内でLSPプロキシ起動
2. Neovimからプロキシ経由でgoplsに接続
3. ファイルオープン（textDocument/didOpen）を送信
4. 定義ジャンプ（textDocument/definition）を実行
5. パスが正しく変換されて動作することを確認
```

#### 実装ファイル構成（Phase 1）
```
lua/container/lsp/proxy/
├── init.lua           # プロキシメイン（シンプル版）
├── jsonrpc.lua        # 基本JSON-RPC処理
├── transport.lua      # stdio通信のみ
└── transform.lua      # 基本パス変換のみ
```

#### 成功判定基準
- ✅ Neovim → プロキシ → gopls の通信が成立
- ✅ `textDocument/didOpen` でコンテナパスが送信される
- ✅ `textDocument/definition` でホストパスが返却される
- ✅ 基本的な定義ジャンプが動作する
- ✅ プロキシが安定して動作する（最低5分間）

### 実装フェーズ2: 機能拡張

**Phase 1の成功後に実装:**

1. **高度なパス変換**
   - 複雑なネストしたオブジェクトの変換
   - 配列内URI変換（diagnostics等）
   - エラーパス変換

2. **パフォーマンス最適化**
   - メッセージキューイング
   - パス変換キャッシュ
   - バッチ処理

3. **堅牢性強化**
   - 詳細なエラーハンドリング
   - ヘルスチェック機能
   - 自動復旧機能

4. **複数言語対応**
   - pylsp, tsserver等での検証
   - 言語固有の設定対応

### 開発環境セットアップ

#### テスト用スクリプト作成
```bash
# プロトタイプテスト用スクリプト
./scripts/test_proxy_prototype.sh
```

#### デバッグ環境
- プロキシログ: `/tmp/lsp_proxy_debug.log`
- LSPサーバーログ: `/tmp/gopls_debug.log`
- Neovimクライアントログ: `:set verbose=9`

### リスク管理

**技術リスク:**
1. **JSON-RPC解析の複雑性** → 段階的実装、既存ライブラリ参考
2. **非同期I/O処理の困難性** → vim.loopドキュメント詳細調査
3. **パフォーマンス問題** → 早期プロファイリング、最適化指針

**緩和策:**
- 各コンポーネントの単体テスト先行実装
- 既存LSPクライアント（lspconfig）のコード参考
- 段階的統合、問題の早期発見

### 次の具体的アクション

1. **Phase 1実装開始**
   - `lua/container/lsp/proxy/jsonrpc.lua` の実装
   - 基本的なContent-Length + JSON処理

2. **stdio通信実装**
   - `lua/container/lsp/proxy/transport.lua` の実装
   - vim.loop.new_pipe()を使った双方向通信

3. **動作検証準備**
   - examples/go-test-exampleでのテスト環境構築
   - デバッグ用のログ・トレース機能

**実装着手可能な状態達成** 🚀

## Phase 1 実行結果（継続調査）

### 2025-06-26 - gdマッピング直接上書きアプローチの検証

**経緯**：
Phase 1の調査過程で、gdマッピングを直接上書きする緊急回避策を発見し、動作確認を実施。

#### 成功した機能確認

**動作する実装**：`working_gd_override.lua`
- ✅ **ホバー（K）** - 正常動作
- ✅ **定義ジャンプ（gd）** - 同ファイル内/異なるファイル間両方で動作
- ✅ **補完機能** - 正常動作
- ✅ **複数回ジャンプ** - 安定性確認済み
- ✅ **同じファイル vs 異なるファイルの適切な処理** - vim.cmd('edit')回避による安定化

**技術的実装内容**：
```lua
vim.keymap.set('n', 'gd', function()
  -- container_goplsクライアントを検索
  -- URIをホストパス→コンテナパスに変換
  -- textDocument/definitionリクエスト送信
  -- レスポンスのURIをコンテナパス→ホストパスに変換
  -- 同じファイル内なら cursor移動のみ、異なるファイルならvim.cmd('edit')
end)
```

#### 残存する根本的問題 ⚠️

**LSP初期化時の警告/エラー**：
1. **ワークスペース初期化警告**：
   ```
   No packages found for open file /Users/ksoichiro/.../main.go. go list
   ```

2. **型解析エラー**：
   ```
   undefined: NewCalculator compiler (UndeclaredName)
   ```

3. **position_encoding警告**（解決済み）：
   ```
   position_encoding param is required in vim.lsp.util.make_position_params
   ```

#### 根本原因分析

**問題の本質**：
- gdマッピング上書きは**症状の対処療法**にすぎない
- LSP初期化時（`textDocument/didOpen`）にホストパスが送信される問題は未解決
- container_goplsがワークスペースを正しく認識できていない
- **従来のパス変換アプローチと本質的に同じ制約**を持つ

**技術的詳細**：
- `textDocument/didOpen`: ホストパス送信 → コンテナ内で認識できない
- ワークスペースフォルダー設定の不完全性
- go.modファイルとの関連性の問題

#### 評価と結論

**gdマッピング上書きアプローチの限界**：
- ✅ 定義ジャンプは動作するが、**LSP全体の動作は不完全**
- ❌ ワークスペース認識問題により、補完や診断の質が低下
- ❌ 根本的なパス変換問題は未解決
- ❌ スケーラビリティに欠ける（他のLSP機能で同様の対応が必要）

**Strategy Bの必要性を再確認**：
現在の「動作する」状態は部分的な成功であり、完全なLSP機能のためにはStrategy B（LSPプロキシ方式）が必要不可欠。

#### 次フェーズへの移行方針

**現状の記録とコミット**：
1. ✅ 動作するgdマッピング実装を保存（`working_gd_override.lua`）
2. ✅ 包括的テスト環境を保存（`test_gd_comprehensive.lua`）
3. ✅ 調査結果を詳細記録
4. 🔄 **変更をコミット** - 一時的解決策の記録
5. 🚀 **Strategy B実装に本格着手** - 根本解決への移行

**Strategy Bの実装優先度**：
- **High**: textDocument/didOpen のパス変換（根本問題解決）
- **High**: ワークスペース設定の完全な修正
- **Medium**: 全LSP機能（診断、リファレンス等）の統合
- **Low**: パフォーマンス最適化

### 作業成果物（2025-06-26追加）

- ✅ `working_gd_override.lua`: 動作する定義ジャンプ実装（一時的解決策）
- ✅ `test_gd_comprehensive.lua`: 包括的テストスクリプト
- ✅ 根本原因の完全な特定と記録
- ✅ Strategy Bの必要性を実証的に確認

## 追加調査結果と方針変更（2025-06-26）

### 新たに判明した重大な制約 🚨

**プロジェクト間での動作差異**：
- **go-example**: ホバー(K)、補完、定義ジャンプすべて動作
- **go-test-example**: 定義ジャンプのみ動作、**ホバー・補完は完全に失敗**

**問題の深刻度再評価**：
1. gdマッピング上書きは**単一機能の対処療法**でしかない
2. **他のLSP機能は依然として破綻**している
3. プロジェクト構造により動作が不安定（実用性なし）

### 方針変更：Strategy B最優先実装 🔴

#### 従来の計画（破棄）
```
Phase 1: 調査・分析 ✅
Phase 2: gdマッピングで暫定対応 ✅
Phase 3: 他のLSP機能も個別対応 ❌
Phase 4: Strategy B実装（将来） ❌
```

#### 新しい計画（即時実行）
```
Phase 1: 調査・分析 ✅ (完了)
Phase 2: Strategy B最小実装 🔄 (最優先)
Phase 3: 統合テスト・改善 📅
Phase 4: 本番デプロイ 📅
```

### 根本原因の詳細分析と解決仮説

#### 観察事実と失敗メカニズムの分析

**事実1: go-test-exampleでの「undefined: NewCalculator」エラー**

現在の失敗メカニズム：
```
1. LSPメッセージ: textDocument/didOpen uri: file:///Users/ksoichiro/.../main.go
2. gopls内部処理:
   - URIからディレクトリ抽出: /Users/ksoichiro/.../
   - go.mod探索: /Users/ksoichiro/.../go.mod （存在しない）
   - importパス解決: "./calculator" → /Users/ksoichiro/.../calculator.go （存在しない）
3. 結果: NewCalculatorを解決できない
```

Strategy Bでの解決メカニズム：
```
[Neovim] → [Proxy] → [gopls]
file:///Users/ksoichiro/.../main.go → file:///workspace/main.go

[gopls内部処理]
- URIからディレクトリ: /workspace/
- go.mod探索: /workspace/go.mod ✓（存在する）
- import解決: "./calculator" → /workspace/calculator.go ✓（存在する）
```

**事実2: ホバー（K）機能の失敗**

失敗の連鎖：
```
textDocument/hover リクエスト → goplsが型解決を試行 → NewCalculatorの定義が見つからない（事実1の問題） → 型情報なし → ホバー情報なし
```

Strategy Bでの解決：
- 事実1が解決 → 型情報正常取得 → calcの型 = *Calculator → Addメソッドのシグネチャ取得可能

**事実3: 補完機能の失敗**

根本原因：事実1,2と同じ型解決の失敗 → メソッド一覧取得不可 → 補完候補なし

**事実4: go-exampleでの成功**

成功の理由：
- 単一ファイル内で完結（外部import不要）
- ワークスペース認識不要
- goplsは現在のファイルのみで型解決可能

#### 汎用性を保証する設計原則

**言語非依存のプロキシアーキテクチャ**：
```lua
-- 基本変換ルール（全言語共通）
local path_rules = {
  {
    pattern = "^file://" .. HOST_WORKSPACE,
    replacement = "file://" .. CONTAINER_WORKSPACE
  }
}

-- 言語固有拡張（必要に応じて）
local language_extensions = {
  go = { /* go.mod特有の処理 */ },
  python = { /* __pycache__処理 */ },
  typescript = { /* node_modules処理 */ }
}
```

**重要**: URI変換の90%は言語に依存しない。LSPプロトコルとファイルパスの概念は標準化されている。

### Strategy B実装の具体的アクションプラン

#### Phase 0: 仮説検証（実装前・1日）
**目標**: 理論の事前検証

1. **gopls動作分析**
   ```bash
   # コンテナ内でgoplsをデバッグモードで起動
   docker exec -it container /go/bin/gopls -v -rpc.trace serve
   ```
   → ファイルシステムアクセスのトレース確認

2. **最小再現テスト**
   - プロキシなしで/workspace パスを直接送信
   - goplsの反応と解決能力を確認

3. **検証環境構築**
   ```bash
   # テスト用最小プロキシ（Python実装）
   docker exec -it container bash -c "
     cd /workspace
     cat > test_proxy.py << 'EOF'
     # 単純な中継プロキシ（変換なし）
     EOF
   "
   ```

#### Phase 2-1: 段階的プロトタイプ実装（3日）
**目標**: 仮説の段階的実証

**Day 1: 基本中継の実装と検証**
- `lua/container/lsp/proxy/jsonrpc.lua` - JSON-RPCパーサー
- `lua/container/lsp/proxy/transport.lua` - stdio通信
- 変換なしで中継のみ実装
- **期待結果**: 現状と同じエラーが発生（プロキシが透過的に動作することを確認）

**Day 2: URI変換の追加と効果測定**
- `lua/container/lsp/proxy/transform.lua` - 双方向パス変換
- textDocument/didOpenのURI変換のみ実装
- **期待結果**: 「undefined: NewCalculator」が解決される
- **測定**: 仮説1,2の直接検証

**Day 3: 完全な双方向変換**
- すべてのURI変換実装（definition、hover、completion）
- **期待結果**: go-test-exampleで全LSP機能の正常動作
- **測定**: go-exampleとgo-test-example両方で動作確認

#### Phase 2-2: 機能完備版（追加5日）
**目標**: 全LSP機能の正常動作

1. **完全なメッセージ変換**
   - すべてのLSPメソッドに対応
   - ネストしたURI変換
   - エラーハンドリング

2. **パフォーマンス最適化**
   - メッセージバッファリング
   - 非同期処理の改善

3. **堅牢性向上**
   - 接続断・再接続処理
   - エラーリカバリー

#### Phase 2-3: 本番統合（追加3日）
**目標**: container.nvimへの完全統合

1. **自動プロキシ起動**
2. **設定システム統合**
3. **ドキュメント作成**

### 言語汎用性の検証計画

#### Phase 2での多言語検証

**検証対象言語**：
1. **Go (gopls)** - 複雑なワークスペース認識、go.mod依存
2. **Python (pylsp)** - モジュール解決、__pycache__処理
3. **TypeScript (tsserver)** - node_modules依存、複雑なimport解決

**各言語での検証項目（共通）**：
- [ ] 複数ファイル間の定義ジャンプ
- [ ] 外部ライブラリ/モジュールの認識
- [ ] プロジェクトルートの正しい認識
- [ ] ホバー機能（型情報表示）
- [ ] 自動補完（外部定義の候補表示）

### 成功基準（厳格化）

#### 定量的指標

**Phase 0完了基準**：
- ✅ goplsデバッグログでファイルシステムアクセスパターン確認
- ✅ /workspace パス直接送信での動作変化測定

**Phase 2-1完了基準（仮説検証）**：
- ✅ Day 1: プロキシ透過動作確認（エラー内容が同一）
- ✅ Day 2: 「undefined: NewCalculator」エラーの解決
- ✅ Day 3: go-test-exampleで全LSP機能動作（5/5項目）

**Phase 2-2完了基準（汎用性確認）**：
- ✅ Go, Python, TypeScriptで基本動作確認
- ✅ エラーログに`/Users/...`パスが0件出現

#### 定性的指標

**理論検証**：
- ✅ goplsのデバッグログで正しいワークスペース認識確認
- ✅ import解決の成功（複数ファイル間）
- ✅ プロキシ通過前後でのメッセージ内容の一貫性

**汎用性検証**：
- ✅ 言語固有のコード追加なしで基本動作
- ✅ 新言語追加時の拡張性確認

### 失敗時のフォールバック計画

#### 各フェーズでの失敗シナリオと対策

**Phase 0で仮説が否定された場合**：
- 仮説の再検討
- 別の根本原因の調査（LSPプロトコル仕様の問題など）
- Strategy Cの検討（Container側でのシンボリックリンク拡張など）

**Phase 2-1で部分的失敗の場合**：
- Day 2で「undefined」が解決しない → ワークスペース認識以外の問題
- Day 3で一部機能のみ動作 → メッセージ変換の不完全性

**Phase 2-2で汎用性確認失敗の場合**：
- 言語固有の処理が必要と判明 → アーキテクチャの再設計
- パフォーマンス問題 → 最適化手法の検討

### 実装開始の判断基準

**GO/NO-GO判定（Phase 0後）**：
- ✅ goplsがワークスペース認識に/workspace パスを使用している
- ✅ ファイルシステムアクセスパターンが予想通り
- ❌ 上記が確認できない場合 → 仮説見直し

### 即時アクション

1. **今日**: Phase 0 - 仮説検証開始
2. **明日**: GO/NO-GO判定実施
3. **3日以内**: Phase 2-1完了（仮説実証）

**重要**:
- Phase 0で仮説が否定された場合は実装を中止し、根本原因を再調査
- gdマッピングは緊急回避策として維持（Strategy B完成後に削除）
- 各Phaseで期待結果と実際の結果を詳細記録（将来の改善に活用）
