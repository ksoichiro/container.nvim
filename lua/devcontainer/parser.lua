-- lua/devcontainer/parser.lua
-- devcontainer.json の解析

local M = {}
local fs = require('devcontainer.utils.fs')
local log = require('devcontainer.utils.log')

-- JSON文字列のコメントを除去
local function remove_json_comments(content)
  -- 行コメント // を除去
  content = content:gsub('//[^\n]*', '')
  -- ブロックコメント /* */ を除去
  content = content:gsub('/%*.-*/', '')
  return content
end

-- JSON解析
local function parse_json(content)
  content = remove_json_comments(content)

  local success, result = pcall(vim.json.decode, content)
  if not success then
    return nil, "Invalid JSON: " .. result
  end

  return result
end

-- 変数展開
local function expand_variables(str, context)
  if type(str) ~= 'string' then
    return str
  end

  context = context or {}

  -- ${localWorkspaceFolder} の展開
  str = str:gsub('${localWorkspaceFolder}', context.workspace_folder or vim.fn.getcwd())

  -- ${containerWorkspaceFolder} の展開
  str = str:gsub('${containerWorkspaceFolder}', context.container_workspace or '/workspace')

  -- ${localEnv:変数名} の展開
  str = str:gsub('${localEnv:([^}]+)}', function(var_name)
    return os.getenv(var_name) or ''
  end)

  -- ${containerEnv:変数名} の展開（プレースホルダーとして保持）
  str = str:gsub('${containerEnv:([^}]+)}', function(var_name)
    return '${containerEnv:' .. var_name .. '}'
  end)

  return str
end

-- 設定のすべての文字列フィールドで変数展開
local function expand_config_variables(config, context)
  if type(config) ~= 'table' then
    return config
  end

  local result = {}

  for key, value in pairs(config) do
    if type(value) == 'string' then
      result[key] = expand_variables(value, context)
    elseif type(value) == 'table' then
      result[key] = expand_config_variables(value, context)
    else
      result[key] = value
    end
  end

  return result
end

-- devcontainer.jsonファイルの検索
function M.find_devcontainer_json(start_path)
  start_path = start_path or vim.fn.getcwd()

  log.debug("Searching for devcontainer.json from: %s", start_path)

  -- .devcontainer/devcontainer.json を検索
  local devcontainer_path = fs.find_file_upward(start_path, '.devcontainer/devcontainer.json')
  if devcontainer_path then
    return devcontainer_path
  end

  -- devcontainer.json を検索
  devcontainer_path = fs.find_file_upward(start_path, 'devcontainer.json')
  if devcontainer_path then
    return devcontainer_path
  end

  return nil
end

-- Dockerfileパスの解決
local function resolve_dockerfile_path(config, base_path)
  if not config.dockerFile then
    return nil
  end

  local dockerfile_path = config.dockerFile
  if not fs.is_absolute_path(dockerfile_path) then
    dockerfile_path = fs.join_path(base_path, dockerfile_path)
  end

  return fs.resolve_path(dockerfile_path)
end

-- docker-compose.ymlパスの解決
local function resolve_compose_file_path(config, base_path)
  if not config.dockerComposeFile then
    return nil
  end

  local compose_path = config.dockerComposeFile
  if not fs.is_absolute_path(compose_path) then
    compose_path = fs.join_path(base_path, compose_path)
  end

  return fs.resolve_path(compose_path)
end

-- ポート設定の正規化
local function normalize_ports(ports)
  if not ports then
    return {}
  end

  local normalized = {}

  for _, port in ipairs(ports) do
    if type(port) == 'number' then
      table.insert(normalized, {
        host_port = port,
        container_port = port,
        protocol = 'tcp',
      })
    elseif type(port) == 'string' then
      local host_port, container_port = port:match('(%d+):(%d+)')
      if host_port and container_port then
        table.insert(normalized, {
          host_port = tonumber(host_port),
          container_port = tonumber(container_port),
          protocol = 'tcp',
        })
      else
        local single_port = tonumber(port)
        if single_port then
          table.insert(normalized, {
            host_port = single_port,
            container_port = single_port,
            protocol = 'tcp',
          })
        end
      end
    elseif type(port) == 'table' then
      table.insert(normalized, {
        host_port = port.hostPort or port.containerPort,
        container_port = port.containerPort,
        protocol = port.protocol or 'tcp',
      })
    end
  end

  return normalized
end

-- マウント設定の正規化
local function normalize_mounts(mounts, context)
  if not mounts then
    return {}
  end

  local normalized = {}

  for _, mount in ipairs(mounts) do
    if type(mount) == 'string' then
      -- "source=...,target=...,type=..." 形式の文字列を解析
      local mount_config = {}
      for pair in mount:gmatch('[^,]+') do
        local key, value = pair:match('([^=]+)=(.+)')
        if key and value then
          mount_config[key:match('^%s*(.-)%s*$')] = expand_variables(value:match('^%s*(.-)%s*$'), context)
        end
      end

      if mount_config.source and mount_config.target then
        table.insert(normalized, {
          type = mount_config.type or 'bind',
          source = mount_config.source,
          target = mount_config.target,
          readonly = mount_config.readonly == 'true',
          consistency = mount_config.consistency,
        })
      end
    elseif type(mount) == 'table' then
      table.insert(normalized, {
        type = mount.type or 'bind',
        source = expand_variables(mount.source, context),
        target = expand_variables(mount.target, context),
        readonly = mount.readonly or false,
        consistency = mount.consistency,
      })
    end
  end

  return normalized
