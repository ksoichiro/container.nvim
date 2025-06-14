-- lua/devcontainer/parser.lua
-- devcontainer.json パーサー

local M = {}
local fs = require('devcontainer.utils.fs')
local log = require('devcontainer.utils.log')

-- devcontainer.jsonの検索候補
local DEVCONTAINER_PATHS = {
  '.devcontainer/devcontainer.json',
  '.devcontainer.json',
}

-- 変数の展開パターン
local VARIABLE_PATTERNS = {
  ['${localWorkspaceFolder}'] = function(context)
    return context.workspace_folder or vim.fn.getcwd()
  end,
  ['${localWorkspaceFolderBasename}'] = function(context)
    local workspace = context.workspace_folder or vim.fn.getcwd()
    return fs.basename(workspace)
  end,
  ['${containerWorkspaceFolder}'] = function(context)
    return context.container_workspace or '/workspace'
  end,
  ['${localEnv:([^}]+)}'] = function(context, var_name)
    return os.getenv(var_name) or ''
  end,
}

-- devcontainer.jsonファイルを検索
function M.find_devcontainer_json(start_path)
  start_path = start_path or vim.fn.getcwd()
  
  log.debug("Searching for devcontainer.json from: %s", start_path)
  
  for _, relative_path in ipairs(DEVCONTAINER_PATHS) do
    local found_path = fs.find_file_upward(start_path, relative_path)
    if found_path then
      log.info("Found devcontainer.json: %s", found_path)
      return found_path
    end
  end
  
  log.warn("No devcontainer.json found from path: %s", start_path)
  return nil
end

-- JSONコメントを削除
local function strip_json_comments(content)
  -- 行コメント (//) を削除
  content = content:gsub('//[^\r\n]*', '')
  
  -- ブロックコメント (/* */) を削除
  content = content:gsub('/%*.--%*/', '')
  
  -- 末尾のカンマを削除（JSONCでは許可されている）
  content = content:gsub(',(%s*[%]}])', '%1')
  
  return content
end

-- 変数の展開
local function expand_variables(value, context)
  if type(value) ~= 'string' then
    return value
  end
  
  local result = value
  
  -- 固定パターンの展開
  for pattern, expander in pairs(VARIABLE_PATTERNS) do
    if pattern:match('%(') then
      -- 動的パターン（正規表現）
      result = result:gsub(pattern, function(captured)
        return expander(context, captured)
      end)
    else
      -- 固定パターン
      result = result:gsub(pattern, expander(context), 1)
    end
  end
  
  return result
end

-- 設定値を再帰的に展開
local function expand_config_variables(config, context)
  if type(config) == 'table' then
    local expanded = {}
    for key, value in pairs(config) do
      expanded[key] = expand_config_variables(value, context)
    end
    return expanded
  else
    return expand_variables(config, context)
  end
end

-- JSONの解析
local function parse_json(content)
  -- コメントを削除
  content = strip_json_comments(content)
  
  -- JSONを解析
  local success, result = pcall(vim.json.decode, content)
  if not success then
    return nil, "Failed to parse JSON: " .. result
  end
  
  return result
end

-- Dockerfileパスの解決
local function resolve_dockerfile_path(config, base_path)
  if not config.dockerFile then
    return nil
  end
  
  local dockerfile_path = config.dockerFile
  if not fs.is_absolute_path(dockerfile_path) then
    -- contextからの相対パスかベースパスからの相対パス
    local context_path = config.build and config.build.context or config.context or "."
    if not fs.is_absolute_path(context_path) then
      context_path = fs.join_path(base_path, context_path)
    end
    dockerfile_path = fs.join_path(context_path, dockerfile_path)
  end
  
  return fs.normalize_path(dockerfile_path)
end

-- Docker Composeファイルパスの解決
local function resolve_compose_file_path(config, base_path)
  if not config.dockerComposeFile then
    return nil
  end
  
  local compose_file = config.dockerComposeFile
  if not fs.is_absolute_path(compose_file) then
    compose_file = fs.join_path(base_path, compose_file)
  end
  
  return fs.normalize_path(compose_file)
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
        container_port = port,
        host_port = port,
        protocol = 'tcp',
      })
    elseif type(port) == 'string' then
      -- "8080:3000" or "8080" 形式をパース
      local host_port, container_port = port:match('(%d+):(%d+)')
      if host_port and container_port then
        table.insert(normalized, {
          container_port = tonumber(container_port),
          host_port = tonumber(host_port),
          protocol = 'tcp',
        })
      else
        local single_port = port:match('(%d+)')
        if single_port then
          local port_num = tonumber(single_port)
          table.insert(normalized, {
            container_port = port_num,
            host_port = port_num,
            protocol = 'tcp',
          })
        end
      end
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
      -- "source=...,target=...,type=..." 形式をパース
      local mount_config = {}
      for pair in mount:gmatch('([^,]+)') do
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
  context.workspace_folder = context.workspace_folder or base_path
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
  
  -- Docker Compose使用時のサービス名確認
  if config.dockerComposeFile and not config.service then
    table.insert(errors, "service field is required when using dockerComposeFile")
  end
  
  -- Dockerfileの存在確認
  if config.resolved_dockerfile and not fs.is_file(config.resolved_dockerfile) then
    table.insert(errors, "Dockerfile not found: " .. config.resolved_dockerfile)
  end
  
  -- Docker Composeファイルの存在確認
  if config.resolved_compose_file and not fs.is_file(config.resolved_compose_file) then
    table.insert(errors, "Docker Compose file not found: " .. config.resolved_compose_file)
  end
  
  -- ポート範囲の確認
  for _, port in ipairs(config.normalized_ports or {}) do
    if port.container_port < 1 or port.container_port > 65535 then
      table.insert(errors, "Invalid container port: " .. port.container_port)
    end
    if port.host_port < 1 or port.host_port > 65535 then
      table.insert(errors, "Invalid host port: " .. port.host_port)
    end
  end
  
  return errors
end

-- 設定の正規化（プラグイン内で使用する形式に変換）
function M.normalize_for_plugin(config)
  return {
    name = config.name,
    image = config.image,
    dockerfile = config.resolved_dockerfile,
    compose_file = config.resolved_compose_file,
    service = config.service,
    context = config.context,
    build_args = config.build and config.build.args or {},
    workspace_folder = config.workspaceFolder,
    mounts = config.normalized_mounts,
    ports = config.normalized_ports,
    port_attributes = config.portsAttributes or {},
    environment = config.containerEnv or {},
    remote_user = config.remoteUser,
    post_create_command = config.postCreateCommand,
    post_start_command = config.postStartCommand,
    post_attach_command = config.postAttachCommand,
    features = config.features or {},
    customizations = config.customizations or {},
    force_rebuild = config.build and config.build.forceRebuild or false,
    privileged = config.privileged or false,
    cap_add = config.capAdd or {},
    security_opt = config.securityOpt or {},
    init = config.init,
    overrides = config.overrideCommand,
  }
end

-- プラグイン設定のマージ
function M.merge_with_plugin_config(devcontainer_config, plugin_config)
  local config = require('devcontainer.config')
  
  -- devcontainer.jsonの設定をプラグイン設定にマージ
  if devcontainer_config.customizations and devcontainer_config.customizations.neovim then
    local neovim_config = devcontainer_config.customizations.neovim
    
    -- ネストした設定のマージ
    if neovim_config.settings then
      for key, value in pairs(neovim_config.settings) do
        config.set_value(key, value)
      end
    end
  end
  
  return config.get()
end

return M

