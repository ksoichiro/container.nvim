# devcontainer.nvim TODO & 改善点

このファイルは、v0.2.0 LSP統合完了後の今後の改善点と計画を記録します。

## 現在の状況 (v0.2.0完了)

✅ **完了済み**
- 基本的なdevcontainer操作 (v0.1.0)
- LSP統合機能 (v0.2.0)
  - Docker内LSPサーバーの自動検出
  - 非同期Docker操作
  - パス変換機能
  - 再接続機能

## 緊急修正が必要な問題

### 🔴 高優先度

1. **LSP Info でのクライアント表示問題**
   - 現状: `:LspInfo` でdevcontainer内pylspクライアントが表示されない
   - 影響: デバッグ時の状態確認が困難（ただし機能は正常動作）
   - 優先度: 中（実用上の問題は少ない）
   - 修正案: lspconfig との統合改善

### ✅ 修正完了

3. **エラーログのクリーンアップ** ✅
   - 修正済み: すべてのDEBUGプリントをlog.debug()に変更

4. **Docker関数の重複修正** ✅
   - 修正済み: M.M.run_docker_command → M.run_docker_command

5. **起動時の不要なメッセージ表示** ✅
   - 修正済み: 初期化メッセージをdebugレベルに変更

6. **LSP自動アタッチ機能** ✅
   - 実装済み: autocommandによる新規バッファへの自動アタッチ

7. **postCreateCommand サポート** ✅
   - 実装済み: コンテナ作成後に postCreateCommand を自動実行
   - パーサーの正規化によるフィールド名変換(postCreateCommand → post_create_command)に対応

8. **Go環境でのLSP検出問題** ✅
   - 修正済み: LSP検出およびLSP実行時のPATHにGoバイナリパス(/usr/local/go/bin, /go/bin)を追加
   - 暫定対応: 環境固有設定のdevcontainer.json対応が実装されるまでの一時的な修正

### 🟡 中優先度

7. **パフォーマンス最適化**
   - LSPサーバー検出の並列化
   - Docker操作のキャッシュ機能
   - 不要なDocker呼び出しの削減

8. **エラーハンドリング強化**
   - Docker未起動時の適切なエラーメッセージ
   - LSPサーバー起動失敗時の復旧機能
   - ネットワークタイムアウトの処理

## 次のマイルストーン計画

### v0.2.1 (バグ修正リリース) ✅ 完了
- [x] 高優先度問題の修正
  - [x] postCreateCommand サポート実装
  - [x] LSP自動アタッチ機能
  - [x] Go環境でのLSP検出問題修正
- [ ] テストスイートの改善（次回へ延期）
- [ ] ドキュメントの更新（次回へ延期）

### v0.3.0 (ターミナル統合) - 4-6週間

#### 新機能
- [ ] **改良されたターミナル統合**
  - [ ] コンテナ内ターミナルの改善
  - [ ] セッション管理機能
  - [ ] ターミナル履歴の永続化

- [ ] **ポートフォワーディング機能**
  - [ ] 自動ポート検出
  - [ ] 動的フォワーディング
  - [ ] ポート管理UI

- [ ] **Telescope統合**
  - [ ] devcontainerピッカー
  - [ ] コマンド履歴ピッカー
  - [ ] ポート管理ピッカー

- [ ] **外部プラグイン統合**
  - [ ] nvim-test統合（テストコマンドのコンテナ内実行）
  - [ ] nvim-dap統合（デバッガーのコンテナ内実行）
  - [ ] 一般的なコマンド実行プラグインとの統合

#### 技術的改善
- [ ] **設定システムの拡張**
  - [ ] ユーザー設定のバリデーション
  - [ ] 設定の動的変更
  - [ ] プロファイル機能

- [ ] **環境固有設定のdevcontainer.json対応**
  - [ ] 実行時環境変数の設定可能化（PATH、GOPATH等）
  - [ ] postCreateCommand実行時の環境変数カスタマイズ
  - [ ] 言語固有の設定をdevcontainer.jsonで指定
  - [ ] プラグインからハードコードされた環境設定を除去

- [ ] **UI/UX の向上**
  - [ ] ステータスライン表示
  - [ ] 通知システム
  - [ ] プログレス表示の改善

### v0.4.0 (マルチコンテナ対応) - 6-8週間

- [ ] **Docker Compose サポート**
  - [ ] docker-compose.yml の解析
  - [ ] マルチコンテナ環境の管理
  - [ ] サービス間通信

- [ ] **高度なネットワーク機能**
  - [ ] カスタムネットワーク設定
  - [ ] サービスディスカバリー
  - [ ] 負荷分散

### v1.0.0 (安定版リリース) - 3-4ヶ月後

- [ ] **完全なVSCode互換性**
- [ ] **包括的なテストスイート**
- [ ] **完全なドキュメント**
- [ ] **パフォーマンス最適化**

## 外部プラグイン統合の詳細設計

