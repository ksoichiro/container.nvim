-- lua/devcontainer/docker/init.lua
-- Docker操作の抽象化

local M = {}
local async = require('devcontainer.utils.async')
local log = require('devcontainer.utils.log')

-- Docker コマンドの可用性チェック
function M.check_docker_availability()
  log.debug("Checking Docker availability")
  
  local result = vim.fn.system("docker --version 2>/dev/null")
  local exit_code = vim.v.shell_error
  
  if exit_code ~= 0 then
    log.error("Docker is not available")
    return false, "Docker command not found"
  end
  
  -- Dockerデーモンの動作確認
  result = vim.fn.system("docker info 2>/dev/null")
  exit_code = vim.v.shell_error
  
  if exit_code ~= 0 then
    log.error("Docker daemon is not running")
    return false, "Docker daemon is not running"
  end
  
  log.info("Docker is available and running")
  return true
end

-- Dockerイメージのビルド
function M.build_image(config, on_progress, on_complete)
  log.info("Building Docker image: %s", config.name)
  
  local args = {"build"}
  
  -- タグの設定
  local tag = config.name:lower():gsub("[^a-z0-9_.-]", "-")
  table.insert(args, "-t")
  table.insert(args, tag)
  
  -- ビルド引数
  if config.build_args then
    for key, value in pairs(config.build_args) do
      table.insert(args, "--build-arg")
      table.insert(args, string.format("%s=%s", key, value))
    end
  end
  
  -- Dockerfileの指定
  if config.dockerfile then
    table.insert(args, "-f")
    table.insert(args, config.dockerfile)
  end
  
  -- ビルドコンテキスト
  local context = config.context or "."
  table.insert(args, context)
  
  log.debug("Docker build command: docker %s", table.concat(args, " "))
  
  return async.run_command("docker", args, {
    on_stdout = function(data)
      if on_progress then
        vim.schedule(function()
          on_progress(data)
        end)
      end
    end,
    on_stderr = function(data)
      log.debug("Docker build stderr: %s", data)
      if on_progress then
        vim.schedule(function()
          on_progress(data)
        end)
      end
    end,
  }, function(result)
    if result.success then
      log.info("Successfully built Docker image: %s", tag)
      config.built_image = tag
    else
      log.error("Failed to build Docker image: %s", result.stderr)
    end
    
    if on_complete then
      vim.schedule(function()
        on_complete(result.success, result)
      end)
    end
  end)
end

-- コンテナの作成
function M.create_container(config)
  log.info("Creating Docker container: %s", config.name)
  
  local args = {"create"}
  
  -- コンテナ名
  local container_name = config.name:lower():gsub("[^a-z0-9_.-]", "-") .. "_devcontainer"
  table.insert(args, "--name")
  table.insert(args, container_name)
  
  -- インタラクティブモード
  table.insert(args, "-it")
  
  -- ワークディレクトリ
  if config.workspace_folder then
    table.insert(args, "-w")
    table.insert(args, config.workspace_folder)
  end
  
  -- 環境変数
  if config.environment then
    for key, value in pairs(config.environment) do
      table.insert(args, "-e")
      table.insert(args, string.format("%s=%s", key, value))
    end
  end
  
  -- ボリュームマウント
  if config.mounts then
    for _, mount in ipairs(config.mounts) do
      table.insert(args, "--mount")
      local mount_str = string.format("type=%s,source=%s,target=%s", 
                                     mount.type, mount.source, mount.target)
      if mount.readonly then
        mount_str = mount_str .. ",readonly"
      end
      if mount.consistency then
        mount_str = mount_str .. ",consistency=" .. mount.consistency
      end
      table.insert(args, mount_str)
    end
  end
  
  -- ポートフォワーディング
  if config.ports then
    for _, port in ipairs(config.ports) do
      table.insert(args, "-p")
      table.insert(args, string.format("%d:%d", port.host_port, port.container_port))
    end
  end
  
  -- 特権モード
  if config.privileged then
    table.insert(args, "--privileged")
  end
  
  -- init プロセス
  if config.init then
    table.insert(args, "--init")
  end
  
  -- ユーザー指定
  if config.remote_user then
    table.insert(args, "--user")
    table.insert(args, config.remote_user)
  end
  
  -- 使用するイメージ
  local image = config.built_image or config.image
  if not image then
    return nil, "No image specified"
  end
  table.insert(args, image)
  
  -- デフォルトコマンド（コンテナを起動状態に保つ）
  table.insert(args, "sleep")
  table.insert(args, "infinity")
  
  log.debug("Docker create command: docker %s", table.concat(args, " "))
  
  local co = coroutine.running()
  local result = nil
  
  async.run_command("docker", args, {}, function(res)
    result = res
    if co then
      coroutine.resume(co)
    end
  end)
  
  if co then
    coroutine.yield()
  end
  
  if result.success then
    local container_id = result.stdout:gsub("%s+", "")
    log.info("Successfully created container: %s (%s)", container_name, container_id)
    return container_id
  else
    log.error("Failed to create container: %s", result.stderr)
    return nil, result.stderr
  end
