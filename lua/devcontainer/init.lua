-- lua/devcontainer/init.lua
-- devcontainer.nvim メインエントリーポイント

local M = {}

-- モジュールの遅延読み込み
local config = nil
local parser = nil
local docker = nil
local log = nil

-- 内部状態
local state = {
  initialized = false,
  current_container = nil,
  current_config = nil,
}

-- 設定のセットアップ
function M.setup(user_config)
  log = require('devcontainer.utils.log')
  config = require('devcontainer.config')
  
  local success, result = config.setup(user_config)
  if not success then
    log.error("Failed to setup configuration")
    return false
  end
  
  state.initialized = true
  log.info("devcontainer.nvim initialized successfully")
  return true
end

-- devcontainerを開く
function M.open(path)
  if not state.initialized then
    log.error("Plugin not initialized. Call setup() first.")
    return false
  end
  
  parser = parser or require('devcontainer.parser')
  docker = docker or require('devcontainer.docker')
  
  path = path or vim.fn.getcwd()
  log.info("Opening devcontainer from path: %s", path)
  
  -- Dockerの利用可能性をチェック
  local docker_ok, docker_err = docker.check_docker_availability()
  if not docker_ok then
    log.error("Docker is not available: %s", docker_err)
    return false
  end
  
  -- devcontainer.jsonを検索・解析
  local devcontainer_config, parse_err = parser.find_and_parse(path)
  if not devcontainer_config then
    log.error("Failed to parse devcontainer.json: %s", parse_err)
    return false
  end
  
  -- 設定の検証
  local validation_errors = parser.validate(devcontainer_config)
  if #validation_errors > 0 then
    for _, error in ipairs(validation_errors) do
      log.error("Configuration error: %s", error)
    end
    return false
  end
  
  -- プラグイン用の設定に正規化
  local normalized_config = parser.normalize_for_plugin(devcontainer_config)
  
  -- プラグイン設定とマージ
  parser.merge_with_plugin_config(devcontainer_config, config.get())
  
  state.current_config = normalized_config
  
  log.info("Successfully loaded devcontainer configuration: %s", normalized_config.name)
  return true
end

-- イメージをビルド
function M.build()
  if not state.current_config then
    log.error("No devcontainer configuration loaded")
    return false
  end
  
  docker = docker or require('devcontainer.docker')
  
  log.info("Building devcontainer image")
  
  return docker.build_image(state.current_config, function(data)
    -- プログレス表示
    print(data)
  end, function(success, result)
    if success then
      log.info("Successfully built devcontainer image")
    else
      log.error("Failed to build devcontainer image")
    end
  end)
end

-- コンテナを開始
function M.start()
  if not state.current_config then
    log.error("No devcontainer configuration loaded")
    return false
  end
  
  docker = docker or require('devcontainer.docker')
  
  -- 既存のコンテナをチェック
  local containers = docker.list_containers("name=" .. state.current_config.name)
  local container_id = nil
  
  if #containers > 0 then
    container_id = containers[1].id
    log.info("Found existing container: %s", container_id)
  else
    -- 新しいコンテナを作成
    local create_result, create_err = docker.create_container(state.current_config)
    if not create_result then
      log.error("Failed to create container: %s", create_err)
      return false
    end
    container_id = create_result
  end
  
  state.current_container = container_id
  
  -- コンテナを開始
  docker.start_container(container_id, function(ready)
    if ready then
      log.info("Container is ready: %s", container_id)
      
      -- post-start コマンドの実行
      if state.current_config.post_start_command then
        M.exec(state.current_config.post_start_command)
      end
    else
      log.error("Container failed to become ready")
    end
  end)
  
  return true
end

-- コンテナを停止
function M.stop()
  if not state.current_container then
    log.error("No active container")
    return false
  end
  
  docker = docker or require('devcontainer.docker')
  
  log.info("Stopping container: %s", state.current_container)
  docker.stop_container(state.current_container)
  
  return true
end

-- コンテナでコマンドを実行
function M.exec(command, opts)
  if not state.current_container then
    log.error("No active container")
    return false
  end
  
  docker = docker or require('devcontainer.docker')
  opts = opts or {}
  
  return docker.exec_command(state.current_container, command, opts)
end

-- ターミナルを開く
function M.shell(shell)
  if not state.current_container then
    log.error("No active container")
    return false
  end
  
  shell = shell or "/bin/bash"
  
  -- 新しいターミナルバッファを開く
  vim.cmd("split")
  local term_opts = string.format("docker exec -it %s %s", state.current_container, shell)
  vim.cmd("terminal " .. term_opts)
  vim.cmd("startinsert")
  
  return true
end

-- コンテナの状態を取得
function M.status()
  if not state.current_container then
    print("No active container")
    return nil
  end
  
  docker = docker or require('devcontainer.docker')
  
  local status = docker.get_container_status(state.current_container)
  local info = docker.get_container_info(state.current_container)
  
  print("=== DevContainer Status ===")
  print("Container ID: " .. state.current_container)
  print("Status: " .. (status or "unknown"))
  
  if info then
    print("Image: " .. (info.Config.Image or "unknown"))
    print("Created: " .. (info.Created or "unknown"))
    
    if info.NetworkSettings and info.NetworkSettings.Ports then
      print("Ports:")
      for container_port, host_bindings in pairs(info.NetworkSettings.Ports) do
        if host_bindings then
          for _, binding in ipairs(host_bindings) do
            print(string.format("  %s -> %s:%s", container_port, binding.HostIp, binding.HostPort))
          end
        end
      end
    end
  end
  
  return {
    container_id = state.current_container,
    status = status,
    info = info,
  }
end

-- ログを表示
function M.logs(opts)
  if not state.current_container then
    log.error("No active container")
    return false
  end
  
  docker = docker or require('devcontainer.docker')
  opts = opts or { tail = 100 }
  
  return docker.get_logs(state.current_container, opts)
end

-- 現在の設定を取得
function M.get_config()
  return state.current_config
end

-- 現在のコンテナIDを取得
function M.get_container_id()
  return state.current_container
end

-- プラグインの状態をリセット
function M.reset()
  state.current_container = nil
  state.current_config = nil
  log.info("Plugin state reset")
end

-- デバッグ情報を表示
function M.debug_info()
  print("=== DevContainer Debug Info ===")
  print("Initialized: " .. tostring(state.initialized))
  print("Current container: " .. (state.current_container or "none"))
  print("Current config: " .. (state.current_config and state.current_config.name or "none"))
  
  if config then
    print("\nPlugin configuration:")
    config.show_config()
  end
  
  if state.current_config then
    print("\nDevContainer configuration:")
    print(vim.inspect(state.current_config))
  end
end

return M