### nvim-test統合
現在、`klen/nvim-test`や`vim-test/vim-test`などのテストプラグインはローカル環境でコマンドを実行しますが、devcontainer環境では以下の統合が必要：

**実装アプローチ:**
- テストプラグインのコマンド実行をフック/オーバーライド
- コンテナが起動している場合は自動的にコンテナ内で実行
- 例: `:TestNearest` → `docker exec container_id go test -run TestFunction`

**対象プラグイン:**
- `klen/nvim-test` 
- `vim-test/vim-test`
- `nvim-neotest/neotest`

### nvim-dap統合
デバッガーもコンテナ内で実行する必要があり、以下が必要：

**実装要件:**
- DAP アダプターの設定をコンテナ内実行用に自動変更
- デバッグポートのフォワーディング
- コンテナ内でのデバッガー起動

### 一般的なコマンド実行統合
他のプラグインでも同様のパターンで統合可能：

**設計パターン:**
```lua
-- プラグイン統合のためのAPI
devcontainer.integrate_command_plugin({
  plugin_name = "nvim-test",
  command_patterns = {"Test*"},
  wrapper_function = function(original_cmd)
    return devcontainer.wrap_command(original_cmd)
  end
})
```

この機能により、開発者はdevcontainer内で完全な開発体験を得られます。

## 環境固有設定の設計改善

### 問題の現状
現在、postCreateCommand実行時の環境変数（PATH、GOPATH等）がプラグイン内にハードコードされており、言語ごとに個別対応が必要になっている。

### 提案する改善案

#### 1. devcontainer.jsonでの環境変数指定
```json
{
  "name": "Go Project",
  "image": "mcr.microsoft.com/devcontainers/go:1-1.23-bookworm",
  "postCreateCommand": "go install golang.org/x/tools/gopls@latest",
  
  "customizations": {
    "devcontainer.nvim": {
      "postCreateEnvironment": {
        "PATH": "/home/vscode/.local/bin:/usr/local/go/bin:/go/bin:$PATH",
        "GOPATH": "/go",
        "GOROOT": "/usr/local/go"
      },
      "execEnvironment": {
        "PATH": "/home/vscode/.local/bin:/usr/local/go/bin:/go/bin:$PATH"
      }
    }
  }
}
```

#### 2. 言語固有のプリセット
```json
{
  "customizations": {
    "devcontainer.nvim": {
      "languagePreset": "go",  // go, python, node, rust等
      "additionalEnvironment": {
        "CUSTOM_VAR": "value"
      }
    }
  }
}
```

#### 3. 実行コンテキスト別設定
- `postCreateEnvironment`: postCreateCommand実行時の環境
- `execEnvironment`: DevcontainerExec実行時の環境  
- `lspEnvironment`: LSP関連コマンド実行時の環境

### 実装の利点
- プラグインから言語固有のハードコードを除去
- ユーザーが環境を完全にコントロール可能
- 新しい言語サポートが容易
- devcontainer.jsonの標準的な拡張パターンに準拠

## 技術的負債と改善案

### アーキテクチャ改善

1. **モジュール間の依存関係整理**
   - 現状: 循環依存が一部存在
   - 改善: 依存関係グラフの最適化

2. **エラーハンドリングの統一**
   - 現状: モジュールごとに異なるエラー処理
   - 改善: 共通エラーハンドリングライブラリ

3. **設定システムの改善**
   - 現状: 設定の検証が不十分
   - 改善: JSON Schema ベースの検証

### パフォーマンス改善

1. **Docker操作の最適化**
   - 不要なDocker呼び出しの削減
   - 結果のキャッシュ
   - 並列処理の活用

2. **LSP通信の最適化**
   - 接続プールの実装
   - リクエストのバッチ処理
   - 応答時間の改善

### 開発体験の改善

1. **デバッグツールの充実**
   - より詳細なログ出力
   - デバッグモードの実装
   - プロファイリング機能

2. **テスト環境の整備**
   - CI/CDパイプライン
   - 自動テスト
   - パフォーマンステスト

## ユーザーフィードバック対応

### よく報告される問題

1. **Docker for Mac でのパフォーマンス問題**
   - ファイルマウントの最適化
   - キャッシュ戦略の改善

2. **Windows 環境での問題**
   - パス区切り文字の処理
   - ファイル権限の問題

3. **大きなプロジェクトでの動作**
   - メモリ使用量の最適化
   - 起動時間の改善

## 開発プロセスの改善

### 品質管理
- [ ] 自動テストの充実
- [ ] コードレビューガイドラインの策定
- [ ] パフォーマンス回帰テスト

### ドキュメント
- [ ] API ドキュメントの自動生成
- [ ] チュートリアルの充実
- [ ] トラブルシューティングガイド

### コミュニティ
- [ ] コントリビューションガイドライン
- [ ] イシューテンプレート
- [ ] ディスカッションフォーラム

---

**最終更新**: 2025-06-15  
**次回レビュー予定**: v0.3.0計画時

このTODOリストは、プロジェクトの進行に合わせて定期的に更新されます。