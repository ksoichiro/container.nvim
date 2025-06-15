-- lua/devcontainer/config.lua
-- 設定管理

local M = {}
local log = require('devcontainer.utils.log')

-- デフォルト設定
M.defaults = {
  -- 基本設定
  auto_start = false,
  log_level = 'info',
  container_runtime = 'docker', -- 'docker' or 'podman'
  
  -- devcontainer設定
  devcontainer_path = '.devcontainer',
  dockerfile_path = '.devcontainer/Dockerfile',
  compose_file = '.devcontainer/docker-compose.yml',
  
  -- ワークスペース設定
  workspace = {
    auto_mount = true,
    mount_point = '/workspace',
    exclude_patterns = { '.git', 'node_modules', '.next', '__pycache__' },
  },
  
  -- LSP設定
  lsp = {
    auto_setup = true,
    timeout = 5000,
    port_range = { 8000, 9000 },
    servers = {}, -- Server-specific configurations
    on_attach = nil, -- Custom on_attach function
  },
  
  -- ターミナル設定
  terminal = {
    shell = '/bin/bash',
    height = 15,
    direction = 'horizontal', -- 'horizontal', 'vertical', 'float'
    close_on_exit = false,
  },
  
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
  
  -- ポートフォワーディング
  port_forwarding = {
    auto_forward = true,
    notification = true,
    bind_address = '127.0.0.1',
    common_ports = {3000, 8080, 5000, 3001},
  },
  
  -- Docker設定
  docker = {
    build_args = {},
    network_mode = 'bridge',
    privileged = false,
    init = true,
    remove_orphans = true,
  },
  
  -- 開発設定
  dev = {
    reload_on_change = true,
    debug_mode = false,
  },
}

-- 現在の設定
local current_config = {}

-- 設定の深いコピー
local function deep_copy(t)
  if type(t) ~= 'table' then
    return t
  end
  
  local copy = {}
  for k, v in pairs(t) do
    copy[k] = deep_copy(v)
  end
  return copy
end

-- 設定のマージ
local function merge_config(target, source)
  for key, value in pairs(source) do
    if type(value) == 'table' and type(target[key]) == 'table' then
      merge_config(target[key], value)
    else
      target[key] = value
    end
  end
end

-- 設定の検証
local function validate_config(config)
  local errors = {}
  
  -- ログレベルの検証
  local valid_log_levels = { 'debug', 'info', 'warn', 'error' }
  if not vim.tbl_contains(valid_log_levels, config.log_level:lower()) then
    table.insert(errors, "Invalid log_level: " .. config.log_level)
  end
  
  -- コンテナランタイムの検証
  local valid_runtimes = { 'docker', 'podman' }
  if not vim.tbl_contains(valid_runtimes, config.container_runtime) then
    table.insert(errors, "Invalid container_runtime: " .. config.container_runtime)
  end
  
  -- ターミナル方向の検証
  local valid_directions = { 'horizontal', 'vertical', 'float' }
  if not vim.tbl_contains(valid_directions, config.terminal.direction) then
    table.insert(errors, "Invalid terminal direction: " .. config.terminal.direction)
  end
  
  -- ポート範囲の検証
  if config.lsp.port_range[1] >= config.lsp.port_range[2] then
    table.insert(errors, "Invalid LSP port_range: start port must be less than end port")
  end
  
  -- パスの検証
  if config.workspace.mount_point == "" then
    table.insert(errors, "workspace.mount_point cannot be empty")
  end
  
  return errors
end

-- 設定のセットアップ
function M.setup(user_config)
  user_config = user_config or {}
  
  -- デフォルト設定をコピー
  current_config = deep_copy(M.defaults)
  
  -- ユーザー設定をマージ
  merge_config(current_config, user_config)
  
  -- 設定を検証
  local errors = validate_config(current_config)
  if #errors > 0 then
    for _, error in ipairs(errors) do
      log.error("Configuration error: %s", error)
    end
    return false, errors
  end
  
  -- ログレベルを設定
  log.set_level(current_config.log_level)
  
  log.debug("Configuration loaded successfully")
  return true, current_config
end

-- 現在の設定を取得
function M.get()
  return current_config
end

-- 特定の設定項目を取得
function M.get_value(path)
  local keys = vim.split(path, ".", { plain = true })
  local value = current_config
  
  for _, key in ipairs(keys) do
    if type(value) == 'table' and value[key] ~= nil then
      value = value[key]
    else
      return nil
    end
  end
  
  return value
