-- lua/devcontainer/docker/init.lua
-- Docker操作の抽象化（修正版）

local M = {}
local log = require('devcontainer.utils.log')

-- Docker コマンドの可用性チェック（同期版）
function M.check_docker_availability()
  log.debug("Checking Docker availability (sync)")

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

-- Docker コマンドの可用性チェック（非同期版）
function M.check_docker_availability_async(callback)
  log.debug("Checking Docker availability (async)")

  -- Dockerバージョンチェック
  vim.fn.jobstart({'docker', '--version'}, {
    on_exit = function(_, exit_code, _)
      if exit_code ~= 0 then
        log.error("Docker is not available")
        callback(false, "Docker command not found")
        return
      end

      -- Dockerデーモンチェック
      vim.fn.jobstart({'docker', 'info'}, {
        on_exit = function(_, daemon_exit_code, _)
          if daemon_exit_code ~= 0 then
            log.error("Docker daemon is not running")
            callback(false, "Docker daemon is not running")
          else
            log.info("Docker is available and running")
            callback(true)
          end
        end,
        stdout_buffered = true,
        stderr_buffered = true,
      })
    end,
    stdout_buffered = true,
    stderr_buffered = true,
  })
end

-- 同期的にコマンドを実行
-- 同期的なDocker コマンド実行（互換性のため保持）
function M.run_docker_command(args, opts)
  opts = opts or {}

  -- 引数を適切にシェルエスケープ
  local escaped_args = {}
  for _, arg in ipairs(args) do
    table.insert(escaped_args, vim.fn.shellescape(arg))
  end
  local cmd = "docker " .. table.concat(escaped_args, " ")

  if opts.cwd then
    cmd = "cd " .. vim.fn.shellescape(opts.cwd) .. " && " .. cmd
  end

  log.debug("Executing (sync): %s", cmd)

  local stdout = vim.fn.system(cmd)
  local exit_code = vim.v.shell_error

  return {
    success = exit_code == 0,
    code = exit_code,
    stdout = stdout or "",
    stderr = exit_code ~= 0 and stdout or "",
  }
end

-- 非同期的なDocker コマンド実行
function M.run_docker_command_async(args, opts, callback)
  opts = opts or {}

  local cmd_args = {'docker'}
  for _, arg in ipairs(args) do
    table.insert(cmd_args, arg)
  end

  log.debug("Executing (async): %s", table.concat(cmd_args, " "))

  local stdout_lines = {}
  local stderr_lines = {}

  local job_opts = {
    on_stdout = function(_, data, _)
      if data then
        for _, line in ipairs(data) do
          if line ~= "" then
            table.insert(stdout_lines, line)
          end
        end
      end
    end,
    on_stderr = function(_, data, _)
      if data then
        for _, line in ipairs(data) do
          if line ~= "" then
            table.insert(stderr_lines, line)
          end
        end
      end
    end,
    on_exit = function(_, exit_code, _)
      local result = {
        success = exit_code == 0,
        code = exit_code,
        stdout = table.concat(stdout_lines, "\n"),
        stderr = table.concat(stderr_lines, "\n"),
      }

      if callback then
        vim.schedule(function()
          callback(result)
        end)
      end
    end,
    stdout_buffered = true,
    stderr_buffered = true,
  }

  if opts.cwd then
    job_opts.cwd = opts.cwd
  end

  return vim.fn.jobstart(cmd_args, job_opts)
end

-- Dockerイメージの存在確認
function M.check_image_exists(image_name)
  log.debug("Checking if image exists: %s", image_name)

  local result = M.run_docker_command({"images", "-q", image_name})

  if result.success then
    local image_id = result.stdout:gsub("%s+", "")
    return image_id ~= ""
  else
    log.error("Failed to check image existence: %s", result.stderr or "unknown error")
    return false
  end
end

-- Dockerイメージの存在確認（非同期版）
function M.check_image_exists_async(image_name, callback)
  log.debug("Checking if image exists (async): %s", image_name)

  M.run_docker_command_async({"images", "-q", image_name}, {}, function(result)
    if result.success then
      local image_id = result.stdout:gsub("%s+", "")
      callback(image_id ~= "", image_id)
    else
      log.error("Failed to check image existence: %s", result.stderr or "unknown error")
      callback(false, nil)
    end
  end)
