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

- **2025-06-21**: 問題分析、計画策定完了
