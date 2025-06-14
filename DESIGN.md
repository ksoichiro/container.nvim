# devcontainer.nvim プラグイン設計ドキュメント

VSCodeのようにdevcontainerを利用できるNeovimプラグインの包括的な設計ドキュメントです。

## 概要

devcontainer.nvimは、VSCodeのDev Containers拡張機能と同様の開発体験をNeovimで提供するプラグインです。Dockerコンテナ内での開発環境を自動的にセットアップし、LSP、ターミナル、ファイルシステムの統合を実現します。

## アーキテクチャ

### プロジェクト構造

```
devcontainer.nvim/
├── lua/
│   └── devcontainer/
│       ├── init.lua              -- メインエントリーポイント
│       ├── config.lua            -- 設定管理
│       ├── parser.lua            -- devcontainer.json パーサー
│       ├── docker/
│       │   ├── init.lua          -- Docker操作の抽象化
│       │   ├── compose.lua       -- Docker Compose サポート
│       │   └── image.lua         -- イメージビルド/管理
│       ├── container/
│       │   ├── manager.lua       -- コンテナライフサイクル管理
│       │   ├── exec.lua          -- コンテナ内でのコマンド実行
│       │   └── filesystem.lua    -- ファイルシステム操作
│       ├── lsp/
│       │   ├── init.lua          -- LSP統合
│       │   └── forwarding.lua    -- LSPサーバーのポートフォワーディング
│       ├── terminal/
│       │   ├── init.lua          -- ターミナル統合
│       │   └── session.lua       -- セッション管理
│       ├── ui/
│       │   ├── picker.lua        -- telescope/fzf統合
│       │   ├── status.lua        -- ステータス表示
│       │   └── notifications.lua -- 通知システム
│       └── utils/
│           ├── fs.lua            -- ファイルシステムユーティリティ
│           ├── log.lua           -- ログシステム
│           └── async.lua         -- 非同期処理
├── plugin/
│   └── devcontainer.lua          -- プラグイン初期化
├── doc/
│   └── devcontainer.txt          -- ドキュメント
└── README.md
```

## 核となる機能

### 1. devcontainer.json 解析と設定管理

#### config.lua の設計
```lua
local M = {}

M.defaults = {
  auto_start = false,
  dockerfile_path = ".devcontainer/Dockerfile",
  compose_file = ".devcontainer/docker-compose.yml",
  mount_workspace = true,
  forward_ports = true,
  post_create_command = nil,
  extensions = {},
  settings = {},
  container_runtime = 'docker', -- or 'podman'
  log_level = 'info',
}

function M.parse_devcontainer_json(path)
  -- devcontainer.json を解析
  -- VSCode の仕様に準拠した設定を読み込み
  -- 返り値: 解析された設定テーブル
end

function M.merge_config(user_config, devcontainer_config)
  -- ユーザー設定とdevcontainer設定をマージ
  -- 優先順位: devcontainer.json > ユーザー設定 > デフォルト設定
end

function M.validate_config(config)
  -- 設定の妥当性をチェック
  -- 必須フィールドの存在確認
  -- パスの有効性確認
end
```

#### parser.lua の設計
```lua
local M = {}

function M.find_devcontainer_json(start_path)
  -- 指定されたパスから上位ディレクトリを検索
  -- .devcontainer/devcontainer.json を探す
end

function M.parse_json_with_comments(file_path)
  -- JSONCファイルの解析（コメント付きJSON）
  -- VSCodeと同様の仕様をサポート
end

function M.resolve_dockerfile_path(config, base_path)
  -- Dockerfileの相対パスを絶対パスに解決
end

function M.expand_variables(config, context)
  -- ${localWorkspaceFolder} などの変数を展開
end
```

### 2. Docker統合レイヤー

#### docker/init.lua の設計
```lua
local M = {}

function M.check_docker_availability()
  -- Dockerの利用可能性をチェック
  -- dockerコマンドの存在確認
  -- Dockerデーモンの動作確認
end

function M.build_image(config, on_progress, on_complete)
  -- Dockerイメージのビルド
  -- プログレス表示とエラーハンドリング
  -- 非同期実行
end

function M.create_container(config)
  -- コンテナの作成
  -- ボリュームマウント、ポートフォワーディングの設定
  -- 環境変数の設定
end

function M.start_container(container_id)
  -- コンテナの開始
  -- ヘルスチェック
end

function M.exec_command(container_id, command, opts)
  -- コンテナ内でのコマンド実行
  -- 非同期実行とストリーミング出力
  -- 終了コードの取得
end

function M.get_container_status(container_id)
  -- コンテナの状態を取得
  -- running, stopped, paused など
end
```