end

-- devcontainer.jsonを解析
function M.parse(file_path, context)
  context = context or {}

  if not fs.is_file(file_path) then
    return nil, "File not found: " .. file_path
  end

  log.debug("Parsing devcontainer.json: %s", file_path)

  -- ファイル読み取り
  local content, err = fs.read_file(file_path)
  if not content then
    return nil, "Failed to read file: " .. err
  end

  -- JSON解析
  local config, parse_err = parse_json(content)
  if not config then
    return nil, parse_err
  end

  -- ベースパスを設定
  local base_path = fs.dirname(file_path)
  -- workspace_folderは.devcontainerの親ディレクトリ（プロジェクトルート）に設定
  context.workspace_folder = context.workspace_folder or fs.dirname(base_path)
  context.devcontainer_folder = base_path

  -- 変数展開のコンテキストを設定
  context.container_workspace = config.workspaceFolder or '/workspace'

  -- 設定を展開
  config = expand_config_variables(config, context)

  -- パスの解決
  config.resolved_dockerfile = resolve_dockerfile_path(config, base_path)
  config.resolved_compose_file = resolve_compose_file_path(config, base_path)

  -- ポート設定の正規化
  config.normalized_ports = normalize_ports(config.forwardPorts)

  -- マウント設定の正規化
  config.normalized_mounts = normalize_mounts(config.mounts, context)

  -- デフォルト値の設定
  config.name = config.name or "devcontainer"
  config.workspaceFolder = config.workspaceFolder or "/workspace"
  config.remoteUser = config.remoteUser or "root"

  log.info("Successfully parsed devcontainer.json: %s", config.name)
  return config
end

-- devcontainer.jsonの存在確認と解析
function M.find_and_parse(start_path, context)
  local devcontainer_path = M.find_devcontainer_json(start_path)
  if not devcontainer_path then
    return nil, "No devcontainer.json found"
  end

  return M.parse(devcontainer_path, context)
end

-- 設定の検証
function M.validate(config)
  local errors = {}

  -- 必須フィールドの確認
  if not config.name then
    table.insert(errors, "Missing required field: name")
  end

  -- Dockerfileまたはイメージの指定確認
  if not config.dockerFile and not config.image and not config.dockerComposeFile then
    table.insert(errors, "Must specify one of: dockerFile, image, or dockerComposeFile")
  end

  -- ポート設定の検証
  if config.normalized_ports then
    for _, port in ipairs(config.normalized_ports) do
      if not port.container_port or port.container_port <= 0 or port.container_port > 65535 then
        table.insert(errors, "Invalid container port: " .. tostring(port.container_port))
      end
      if not port.host_port or port.host_port <= 0 or port.host_port > 65535 then
        table.insert(errors, "Invalid host port: " .. tostring(port.host_port))
      end
    end
  end

  -- マウント設定の検証
  if config.normalized_mounts then
    for _, mount in ipairs(config.normalized_mounts) do
      if not mount.source or mount.source == "" then
        table.insert(errors, "Mount source cannot be empty")
      end
      if not mount.target or mount.target == "" then
        table.insert(errors, "Mount target cannot be empty")
      end
    end
  end

  return errors
end

-- プラグイン用の設定に正規化
function M.normalize_for_plugin(config)
  local normalized = {}

  -- 基本設定
  normalized.name = config.name or "devcontainer"
  normalized.image = config.image
  normalized.dockerfile = config.resolved_dockerfile
  normalized.context = config.build and config.build.context or "."
  normalized.build_args = config.build and config.build.args or {}
  normalized.workspace_folder = config.workspaceFolder or "/workspace"
  normalized.remote_user = config.remoteUser

  -- 環境変数
  normalized.environment = config.remoteEnv or {}

  -- ポート設定
  normalized.ports = config.normalized_ports or {}

  -- マウント設定
  normalized.mounts = config.normalized_mounts or {}

  -- フィーチャー設定
  normalized.features = config.features or {}

  -- カスタマイゼーション
  normalized.customizations = config.customizations or {}

  -- ライフサイクルコマンド
  normalized.post_create_command = config.postCreateCommand
  normalized.post_start_command = config.postStartCommand
  normalized.post_attach_command = config.postAttachCommand

  -- セキュリティ設定
  normalized.privileged = config.privileged or false
  normalized.cap_add = config.capAdd or {}
  normalized.security_opt = config.securityOpt or {}
  normalized.init = config.init

  -- その他のDocker設定
  normalized.run_args = config.runArgs or {}
  normalized.override_command = config.overrideCommand
  normalized.shutdown_action = config.shutdownAction

  -- 強制リビルドフラグ
  normalized.force_rebuild = false

  -- ポート属性
  normalized.port_attributes = config.portsAttributes or {}

  return normalized
end

-- プラグイン設定とのマージ
function M.merge_with_plugin_config(devcontainer_config, plugin_config)
  -- プラグイン設定で上書き可能な項目
  if plugin_config.container_runtime then
    devcontainer_config.container_runtime = plugin_config.container_runtime
  end

  if plugin_config.log_level then
    devcontainer_config.log_level = plugin_config.log_level
  end

  -- プラグイン固有の設定をマージ
  devcontainer_config.plugin_config = plugin_config

  return devcontainer_config
end

return M

