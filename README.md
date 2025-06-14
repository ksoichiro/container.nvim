# devcontainer.nvim

VSCodeのDev Containers拡張機能と同様の開発体験をNeovimで提供するプラグインです。

## 特徴

- **devcontainer.json サポート**: VSCodeと完全互換の設定ファイル
- **自動イメージビルド**: Dockerイメージの自動ビルドと管理
- **シームレスな統合**: Neovimターミナルとの完全統合
- **LSP統合**: コンテナ内LSPサーバーの自動検出・設定（将来実装予定）
- **ポートフォワーディング**: 自動ポート転送とポート管理
- **非同期操作**: すべてのDocker操作を非同期で実行

## 必要要件

- Neovim 0.8+
- Docker または Podman
- Git

## インストール

### lazy.nvim

```lua
{
  'ksoichiro/devcontainer.nvim',
  dependencies = {
    'nvim-lua/plenary.nvim', -- 非同期処理用（将来の機能拡張のため）
  },
  config = function()
    require('devcontainer').setup({
      -- 設定オプション
      log_level = 'info',
      container_runtime = 'docker', -- 'docker' or 'podman'
      auto_start = false,
    })
  end,
}
```

### packer.nvim

```lua
use {
  'ksoichiro/devcontainer.nvim',
  requires = {
    'nvim-lua/plenary.nvim',
  },
  config = function()
    require('devcontainer').setup()
  end,
}
```

## 基本的な使用方法

### 1. devcontainer.json の作成

プロジェクトルートに `.devcontainer/devcontainer.json` ファイルを作成します：

```json
{
  "name": "Node.js Development Environment",
  "dockerFile": "Dockerfile",
  "workspaceFolder": "/workspace",
  "mounts": [
    "source=${localWorkspaceFolder},target=/workspace,type=bind"
  ],
  "forwardPorts": [3000, 8080],
  "postCreateCommand": "npm install",
  "postStartCommand": "npm run dev",
  "remoteUser": "node"
}
```

### 2. Dockerfileの作成

`.devcontainer/Dockerfile`:

```dockerfile
FROM node:18

# 必要なツールをインストール
RUN apt-get update && apt-get install -y \
    git \
    curl \
    && rm -rf /var/lib/apt/lists/*

# 作業ディレクトリを設定
WORKDIR /workspace

# ユーザーを作成
RUN useradd -m -s /bin/bash node
USER node
```

### 3. devcontainerの起動

```vim
:DevcontainerOpen
:DevcontainerBuild
:DevcontainerStart
```

## コマンド

### 基本操作

| コマンド | 説明 |
|---------|------|
| `:DevcontainerOpen [path]` | devcontainerを開く |
| `:DevcontainerBuild` | イメージをビルド |
| `:DevcontainerStart` | コンテナを開始 |
| `:DevcontainerStop` | コンテナを停止 |
| `:DevcontainerRestart` | コンテナを再起動 |

### 実行・アクセス

| コマンド | 説明 |
|---------|------|
| `:DevcontainerExec <command>` | コンテナ内でコマンド実行 |
| `:DevcontainerShell [shell]` | コンテナ内のシェルを開く |

### 情報表示

| コマンド | 説明 |
|---------|------|
| `:DevcontainerStatus` | コンテナ状態を表示 |
| `:DevcontainerLogs` | コンテナログを表示 |
| `:DevcontainerConfig` | 設定を表示 |

### 管理

| コマンド | 説明 |
|---------|------|
| `:DevcontainerReset` | プラグイン状態をリセット |
| `:DevcontainerDebug` | デバッグ情報を表示 |

## 設定

### デフォルト設定

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
      error = "❌",
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
    exclude_patterns = { '.git', 'node_modules', '.next' },
  },
})
```

## Lua API

プログラムからプラグインを操作する場合：

```lua
-- 基本操作
require('devcontainer').open()
require('devcontainer').build()
require('devcontainer').start()
require('devcontainer').stop()

-- コマンド実行
require('devcontainer').exec('npm test')
require('devcontainer').shell('/bin/zsh')