end

-- コンテナの開始
function M.start_container(container_id, on_ready)
  log.info("Starting container: %s", container_id)
  
  return async.run_command("docker", {"start", container_id}, {}, function(result)
    if result.success then
      log.info("Successfully started container: %s", container_id)
      
      -- コンテナの準備完了を待つ
      M.wait_for_container_ready(container_id, function(ready)
        if on_ready then
          vim.schedule(function()
            on_ready(ready)
          end)
        end
      end)
    else
      log.error("Failed to start container: %s", result.stderr)
      if on_ready then
        vim.schedule(function()
          on_ready(false)
        end)
      end
    end
  end)
end

-- コンテナの停止
function M.stop_container(container_id, timeout)
  timeout = timeout or 30
  log.info("Stopping container: %s", container_id)
  
  local args = {"stop"}
  if timeout then
    table.insert(args, "-t")
    table.insert(args, tostring(timeout))
  end
  table.insert(args, container_id)
  
  return async.run_command("docker", args, {}, function(result)
    if result.success then
      log.info("Successfully stopped container: %s", container_id)
    else
      log.error("Failed to stop container: %s", result.stderr)
    end
  end)
end

-- コンテナの削除
function M.remove_container(container_id, force)
  log.info("Removing container: %s", container_id)
  
  local args = {"rm"}
  if force then
    table.insert(args, "-f")
  end
  table.insert(args, container_id)
  
  return async.run_command("docker", args, {}, function(result)
    if result.success then
      log.info("Successfully removed container: %s", container_id)
    else
      log.error("Failed to remove container: %s", result.stderr)
    end
  end)
end

-- コンテナ内でのコマンド実行
function M.exec_command(container_id, command, opts)
  opts = opts or {}
  log.debug("Executing command in container %s: %s", container_id, command)
  
  local args = {"exec"}
  
  -- インタラクティブモード
  if opts.interactive then
    table.insert(args, "-it")
  else
    table.insert(args, "-i")
  end
  
  -- 作業ディレクトリ
  if opts.workdir then
    table.insert(args, "-w")
    table.insert(args, opts.workdir)
  end
  
  -- ユーザー指定
  if opts.user then
    table.insert(args, "--user")
    table.insert(args, opts.user)
  end
  
  -- 環境変数
  if opts.env then
    for key, value in pairs(opts.env) do
      table.insert(args, "-e")
      table.insert(args, string.format("%s=%s", key, value))
    end
  end
  
  table.insert(args, container_id)
  
  -- コマンドを分割
  if type(command) == "string" then
    -- シェルコマンドとして実行
    table.insert(args, "sh")
    table.insert(args, "-c")
    table.insert(args, command)
  elseif type(command) == "table" then
    -- コマンド配列として実行
    for _, cmd_part in ipairs(command) do
      table.insert(args, cmd_part)
    end
  end
  
  return async.run_command("docker", args, {
    on_stdout = opts.on_stdout,
    on_stderr = opts.on_stderr,
  }, opts.on_complete)