end

-- 設定項目を更新
function M.set_value(path, new_value)
  local keys = vim.split(path, ".", { plain = true })
  local target = current_config
  
  -- 最後のキー以外まで辿る
  for i = 1, #keys - 1 do
    local key = keys[i]
    if type(target[key]) ~= 'table' then
      target[key] = {}
    end
    target = target[key]
  end
  
  -- 最後のキーで値を設定
  target[keys[#keys]] = new_value
  
  log.debug("Configuration updated: %s = %s", path, vim.inspect(new_value))
end

-- 設定をファイルに保存
function M.save_to_file(filepath)
  local fs = require('devcontainer.utils.fs')
  
  local content = "-- devcontainer.nvim configuration\n"
  content = content .. "return " .. vim.inspect(current_config, {
    indent = "  ",
    depth = 10,
  })
  
  local success, err = fs.write_file(filepath, content)
  if not success then
    log.error("Failed to save configuration: %s", err)
    return false, err
  end
  
  log.info("Configuration saved to %s", filepath)
  return true
end

-- 設定をファイルから読み込み
function M.load_from_file(filepath)
  local fs = require('devcontainer.utils.fs')
  
  if not fs.is_file(filepath) then
    log.warn("Configuration file not found: %s", filepath)
    return false, "File not found"
  end
  
  local content, err = fs.read_file(filepath)
  if not content then
    log.error("Failed to read configuration file: %s", err)
    return false, err
  end
  
  local chunk, load_err = loadstring(content)
  if not chunk then
    log.error("Failed to parse configuration file: %s", load_err)
    return false, load_err
  end
  
  local success, config = pcall(chunk)
  if not success then
    log.error("Failed to execute configuration file: %s", config)
    return false, config
  end
  
  return M.setup(config)
end

-- デフォルト設定にリセット
function M.reset()
  current_config = deep_copy(M.defaults)
  log.info("Configuration reset to defaults")
  return current_config
end

-- 設定の差分を表示
function M.diff_from_defaults()
  local function table_diff(default, current, prefix)
    local diffs = {}
    prefix = prefix or ""
    
    for key, value in pairs(current) do
      local path = prefix == "" and key or prefix .. "." .. key
      
      if default[key] == nil then
        table.insert(diffs, {
          path = path,
          action = "added",
          value = value,
        })
      elseif type(value) == 'table' and type(default[key]) == 'table' then
        local sub_diffs = table_diff(default[key], value, path)
        for _, diff in ipairs(sub_diffs) do
          table.insert(diffs, diff)
        end
      elseif value ~= default[key] then
        table.insert(diffs, {
          path = path,
          action = "changed",
          old_value = default[key],
          new_value = value,
        })
      end
    end
    
    for key, value in pairs(default) do
      local path = prefix == "" and key or prefix .. "." .. key
      if current[key] == nil then
        table.insert(diffs, {
          path = path,
          action = "removed",
          value = value,
        })
      end
    end
    
    return diffs
  end
  
  return table_diff(M.defaults, current_config)
end

-- 設定の詳細を表示
function M.show_config()
  local diffs = M.diff_from_defaults()
  
  print("=== devcontainer.nvim Configuration ===")
  print()
  
  if #diffs == 0 then
    print("Using default configuration")
  else
    print("Differences from defaults:")
    for _, diff in ipairs(diffs) do
      if diff.action == "changed" then
        print(string.format("  %s: %s -> %s", diff.path, 
                          vim.inspect(diff.old_value), 
                          vim.inspect(diff.new_value)))
      elseif diff.action == "added" then
        print(string.format("  +%s: %s", diff.path, vim.inspect(diff.value)))
      elseif diff.action == "removed" then
        print(string.format("  -%s: %s", diff.path, vim.inspect(diff.value)))
      end
    end
  end
  
  print()
  print("Current log level: " .. current_config.log_level)
  print("Container runtime: " .. current_config.container_runtime)
  print()
end

-- 設定のスキーマを取得（補完用）
function M.get_schema()
  local function extract_schema(config, prefix)
    local schema = {}
    prefix = prefix or ""
    
    for key, value in pairs(config) do
      local path = prefix == "" and key or prefix .. "." .. key
      
      if type(value) == 'table' then
        schema[path] = {
          type = "table",
          children = extract_schema(value, path),
        }
      else
        schema[path] = {
          type = type(value),
          default = value,
        }
      end
    end
    
    return schema
  end
  
  return extract_schema(M.defaults)
end

return M