#### docker/image.lua の設計
```lua
local M = {}

function M.build_from_dockerfile(dockerfile_path, context_path, tag, opts)
  -- Dockerfileからイメージをビルド
  -- ビルドコンテキストの設定
  -- キャッシュ戦略
end

function M.pull_base_image(image_name, on_progress)
  -- ベースイメージのプル
  -- プログレス表示
end

function M.list_images(filter)
  -- ローカルイメージの一覧取得
  -- フィルタリング機能
end

function M.remove_image(image_id, force)
  -- イメージの削除
  -- 依存関係のチェック
end
```

### 3. コンテナ管理

#### container/manager.lua の設計
```lua
local M = {}

function M.create_devcontainer(config)
  -- devcontainerの作成
  -- 設定に基づいたコンテナ設定
  -- ネットワーク設定
end

function M.start_devcontainer(container_id, post_start_command)
  -- devcontainerの開始
  -- post-start コマンドの実行
end

function M.stop_devcontainer(container_id, timeout)
  -- devcontainerの停止
  -- グレースフルシャットダウン
end

function M.remove_devcontainer(container_id, remove_volumes)
  -- devcontainerの削除
  -- ボリュームの削除オプション
end

function M.get_container_info(container_id)
  -- コンテナ情報の取得
  -- IPアドレス、ポート、マウント情報など
end
```

#### container/exec.lua の設計
```lua
local M = {}

function M.exec_interactive(container_id, command, opts)
  -- インタラクティブなコマンド実行
  -- PTYの割り当て
  -- 入出力のストリーミング
end

function M.exec_background(container_id, command, opts)
  -- バックグラウンドでのコマンド実行
  -- ログの取得
end

function M.copy_to_container(container_id, local_path, container_path)
  -- ローカルからコンテナへのファイルコピー
end

function M.copy_from_container(container_id, container_path, local_path)
  -- コンテナからローカルへのファイルコピー
end
```

### 4. LSP統合

#### lsp/init.lua の設計
```lua
local M = {}

function M.setup_lsp_in_container(config, container_id)
  -- コンテナ内のLSPサーバーを検出・設定
  -- 言語別の設定
  -- ポートベースまたはstdio通信の選択
end

function M.create_lsp_client(server_config, container_id)
  -- コンテナ内のLSPサーバーとの通信クライアント作成
  -- nvim-lspconfigとの統合
end

function M.detect_language_servers(container_id, workspace_path)
  -- コンテナ内で利用可能なLSPサーバーの検出
  -- 自動設定
end

function M.forward_lsp_requests(client, request, params)
  -- LSPリクエストのコンテナへの転送
  -- パスの変換処理
end
```

#### lsp/forwarding.lua の設計
```lua
local M = {}

function M.setup_port_forwarding(container_id, ports)
  -- LSPサーバーのポートフォワーディング設定
  -- 動的ポート割り当て
end

function M.create_stdio_bridge(container_id, command)
  -- stdio経由でのLSP通信ブリッジ
  -- プロセス管理
end

function M.transform_file_uris(uri, workspace_mapping)
  -- ファイルURIの変換
  -- ローカルパスとコンテナパスのマッピング
end
```

### 5. ターミナル統合

#### terminal/init.lua の設計
```lua
local M = {}

function M.open_container_terminal(container_id, opts)
  -- コンテナ内のターミナルを開く
  -- Neovimターミナルとの統合
end

function M.create_terminal_session(container_id, shell_command)
  -- ターミナルセッションの作成
  -- セッション管理
end

function M.attach_to_session(session_id)
  -- 既存セッションへのアタッチ
end

function M.list_sessions(container_id)
  -- アクティブなセッションの一覧
end
```

### 6. ユーザーインターフェース