end

-- Dockerイメージのプル（修正版 - 詳細デバッグ付き）
function M.pull_image_async(image_name, on_progress, on_complete)
  log.info("Pulling Docker image (async): %s", image_name)

  -- 開始直後のデバッグ情報
  if on_progress then
    on_progress("Starting image pull...")
    on_progress("   Command: docker pull " .. image_name)
  end

  local stdout_lines = {}
  local stderr_lines = {}
  local start_time = vim.loop.hrtime()
  local job_started = false
  local data_received = false

  log.debug("About to start docker pull job for: %s", image_name)

  local job_id = vim.fn.jobstart({'docker', 'pull', image_name}, {
    on_stdout = function(job_id, data, event)
      log.debug("Docker pull stdout callback triggered (job: %d, event: %s)", job_id, event)
      data_received = true

      if data then
        log.debug("Docker pull stdout data length: %d", #data)
        for i, line in ipairs(data) do
          log.debug("Docker pull stdout[%d]: '%s'", i, line or "<nil>")
          if line and line ~= "" then
            table.insert(stdout_lines, line)
            if on_progress then
              local progress_line = "   [stdout] " .. line
              on_progress(progress_line)

              -- Special handling for common docker pull messages
              if line:match("Pulling") or line:match("Downloading") or line:match("Extracting") or line:match("Pull complete") then
                log.info("Docker pull progress: %s", line)
              end
            end
          end
        end
      else
        log.debug("Docker pull stdout: data is nil")
      end
    end,

    on_stderr = function(job_id, data, event)
      log.debug("Docker pull stderr callback triggered (job: %d, event: %s)", job_id, event)
      data_received = true

      if data then
        log.debug("Docker pull stderr data length: %d", #data)
        for i, line in ipairs(data) do
          log.debug("Docker pull stderr[%d]: '%s'", i, line or "<nil>")
          if line and line ~= "" then
            table.insert(stderr_lines, line)
            if on_progress then
              local progress_line = "   [stderr] " .. line
              on_progress(progress_line)
            end
          end
        end
      else
        log.debug("Docker pull stderr: data is nil")
      end
    end,

    on_exit = function(job_id, exit_code, event)
      local end_time = vim.loop.hrtime()
      local duration = (end_time - start_time) / 1e9 -- seconds

      log.debug("Docker pull exit callback (job: %d, exit_code: %d, event: %s, duration: %.1fs)", job_id, exit_code, event, duration)
      log.debug("Data received during job: %s", tostring(data_received))
      log.debug("Total stdout lines: %d", #stdout_lines)
      log.debug("Total stderr lines: %d", #stderr_lines)

      local result = {
        success = exit_code == 0,
        code = exit_code,
        stdout = table.concat(stdout_lines, "\n"),
        stderr = table.concat(stderr_lines, "\n"),
        duration = duration,
        data_received = data_received
      }

      if exit_code == 0 then
        log.info("Successfully pulled Docker image: %s (%.1fs)", image_name, duration)
        if on_progress then
          on_progress(string.format("✓ Image pull completed (%.1fs)", duration))
        end
      else
        log.error("Failed to pull Docker image: %s (exit code: %d)", image_name, exit_code)
        if on_progress then
          on_progress("✗ Image pull failed (exit code: " .. exit_code .. ")")
        end
      end

      if on_complete then
        vim.schedule(function()
          on_complete(result.success, result)
        end)
      end
    end,

    -- Try without buffering to see if that helps
    stdout_buffered = false,
    stderr_buffered = false,
  })

  log.debug("jobstart returned job_id: %s", tostring(job_id))

  if job_id == 0 then
    log.error("Failed to start docker pull job (jobstart returned 0)")
    if on_progress then
      on_progress("✗ Failed to start docker pull job")
    end
    if on_complete then
      vim.schedule(function()
        on_complete(false, {error = "Failed to start docker pull job"})
      end)
    end
    return nil
  elseif job_id == -1 then
    log.error("Invalid arguments for docker pull job")
    if on_progress then
      on_progress("✗ Invalid arguments for docker pull job")
    end
    if on_complete then
      vim.schedule(function()
        on_complete(false, {error = "Invalid arguments for docker pull job"})
      end)
    end
    return nil
  end

  job_started = true
  log.info("Started docker pull job with ID: %d", job_id)

  if on_progress then
    on_progress("   Pull job started (ID: " .. job_id .. ")")
    on_progress("   Waiting for Docker output...")
  end

  -- 進捗チェックを追加
  local progress_check_count = 0
  local function check_progress()
    progress_check_count = progress_check_count + 1
    local elapsed = (vim.loop.hrtime() - start_time) / 1e9

    -- ジョブがまだ実行中かチェック
    local job_status = vim.fn.jobwait({job_id}, 0)[1]

    if job_status == -1 then -- Still running
      log.debug("Progress check #%d: job still running (%.1fs elapsed, data_received: %s)",
        progress_check_count, elapsed, tostring(data_received))

      if on_progress then
        on_progress(string.format("   [%.0fs] Pull in progress... (check #%d)", elapsed, progress_check_count))

        if not data_received and elapsed > 30 then
          on_progress("   Warning: No data received from Docker yet. This might indicate a problem.")
        end
      end

      -- 10分でタイムアウト
      if elapsed < 600 then
        vim.defer_fn(check_progress, 10000) -- Check every 10 seconds
      else
        log.warn("Docker pull timeout, stopping job: %d", job_id)
        vim.fn.jobstop(job_id)
        if on_progress then
          on_progress("⚠ Image pull timed out (10 minutes)")
        end
        if on_complete then
          vim.schedule(function()
            on_complete(false, {error = "Timeout", duration = elapsed})
          end)
        end
      end
    else
      log.debug("Progress check #%d: job finished with code %d", progress_check_count, job_status)
    end
  end

  -- 最初の進捗チェックを5秒後に開始
  vim.defer_fn(check_progress, 5000)

  return job_id
end

-- Dockerイメージのプル（旧版、互換性のため保持）
function M.pull_image(image_name, on_progress, on_complete)
  log.info("Pulling Docker image: %s", image_name)

  -- 非同期処理をシミュレート
  vim.defer_fn(function()
    local result = M.run_docker_command({"pull", image_name})

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

    local result = M.run_docker_command(args, {cwd = config.base_path})

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
-- コンテナ作成（非同期版）
function M.create_container_async(config, callback)
  log.info("Creating Docker container (async): %s", config.name)

  local args = M._build_create_args(config)

  M.run_docker_command_async(args, {}, function(result)
    if result.success then
      local container_id = result.stdout:gsub("%s+", "")
      log.info("Successfully created container: %s", container_id)
      callback(container_id, nil)
    else
      local error_parts = {}
      if result.stderr and result.stderr ~= "" then
        table.insert(error_parts, "Error output: " .. result.stderr)
      end
      if result.code then
        table.insert(error_parts, "Exit code: " .. tostring(result.code))
      end

      local error_msg = "Docker create command failed"
      if #error_parts > 0 then
        error_msg = error_msg .. " | " .. table.concat(error_parts, " | ")
      end

      log.error("Failed to create container: %s", error_msg)
      callback(nil, error_msg)
    end
  end)
end

-- コンテナ作成引数の構築
function M._build_create_args(config)
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

  -- ワークスペースマウント（デフォルト）
  local workspace_source = config.workspace_source or vim.fn.getcwd()
  local workspace_target = config.workspace_mount or "/workspace"
  table.insert(args, "-v")
  table.insert(args, workspace_source .. ":" .. workspace_target)

  -- イメージ
  table.insert(args, config.image)

  return args
end

-- コンテナ作成（同期版、互換性のため保持）
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

  local result = M.run_docker_command(args)

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

-- コンテナの開始（非同期版）
function M.start_container(container_id, on_ready)
  log.info("Starting container: %s", container_id)

  vim.defer_fn(function()
    local result = M.run_docker_command({"start", container_id})

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

-- コンテナの開始（改良版 - 非ブロッキング）
function M.start_container_async(container_id, callback)
  log.info("Starting container asynchronously: %s", container_id)

  -- コンテナを開始
  local result = M.run_docker_command({"start", container_id})
  if not result.success then
    local error_msg = result.stderr or "unknown error"
    log.error("Failed to start container: %s", error_msg)
    callback(false, error_msg)
    return
  end

  log.info("Container started, checking readiness...")

  -- 非ブロッキングで準備完了を待つ
  local attempts = 0
  local max_attempts = 30

  local function check_ready()
    attempts = attempts + 1

    local status = M.get_container_status(container_id)
    if status == "running" then
      -- 簡単なコマンドで確認
      local test_result = M.run_docker_command({"exec", container_id, "echo", "ready"})
      if test_result.success then
        log.info("Container is ready: %s", container_id)
        callback(true)
        return
      end
    end

    if attempts < max_attempts then
      -- 1秒後に再試行（非ブロッキング）
      vim.defer_fn(check_ready, 1000)
    else
      log.warn("Container readiness check timed out: %s", container_id)
      callback(false, "timeout")
    end
  end

  -- 最初のチェックを開始
  vim.defer_fn(check_ready, 500)
end

-- シンプルなコンテナ起動テスト
function M.start_container_simple(container_id)
  log.info("Starting container (simple): %s", container_id)

  -- コンテナを開始
  local result = M.run_docker_command({"start", container_id})
  if not result.success then
    local error_msg = result.stderr or "unknown error"
    log.error("Failed to start container: %s", error_msg)
    return false, error_msg
  end

  log.info("Container start command completed: %s", container_id)

  -- 状態確認（1回のみ）
  local status = M.get_container_status(container_id)
  return status == "running", status
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
    local result = M.run_docker_command(args)

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
    local result = M.run_docker_command(args)

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

  -- 環境変数をクリアしてコンテナのデフォルト環境を使用（ユーザーのローカルbinも含める）
  table.insert(args, "-e")
  table.insert(args, "PATH=/home/vscode/.local/bin:/usr/local/python/current/bin:/usr/local/bin:/usr/bin:/bin")

  table.insert(args, container_id)

  -- コマンドを分割
  if type(command) == "string" then
    -- シェルコマンドとして実行（適切にエスケープ）
    table.insert(args, "bash")
    table.insert(args, "-c")
    -- コマンド全体を単一の引数として渡す
    table.insert(args, string.format("%s", command))
  elseif type(command) == "table" then
    -- コマンド配列として実行
    for _, cmd_part in ipairs(command) do
      table.insert(args, cmd_part)
    end
  end

  -- デバッグ：実行予定のコマンドをログ出力
  log.debug("Docker exec command: docker %s", table.concat(args, " "))

  vim.defer_fn(function()
    local result = M.run_docker_command(args)

    -- デバッグ：結果をログ出力
    log.debug("Docker exec result: success=%s, code=%s, stdout_len=%s, stderr_len=%s",
      tostring(result.success),
      tostring(result.code),
      tostring(result.stdout and #result.stdout or 0),
      tostring(result.stderr and #result.stderr or 0))

    if opts.on_complete then
      opts.on_complete(result)
    end
  end, 100)
end

-- コンテナの状態取得
function M.get_container_status(container_id)
  log.debug("Getting container status: %s", container_id)

  local result = M.run_docker_command({"inspect", container_id, "--format", "{{.State.Status}}"})

  if result.success then
    return result.stdout:gsub("%s+", "")
  else
    return nil
  end
end

-- コンテナの詳細情報取得
function M.get_container_info(container_id)
  log.debug("Getting container info: %s", container_id)

  local result = M.run_docker_command({"inspect", container_id})

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

  local result = M.run_docker_command(args)

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
    local result = M.run_docker_command(args)
    if opts.on_complete then
      opts.on_complete(result)
    end
  end, 100)
end

return M