-- 情報取得
local status = require('devcontainer').status()
local config = require('devcontainer').get_config()
local container_id = require('devcontainer').get_container_id()
```

## devcontainer.json 設定例

### Node.js プロジェクト

```json
{
  "name": "Node.js Development",
  "dockerFile": "Dockerfile",
  "context": "..",
  "workspaceFolder": "/workspace",
  "mounts": [
    "source=${localWorkspaceFolder},target=/workspace,type=bind,consistency=cached"
  ],
  "forwardPorts": [3000, 8080, 9229],
  "portsAttributes": {
    "3000": {
      "label": "Frontend",
      "onAutoForward": "notify"
    },
    "9229": {
      "label": "Node Debug",
      "onAutoForward": "silent"
    }
  },
  "postCreateCommand": "npm install",
  "postStartCommand": "npm run dev",
  "customizations": {
    "neovim": {
      "settings": {
        "editor.tabSize": 2,
        "editor.insertSpaces": true
      },
      "extensions": [
        "typescript-language-server",
        "eslint-language-server"
      ]
    }
  },
  "features": {
    "ghcr.io/devcontainers/features/node:1": {
      "version": "18"
    },
    "ghcr.io/devcontainers/features/git:1": {}
  },
  "remoteUser": "node"
}
```

### Python プロジェクト

```json
{
  "name": "Python Development",
  "image": "mcr.microsoft.com/devcontainers/python:3.11",
  "workspaceFolder": "/workspace",
  "mounts": [
    "source=${localWorkspaceFolder},target=/workspace,type=bind"
  ],
  "forwardPorts": [8000, 5000],
  "postCreateCommand": "pip install -r requirements.txt",
  "customizations": {
    "neovim": {
      "extensions": [
        "pylsp",
        "mypy"
      ]
    }
  },
  "features": {
    "ghcr.io/devcontainers/features/python:1": {
      "version": "3.11"
    }
  }
}
```

### Docker Compose 使用例

```json
{
  "name": "Web Application",
  "dockerComposeFile": "docker-compose.yml",
  "service": "web",
  "workspaceFolder": "/workspace",
  "forwardPorts": [3000, 8080],
  "postCreateCommand": "npm install && npm run setup"
}
```

## トラブルシューティング

### Dockerが利用できない

```bash
# Dockerの状態確認
docker --version
docker info

# Dockerデーモンの起動
sudo systemctl start docker
```

### コンテナが起動しない

```vim
:DevcontainerLogs
:DevcontainerDebug
```

### 設定ファイルのエラー

```vim
:DevcontainerConfig
```

で設定を確認し、devcontainer.jsonの構文をチェックしてください。

### パフォーマンスの問題

- ビルドキャッシュを使用する
- `.dockerignore` ファイルで不要なファイルを除外
- ボリュームマウントの一貫性設定を調整

## 開発計画

### v0.1.0 (現在)
- ✅ 基本的なdevcontainer操作
- ✅ Docker統合
- ✅ 基本コマンド

### v0.2.0 (計画中)
- 🔄 LSPサーバー統合
- 🔄 ターミナル統合改善
- 🔄 ポートフォワーディング

### v0.3.0 (計画中)
- 📋 Telescope統合
- 📋 ステータス表示強化
- 📋 設定UI

### v1.0.0 (目標)
- 📋 全機能実装
- 📋 包括的テスト
- 📋 完全ドキュメント

## コントリビューション

プルリクエストや Issue の報告を歓迎します！

1. このリポジトリをフォーク
2. フィーチャーブランチを作成 (`git checkout -b feature/amazing-feature`)
3. 変更をコミット (`git commit -m 'Add amazing feature'`)
4. ブランチにプッシュ (`git push origin feature/amazing-feature`)
5. プルリクエストを作成

## ライセンス

MIT License - 詳細は [LICENSE](LICENSE) ファイルを参照してください。

## 関連プロジェクト

- [VS Code Dev Containers](https://code.visualstudio.com/docs/remote/containers)
- [devcontainer/cli](https://github.com/devcontainers/cli)
- [devcontainer/spec](https://github.com/devcontainers/spec)