#### コマンド設計
```vim
" 基本操作
:DevcontainerOpen [path]         " devcontainerを開く
:DevcontainerBuild               " イメージをビルド
:DevcontainerRebuild             " イメージを再ビルド
:DevcontainerStart               " コンテナを開始
:DevcontainerStop                " コンテナを停止
:DevcontainerRestart             " コンテナを再起動
:DevcontainerAttach              " コンテナにアタッチ

" コマンド実行
:DevcontainerExec <command>      " コンテナ内でコマンド実行
:DevcontainerShell [shell]       " コンテナ内のシェルを開く

" 情報表示
:DevcontainerStatus              " コンテナ状態を表示
:DevcontainerLogs                " コンテナログを表示
:DevcontainerConfig              " 設定を表示/編集

" ポート管理
:DevcontainerForwardPort <port>  " ポートフォワーディング
:DevcontainerPorts               " フォワード済みポート一覧

" 高度な操作
:DevcontainerReset               " 環境をリセット
:DevcontainerClone <url>         " リポジトリをクローンして開く
```

#### ui/picker.lua の設計（Telescope統合）
```lua
local M = {}

function M.pick_devcontainer()
  -- 利用可能なdevcontainerを選択
  -- プレビュー機能付き
end

function M.pick_container_command()
  -- 実行可能なコマンドを選択
  -- 履歴機能
end

function M.pick_forwarded_ports()
  -- フォワード済みポートを管理
  -- ポートの追加/削除
end

function M.pick_container_files()
  -- コンテナ内ファイルのピッカー
  -- ファイルブラウザ機能
end
```

#### ui/status.lua の設計
```lua
local M = {}

function M.show_container_status()
  -- ステータスラインでのコンテナ状態表示
  -- アイコンと色による視覚的表示
end

function M.show_build_progress(progress_info)
  -- ビルド進行状況の表示
  -- プログレスバー
end

function M.show_port_status(ports)
  -- ポートフォワーディング状態の表示
end
```

### 7. 設定システム

#### プラグイン設定例
```lua
require('devcontainer').setup({
  -- 基本設定
  auto_start = false,
  log_level = 'info',
  container_runtime = 'docker', -- 'docker' or 'podman'
  
  -- UI設定
  ui = {
    use_telescope = true,
    show_notifications = true,
    status_line = true,
    icons = {
      container = "🐳",
      running = "✅",
      stopped = "⏹️",
      building = "🔨",
    },
  },
  
  -- LSP設定
  lsp = {
    auto_setup = true,
    timeout = 5000,
    servers = {
      -- 言語別のLSP設定
      lua = { cmd = "lua-language-server" },
      python = { cmd = "pylsp" },
      javascript = { cmd = "typescript-language-server" },
    },
  },
  
  -- ターミナル設定
  terminal = {
    shell = '/bin/bash',
    height = 15,
    direction = 'horizontal', -- 'horizontal', 'vertical', 'float'
    close_on_exit = false,
  },
  
  -- ポートフォワーディング
  port_forwarding = {
    auto_forward = true,
    notification = true,
    common_ports = {3000, 8080, 5000, 3001},
  },
  
  -- ワークスペース設定
  workspace = {
    auto_mount = true,
    mount_point = '/workspace',
    sync_settings = true,
  },
  
  -- Docker設定
  docker = {
    build_args = {},
    network_mode = 'bridge',
    privileged = false,
    init = true,
  },
  
  -- 開発設定
  dev = {
    reload_on_change = true,
    debug_mode = false,
  },
})
```

#### devcontainer.json サポート
```json
{
  "name": "My Development Environment",
  "dockerFile": "Dockerfile",
  "context": "..",
  "build": {
    "dockerfile": "Dockerfile",
    "context": "..",
    "args": {
      "NODE_VERSION": "18"
    }
  },
  "mounts": [
    "source=${localWorkspaceFolder},target=/workspace,type=bind,consistency=cached"
  ],
  "forwardPorts": [3000, 8080],
  "portsAttributes": {
    "3000": {
      "label": "Frontend",
      "onAutoForward": "notify"
    }
  },
  "postCreateCommand": "npm install && npm run setup",
  "postStartCommand": "npm run dev",
  "remoteUser": "developer",
  "workspaceFolder": "/workspace",
  "customizations": {
    "neovim": {
      "settings": {
        "editor.tabSize": 2,
        "editor.insertSpaces": true
      },
      "extensions": [
        "nvim-lspconfig",
        "nvim-treesitter"
      ],
      "commands": [
        "PlugInstall",
        "TSUpdate"
      ]
    }
  },
  "features": {
    "ghcr.io/devcontainers/features/git:1": {},
    "ghcr.io/devcontainers/features/node:1": {
      "version": "18"
    }
  }
}
```

