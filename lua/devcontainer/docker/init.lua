-- lua/devcontainer/docker/init.lua
-- Docker操作の抽象化（修正版）

local M = {}
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

-- 同期的にコマンドを実行
local function run_docker_command(args, opts)
  opts = opts or {}
  local cmd = "docker " .. table.concat(args, " ")
  
  if opts.cwd then
    cmd = "cd " .. vim.fn.shellescape(opts.cwd) .. " && " .. cmd
  end
  
  log.debug("Executing: %s", cmd)
  
  local stdout = vim.fn.system(cmd)
  local exit_code = vim.v.shell_error
  
  return {
    success = exit_code == 0,
    code = exit_code,
    stdout = stdout or "",
    stderr = exit_code ~= 0 and stdout or "",
  }
end

-- Dockerイメージの存在確認
function M.check_image_exists(image_name)
  log.debug("Checking if image exists: %s", image_name)
  
  local result = run_docker_command({"images", "-q", image_name})
  
  if result.success then
    local image_id = result.stdout:gsub("%s+", "")
    return image_id ~= ""
  else
    log.error("Failed to check image existence: %s", result.stderr or "unknown error")
    return false
  end
end

-- Dockerイメージのプル
function M.pull_image(image_name, on_progress, on_complete)
  log.info("Pulling Docker image: %s", image_name)

  -- 非同期処理をシミュレート
  vim.defer_fn(function()
    local result = run_docker_command({"pull", image_name})
    
    if result.success then
      log.info("Successfully pulled Docker image: %s", image_name)
    else
      log.error("Failed to pull Docker image: %s", result.stderr)
    end

    if on_complete then
      vim.schedule(function()
        on_complete(result.success, result)
      end)
    end
  end, 100)
end

-- Dockerイメージのビルド
function M.build_image(config, on_progress, on_complete)
  log.info("Building Docker image: %s", config.name)

  vim.defer_fn(function()
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

    local result = run_docker_command(args, {cwd = config.base_path})
    
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
  end, 100)
end

-- イメージの準備（ビルドまたはプル）
function M.prepare_image(config, on_progress, on_complete)
  -- Dockerfileが指定されている場合はビルド
  if config.dockerfile then
    return M.build_image(config, on_progress, on_complete)
  end

  -- imageが指定されている場合
  if config.image then
    -- ローカルにイメージが存在するかチェック
    local exists = M.check_image_exists(config.image)

    if exists then
      log.info("Image already exists locally: %s", config.image)
      config.prepared_image = config.image
      if on_complete then
        vim.schedule(function()
          on_complete(true, {success = true, stdout = "", stderr = ""})
        end)
      end
      return
    else
      -- イメージが存在しない場合はプル
      return M.pull_image(config.image, on_progress, function(success, result)
        if success then
          config.prepared_image = config.image
        end
        if on_complete then
          on_complete(success, result)
        end
      end)
    end
  end

  -- DockerfileもImageも指定されていない場合
  local error_msg = "No dockerfile or image specified"
  log.error(error_msg)
  if on_complete then
    vim.schedule(function()
      on_complete(false, {success = false, stderr = error_msg})
    end)
  end
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

  -- 使用するイメージ（ビルドされたイメージまたは指定されたイメージ）
  local image = config.built_image or config.prepared_image or config.image
  if not image then
    local error_msg = "No image available for container creation"
    log.error(error_msg)
    return nil, error_msg
  end
  table.insert(args, image)

  -- デフォルトコマンド（コンテナを起動状態に保つ）
  table.insert(args, "sleep")
  table.insert(args, "infinity")

  log.debug("Docker create command: docker %s", table.concat(args, " "))

  local result = run_docker_command(args)

  if result.success then
    local container_id = result.stdout:gsub("%s+", "")
    if container_id == "" then
      local error_msg = "Docker create command succeeded but returned empty container ID"
      log.error(error_msg)
      return nil, error_msg
    end
    log.info("Successfully created container: %s (%s)", container_name, container_id)
    return container_id
  else
    -- 詳細なエラー情報を構築
    local error_parts = {}

    -- 基本エラー情報
    table.insert(error_parts, "Docker create command failed")

    -- 終了コード
    if result.code then
      table.insert(error_parts, string.format("Exit code: %d", result.code))
    end

    -- stderr出力
    if result.stderr and result.stderr ~= "" then
      table.insert(error_parts, string.format("Error output: %s", result.stderr:gsub("%s+$", "")))
    end

    -- stdout出力（エラー情報が含まれている場合がある）
    if result.stdout and result.stdout ~= "" then
      table.insert(error_parts, string.format("Standard output: %s", result.stdout:gsub("%s+$", "")))
    end

    -- 実行されたコマンド
    table.insert(error_parts, string.format("Command: docker %s", table.concat(args, " ")))

    local error_msg = table.concat(error_parts, " | ")
    log.error("Failed to create container: %s", error_msg)
    return nil, error_msg
  end
end

-- コンテナの開始
function M.start_container(container_id, on_ready)
  log.info("Starting container: %s", container_id)

  vim.defer_fn(function()
    local result = run_docker_command({"start", container_id})
    
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
      local error_msg = result.stderr or "unknown error"
      log.error("Failed to start container: %s", error_msg)
      if on_ready then
        vim.schedule(function()
          on_ready(false)
        end)
      end
    end
  end, 100)
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

  vim.defer_fn(function()
    local result = run_docker_command(args)
    
    if result.success then
      log.info("Successfully stopped container: %s", container_id)
    else
      log.error("Failed to stop container: %s", result.stderr)
    end
  end, 100)
end

-- コンテナの削除
function M.remove_container(container_id, force)
  log.info("Removing container: %s", container_id)

  local args = {"rm"}
  if force then
    table.insert(args, "-f")
  end
  table.insert(args, container_id)

  vim.defer_fn(function()
    local result = run_docker_command(args)
    
    if result.success then
      log.info("Successfully removed container: %s", container_id)
    else
      log.error("Failed to remove container: %s", result.stderr)
    end
  end, 100)
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

  vim.defer_fn(function()
    local result = run_docker_command(args)
    if opts.on_complete then
      opts.on_complete(result)
    end
  end, 100)
end

-- コンテナの状態取得
function M.get_container_status(container_id)
  log.debug("Getting container status: %s", container_id)

  local result = run_docker_command({"inspect", container_id, "--format", "{{.State.Status}}"})

  if result.success then
    return result.stdout:gsub("%s+", "")
  else
    return nil
  end
end

-- コンテナの詳細情報取得
function M.get_container_info(container_id)
  log.debug("Getting container info: %s", container_id)

  local result = run_docker_command({"inspect", container_id})

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

  local result = run_docker_command(args)

  if result.success then
    local containers = {}
    for line in result.stdout:gmatch("[^\n]+") do
      local id, name, status, image = line:match("([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)")
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
            vim.defer_fn(check_ready, 1000)
          else
            log.warn("Container readiness check timed out: %s", container_id)
            callback(false)
          end
        end
      })
    elseif attempts < max_attempts then
      -- 1秒待って再試行
      vim.defer_fn(check_ready, 1000)
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

  vim.defer_fn(function()
    local result = run_docker_command(args)
    if opts.on_complete then
      opts.on_complete(result)
    end
  end, 100)
end

return M