end

-- コンテナの状態取得
function M.get_container_status(container_id)
  log.debug("Getting container status: %s", container_id)
  
  local co = coroutine.running()
  local result = nil
  
  async.run_command("docker", {"inspect", container_id, "--format", "{{.State.Status}}"}, {}, function(res)
    result = res
    if co then
      coroutine.resume(co)
    end
  end)
  
  if co then
    coroutine.yield()
  end
  
  if result.success then
    return result.stdout:gsub("%s+", "")
  else
    return nil
  end
end

-- コンテナの詳細情報取得
function M.get_container_info(container_id)
  log.debug("Getting container info: %s", container_id)
  
  local co = coroutine.running()
  local result = nil
  
  async.run_command("docker", {"inspect", container_id}, {}, function(res)
    result = res
    if co then
      coroutine.resume(co)
    end
  end)
  
  if co then
    coroutine.yield()
  end
  
  if result.success then
    local success, info = pcall(vim.json.decode, result.stdout)
    if success and info[1] then
      return info[1]
    end
  end
  
  return nil
end

-- コンテナのリスト取得
function M.list_containers(filter)
  log.debug("Listing containers with filter: %s", filter or "all")
  
  local args = {"ps", "-a", "--format", "{{.ID}}\\t{{.Names}}\\t{{.Status}}\\t{{.Image}}"}
  
  if filter then
    table.insert(args, "--filter")
    table.insert(args, filter)
  end
  
  local co = coroutine.running()
  local result = nil
  
  async.run_command("docker", args, {}, function(res)
    result = res
    if co then
      coroutine.resume(co)
    end
  end)
  
  if co then
    coroutine.yield()
  end
  
  if result.success then
    local containers = {}
    for line in result.stdout:gmatch("[^\\n]+") do
      local id, name, status, image = line:match("([^\\t]+)\\t([^\\t]+)\\t([^\\t]+)\\t([^\\t]+)")
      if id and name and status and image then
        table.insert(containers, {
          id = id,
          name = name,
          status = status,
          image = image,
        })
      end
    end
    return containers
  else
    return {}
  end
end

-- コンテナの準備完了を待つ
function M.wait_for_container_ready(container_id, callback, max_attempts)
  max_attempts = max_attempts or 30
  local attempts = 0
  
  local function check_ready()
    attempts = attempts + 1
    
    -- コンテナの状態確認
    local status = M.get_container_status(container_id)
    if status == "running" then
      -- 簡単なコマンドを実行して確認
      M.exec_command(container_id, "echo 'ready'", {
        on_complete = function(result)
          if result.success then
            log.debug("Container is ready: %s", container_id)
            callback(true)
          elseif attempts < max_attempts then
            -- 1秒待って再試行
            async.delay(1000, check_ready)
          else
            log.warn("Container readiness check timed out: %s", container_id)
            callback(false)
          end
        end
      })
    elseif attempts < max_attempts then
      -- 1秒待って再試行
      async.delay(1000, check_ready)
    else
      log.warn("Container failed to start: %s", container_id)
      callback(false)
    end
  end
  
  check_ready()
end

-- ログの取得
function M.get_logs(container_id, opts)
  opts = opts or {}
  log.debug("Getting logs for container: %s", container_id)
  
  local args = {"logs"}
  
  if opts.follow then
    table.insert(args, "-f")
  end
  
  if opts.tail then
    table.insert(args, "--tail")
    table.insert(args, tostring(opts.tail))
  end
  
  if opts.since then
    table.insert(args, "--since")
    table.insert(args, opts.since)
  end
  
  table.insert(args, container_id)
  
  return async.run_command("docker", args, {
    on_stdout = opts.on_stdout,
    on_stderr = opts.on_stderr,
  }, opts.on_complete)
end

return M