## 実装フェーズ

### フェーズ1: 基盤実装（4-6週間）
1. **コア機能**
   - devcontainer.json パーサー
   - Docker基本操作（build, run, exec）
   - 設定システム
   - ログシステム

2. **基本UI**
   - コマンドインターフェース
   - ステータス表示
   - エラーハンドリング

3. **テスト環境**
   - 単体テスト
   - 統合テスト
   - サンプルプロジェクト

### フェーズ2: 統合機能（6-8週間）
1. **LSP統合**
   - コンテナ内LSPサーバーの検出
   - nvim-lspconfigとの統合
   - ファイルパスの変換

2. **ターミナル統合**
   - コンテナ内ターミナル
   - セッション管理
   - コマンド履歴

3. **ポートフォワーディング**
   - 自動ポート検出
   - 動的フォワーディング
   - ポート管理UI

### フェーズ3: 高度な機能（4-6週間）
1. **Docker Compose サポート**
   - マルチコンテナ環境
   - サービス間通信
   - 依存関係管理

2. **Telescope統合**
   - ファイルピッカー
   - コマンドピッカー
   - コンテナピッカー

3. **拡張機能**
   - プラグインエコシステム
   - カスタムアクション
   - フック機能

### フェーズ4: 最適化・拡張（2-4週間）
1. **パフォーマンス最適化**
   - 非同期処理の最適化
   - メモリ使用量削減
   - キャッシュ機能

2. **エラーハンドリング強化**
   - 詳細なエラーメッセージ
   - 復旧機能
   - デバッグ支援

3. **ドキュメント整備**
   - ユーザーガイド
   - API documentation
   - チュートリアル

## 技術的考慮事項

### 非同期処理
- `vim.loop` (libuv) を使用したノンブロッキング操作
- Docker APIの非同期呼び出し
- プログレス表示とキャンセル機能
- エラー時の適切な cleanup

### エラーハンドリング
- Docker未インストール時の適切なエラーメッセージ
- ネットワークエラーやタイムアウトの処理
- 部分的失敗時の復旧機能
- ユーザーフレンドリーなエラー表示

### セキュリティ
- Docker socket へのアクセス権限チェック
- コンテナ内でのファイルアクセス制限
- 機密情報の適切な処理
- 権限昇格の防止

### パフォーマンス
- イメージビルドの並列化
- LSP通信の最適化
- ファイルシステム操作の効率化
- メモリ使用量の監視

### 互換性
- 複数のDockerバージョンサポート
- Podmanとの互換性
- 異なるOS（Linux, macOS, Windows）での動作
- VSCode devcontainerとの互換性

## 依存関係

### 必須依存関係
- Neovim 0.8+
- Docker または Podman
- plenary.nvim (非同期処理)

### オプション依存関係
- telescope.nvim (UI拡張)
- nvim-lspconfig (LSP統合)
- nvim-treesitter (シンタックスハイライト)
- which-key.nvim (キーバインド表示)

## テスト戦略

### 単体テスト
- 各モジュールの個別テスト
- モックを使用したDocker操作テスト
- 設定解析のテスト

### 統合テスト
- 実際のDockerコンテナを使用したテスト
- LSP統合のテスト
- エンドツーエンドのワークフローテスト

### パフォーマンステスト
- 大きなプロジェクトでの動作確認
- メモリ使用量の測定
- 応答時間の測定

## リリース計画

### v0.1.0 (MVP)
- 基本的なdevcontainer操作
- Docker統合
- 基本コマンド

### v0.2.0 (LSP統合)
- LSPサーバー統合
- ターミナル統合
- ポートフォワーディング

### v0.3.0 (UI強化)
- Telescope統合
- ステータス表示強化
- 設定UI

### v1.0.0 (安定版)
- 全機能実装
- 包括的テスト
- 完全なドキュメント

この設計により、VSCodeのdevcontainer機能と同等またはそれ以上の開発体験をNeovimで実現できます。段階的な実装により、基本機能から高度な機能まで順次追加していくことが可能です。

