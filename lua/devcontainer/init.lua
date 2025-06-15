-- lua/devcontainer/init.lua
-- devcontainer.nvim メインエントリーポイント

local M = {}

-- モジュールの遅延読み込み
local config = nil
local parser = nil
local docker = nil
local log = nil
local lsp = nil

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
  log.debug("devcontainer.nvim initialized successfully")

  -- 既存のコンテナを自動検出して再接続を試みる
  vim.defer_fn(function()
    M._try_reconnect_existing_container()
  end, 1000)

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
  log.debug("Config has postCreateCommand: %s", tostring(normalized_config.postCreateCommand ~= nil))
  log.debug("Config has post_create_command: %s", tostring(normalized_config.post_create_command ~= nil))
  if normalized_config.postCreateCommand then
    log.debug("postCreateCommand: %s", normalized_config.postCreateCommand)
  end
  if normalized_config.post_create_command then
    log.debug("post_create_command: %s", normalized_config.post_create_command)
  end
  return true
end

-- イメージを準備（ビルドまたはプル）
function M.build()
  if not state.current_config then
    log.error("No devcontainer configuration loaded")
    return false
  end

  docker = docker or require('devcontainer.docker')

  log.info("Preparing devcontainer image")

  return docker.prepare_image(state.current_config, function(data)
    -- プログレス表示
    print(data)
  end, function(success, result)
    if success then
      log.info("Successfully prepared devcontainer image")
    else
      log.error("Failed to prepare devcontainer image: %s", result.stderr or "unknown error")
    end
  end)
end

-- コンテナを開始（完全非同期版）
function M.start()
  if not state.current_config then
    log.error("No devcontainer configuration loaded")
    return false
  end

  docker = docker or require('devcontainer.docker.init')

  log.info("Starting devcontainer...")
  print("=== DevContainer Start (Async) ===")

  -- イメージが準備されているかチェック
  local has_image = state.current_config.built_image or
                   state.current_config.prepared_image or
                   state.current_config.image

  if not has_image then
    log.info("Image not prepared, building/pulling first...")
    print("Building/pulling image... This may take a while.")
    print("Note: Image building is not yet fully async. This may take time.")
    M.build()
    return true
  end

  -- Docker可用性確認（非同期）
  print("Step 1: Checking Docker...")
  docker.check_docker_availability_async(function(available, err)
    vim.schedule(function()
      if not available then
        print("✗ Docker not available: " .. (err or "unknown"))
        return
      end
      print("✓ Docker is available")

      -- 既存のコンテナをチェック（非同期）
      print("Step 2: Checking for existing containers...")
      M._list_containers_async("name=" .. state.current_config.name, function(containers)
        vim.schedule(function()
          local container_id = nil

          if #containers > 0 then
            container_id = containers[1].id
            log.info("Found existing container: %s", container_id)
            print("✓ Found existing container: " .. container_id)
            state.current_container = container_id

            -- コンテナ起動へ進む
            M._start_final_step(container_id)
          else
            -- 新しいコンテナを作成（非同期）
            print("Step 3: Creating new container...")
            M._create_container_full_async(state.current_config, function(create_result, create_err)
              vim.schedule(function()
                if not create_result then
                  log.error("Failed to create container: %s", create_err)
                  print("✗ Failed to create container: " .. (create_err or "unknown"))
                  return
                end
                container_id = create_result
                print("✓ Created container: " .. container_id)
                state.current_container = container_id

                -- コンテナ起動へ進む
                M._start_final_step(container_id)
              end)
            end)
          end
        end)
      end)
    end)
  end)

  print("DevContainer start initiated (non-blocking)...")
  return true
end

-- 最終ステップ: コンテナ起動とセットアップ
function M._start_final_step(container_id)
  print("Step 4: Starting container...")
  docker = docker or require('devcontainer.docker.init')

  docker.start_container_async(container_id, function(success, error_msg)
    vim.schedule(function()
      if success then
        print("✓ Container started successfully!")
        log.info("Container is ready: %s", container_id)

        -- postCreateCommand の実行
        M._run_post_create_command(container_id, function(post_create_success)
          if not post_create_success then
            print("⚠ Warning: postCreateCommand failed, but continuing...")
          end

          -- LSP統合のセットアップ
          if config.get_value('lsp.auto_setup') then
            print("Step 5: Setting up LSP...")
            lsp = lsp or require('devcontainer.lsp.init')
            lsp.setup(config.get_value('lsp'))
            lsp.set_container_id(container_id)

            -- パスマッピングの設定
            local lsp_path = require('devcontainer.lsp.path')
            lsp_path.setup(
              vim.fn.getcwd(),
              state.current_config.workspace_mount or '/workspace',
              state.current_config.mounts or {}
            )

            -- LSPサーバーのセットアップ
            lsp.setup_lsp_in_container()
            print("✓ LSP setup complete!")
          end
        end) -- _run_post_create_command callback終了

        -- post-start コマンドの実行（既存）
        if state.current_config.post_start_command then
          print("Step 6: Running post-start command...")
          M.exec(state.current_config.post_start_command)
        end

        print("=== DevContainer is ready! ===")
      else
        log.error("Failed to start container")
        print("✗ Failed to start container: " .. (error_msg or "unknown"))
      end
    end)
  end)
end

-- 本格的なコンテナ作成（完全非同期版）
function M._create_container_full_async(config, callback)
  local docker = require('devcontainer.docker.init')

  -- Step 1: イメージ存在確認
  print("Step 3a: Checking if image exists locally...")
  docker.check_image_exists_async(config.image, function(exists, image_id)
    vim.schedule(function()
      if exists then
        print("✓ Image found locally: " .. config.image)
        -- イメージがあるので直接コンテナ作成
        M._create_container_direct(config, callback)
      else
        print("⚠ Image not found locally, pulling: " .. config.image)
        -- イメージをプルしてからコンテナ作成
        M._pull_and_create_container(config, callback)
      end
    end)
  end)
end

-- イメージプル後にコンテナ作成
function M._pull_and_create_container(config, callback)
  local docker = require('devcontainer.docker.init')

  print("Step 3b: Pulling image (this may take a while)...")
  print("   Image: " .. config.image)
  print("   This is a large download and may take 5-15 minutes depending on your connection.")
  print("   Progress will be shown below. You can continue using Neovim while this runs.")
  print("   Note: If no progress appears after 30 seconds, there may be an issue.")

  local start_time = vim.fn.reltime()
  local progress_count = 0

  local job_id = docker.pull_image_async(
    config.image,
    function(progress)
      progress_count = progress_count + 1
      local elapsed = vim.fn.reltimestr(vim.fn.reltime(start_time))
      print(string.format("   [%ss] %s", elapsed, progress))

      -- 進捗が見えていることを確認
      if progress_count == 1 then
        print("   ✓ Docker pull output started - progress tracking is working")
      end
    end,
    function(success, result)
      vim.schedule(function()
        local elapsed = vim.fn.reltimestr(vim.fn.reltime(start_time))
        print(string.format("   [%ss] Pull completed with status: %s", elapsed, tostring(success)))

        if success then
          print("✓ Image pull completed successfully!")
          print("   Now proceeding to create container...")
          -- イメージプル成功、コンテナ作成
          M._create_container_direct(config, callback)
        else
          print("✗ Image pull failed:")

          if result then
            if result.stderr and result.stderr ~= "" then
              print("   Error output: " .. result.stderr)
            end
            if result.error then
              print("   Error: " .. result.error)
            end
            if result.data_received == false then
              print("   Issue: No data was received from Docker command")
              print("   This suggests Docker may be unresponsive or the image name is invalid")
            end
            if result.duration then
              print(string.format("   Duration: %.1f seconds", result.duration))
            end
          end

          print("   Troubleshooting steps:")
          print("   1. Check your internet connection")
          print("   2. Verify the image name: " .. config.image)
          print("   3. Try manually: docker pull " .. config.image)
          print("   4. Check if Docker daemon is responsive: docker info")
          print("   5. Use :DevcontainerTestPull for isolated testing")

          callback(nil, "Failed to pull image: " .. (result and result.stderr or result and result.error or "unknown"))
        end
      end)
    end
  )

  if job_id and job_id > 0 then
    print("   ✓ Pull job started successfully (ID: " .. job_id .. ")")
    print("   Tip: Use :messages to see all progress, or :DevcontainerTestPull for testing")

    -- 30秒後に進捗チェック
    vim.defer_fn(function()
      if progress_count == 0 then
        print("   ⚠ Warning: No progress received after 30 seconds")
        print("   This may indicate a Docker or network issue")
        print("   Try :DevcontainerTestPull or manual 'docker pull " .. config.image .. "'")
      end
    end, 30000)
  else
    print("   ✗ Failed to start pull job (job_id: " .. tostring(job_id) .. ")")
    callback(nil, "Failed to start Docker pull job")
  end
end

-- 直接コンテナ作成
function M._create_container_direct(config, callback)
  local docker = require('devcontainer.docker.init')

  print("Step 3c: Creating container...")
  docker.create_container_async(config, function(container_id, error_msg)
    if container_id then
      print("✓ Container created successfully: " .. container_id)
    else
      print("✗ Container creation failed: " .. (error_msg or "unknown"))
    end
    callback(container_id, error_msg)
  end)
end

-- コンテナを停止
function M.stop()
  if not state.current_container then
    log.error("No active container")
    return false
  end

  docker = docker or require('devcontainer.docker')

  -- LSPクライアントを停止
  if lsp then
    lsp.stop_all()
  end

  log.info("Stopping container: %s", state.current_container)
  docker.stop_container(state.current_container)

  return true
end

-- コンテナでコマンドを実行
function M.exec(command, opts)
  if not state.current_container then
    print("✗ No active container")
    log.error("No active container")
    return false
  end

  docker = docker or require('devcontainer.docker.init')
  opts = opts or {}

  -- Use the remote user from devcontainer config if available
  if state.current_config and state.current_config.remote_user and not opts.user then
    opts.user = state.current_config.remote_user
  end

  print("Executing in container: " .. command)
  if opts.user then
    print("  As user: " .. opts.user)
  end

  -- Add callback to display output
  opts.on_complete = function(result)
    vim.schedule(function()
      if result.success then
        if result.stdout and result.stdout ~= "" then
          print("=== Command Output ===")
          for line in result.stdout:gmatch("[^\n]+") do
            print(line)
          end
        else
          print("Command completed (no output)")
        end
      else
        print("✗ Command failed:")
        if result.stderr and result.stderr ~= "" then
          for line in result.stderr:gmatch("[^\n]+") do
            print("Error: " .. line)
          end
        else
          print("No error details available")
        end
      end
    end)
  end

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

-- LSPの状態を取得
function M.lsp_status()
  -- LSPモジュールを初期化（まだされていない場合）
  if not lsp then
    log = log or require('devcontainer.utils.log')
    config = config or require('devcontainer.config')

    if not state.initialized then
      log.warn("Plugin not fully initialized")
      return nil
    end

    lsp = require('devcontainer.lsp.init')
    lsp.setup(config.get_value('lsp') or {})
  end

  local lsp_state = lsp.get_state()
  print("=== DevContainer LSP Status ===")
  print("Container ID: " .. (lsp_state.container_id or "none"))
  print("Auto setup: " .. tostring(lsp_state.config and lsp_state.config.auto_setup or "unknown"))

  if lsp_state.servers and next(lsp_state.servers) then
    print("Detected servers:")
    for name, server in pairs(lsp_state.servers) do
      print(string.format("  %s: %s (available: %s)", name, server.cmd, tostring(server.available)))
    end
  else
    print("No servers detected (container may not be running)")
  end

  if lsp_state.clients and #lsp_state.clients > 0 then
    print("Active clients:")
    for _, client_name in ipairs(lsp_state.clients) do
      print("  " .. client_name)
    end
  else
    print("No active LSP clients")
  end

  return lsp_state
end

-- LSPサーバーを手動でセットアップ
function M.lsp_setup()
  -- 基本的な初期化チェック
  log = log or require('devcontainer.utils.log')
  config = config or require('devcontainer.config')

  if not state.initialized then
    log.error("Plugin not initialized. Call setup() first.")
    return false
  end

  if not state.current_container then
    log.error("No active container. Start container first with :DevcontainerStart")
    return false
  end

  -- LSPモジュールを初期化
  lsp = lsp or require('devcontainer.lsp.init')
  lsp.setup(config.get_value('lsp') or {})
  lsp.set_container_id(state.current_container)

  -- パスマッピングの設定
  local lsp_path = require('devcontainer.lsp.path')
  lsp_path.setup(
    vim.fn.getcwd(),
    (state.current_config and state.current_config.workspace_mount) or '/workspace',
    (state.current_config and state.current_config.mounts) or {}
  )

  -- LSPサーバーのセットアップ
  lsp.setup_lsp_in_container()

  log.info("LSP setup completed")
  return true
end

-- 最小限のテスト（ブロッキングなし）
function M.test_minimal()
  print("=== Minimal Test ===")
  print("✓ Plugin loaded successfully")
  print("✓ State initialized: " .. tostring(state.initialized))

  if state.current_config then
    print("✓ Config loaded: " .. (state.current_config.name or "unnamed"))
  else
    print("⚠ No config loaded (run :DevcontainerOpen first)")
  end

  print("=== Test completed without blocking ===")
  return true
end

-- Docker の基本的な動作確認（非同期版）
function M.test_docker()
  print("=== Docker Test (Async) ===")
  print("Testing Docker availability...")

  -- 非同期でDockerバージョンチェック
  vim.fn.jobstart({'docker', '--version'}, {
    on_exit = function(_, exit_code, _)
      vim.schedule(function()
        if exit_code == 0 then
          print("✓ Docker is available")

          -- Docker daemonのチェック
          print("Testing Docker daemon...")
          vim.fn.jobstart({'docker', 'info'}, {
            on_exit = function(_, daemon_exit_code, _)
              vim.schedule(function()
                if daemon_exit_code == 0 then
                  print("✓ Docker daemon is running")
                  print("=== Docker test completed successfully ===")
                else
                  print("✗ Docker daemon is not running")
                end
              end)
            end,
            stdout_buffered = true,
            stderr_buffered = true,
          })
        else
          print("✗ Docker is not available")
        end
      end)
    end,
    stdout_buffered = true,
    stderr_buffered = true,
  })

  print("Docker test initiated (non-blocking)...")
  return true
end

-- シンプルなコンテナテスト（完全非同期版）
function M.test_container_basic()
  print("=== Basic Container Test (Async) ===")

  if not state.current_config then
    print("✗ No devcontainer configuration loaded")
    print("Run :DevcontainerOpen first")
    return false
  end

  docker = docker or require('devcontainer.docker.init')

  -- Step 1: Docker確認（非同期）
  print("Step 1: Checking Docker...")
  docker.check_docker_availability_async(function(available, err)
    vim.schedule(function()
      if not available then
        print("✗ Docker not available: " .. (err or "unknown"))
        return
      end
      print("✓ Docker is available")

      -- Step 2: イメージ確認
      print("Step 2: Checking image...")
      local has_image = state.current_config.built_image or
                       state.current_config.prepared_image or
                       state.current_config.image
      if not has_image then
        print("✗ No image specified")
        return
      end
      print("✓ Image: " .. (has_image or "unknown"))

      -- Step 3: コンテナリスト確認（非同期）
      print("Step 3: Checking for existing containers...")
      M._list_containers_async("name=" .. state.current_config.name, function(containers)
        vim.schedule(function()
          local container_id = nil

          if #containers > 0 then
            container_id = containers[1].id
            print("✓ Found existing container: " .. container_id)
            state.current_container = container_id

            -- Step 4: コンテナ状態確認
            print("Step 4: Checking container status...")
            M._get_container_status_async(container_id, function(status)
              vim.schedule(function()
                print("✓ Container status: " .. (status or "unknown"))
                print("=== Basic Test Complete (Async) ===")
                print("Container ID: " .. container_id)
              end)
            end)
          else
            print("⚠ No existing container found")
            print("=== Basic Test Complete (Async) ===")
            print("Note: Use :DevcontainerStart to create and start a container")
          end
        end)
      end)
    end)
  end)

  print("Basic container test initiated (non-blocking)...")
  return true
end

-- 非同期でコンテナリストを取得
function M._list_containers_async(filter, callback)
  local args = {"ps", "-a", "--format", "{{.ID}}\\t{{.Names}}\\t{{.Status}}\\t{{.Image}}"}

  if filter then
    table.insert(args, "--filter")
    table.insert(args, filter)
  end

  vim.fn.jobstart(vim.list_extend({'docker'}, args), {
    on_stdout = function(_, data, _)
      local containers = {}
      if data then
        for _, line in ipairs(data) do
          if line and line ~= "" then
            local parts = vim.split(line, "\t")
            if #parts >= 4 then
              table.insert(containers, {
                id = parts[1],
                name = parts[2],
                status = parts[3],
                image = parts[4]
              })
            end
          end
        end
      end
      callback(containers)
    end,
    stdout_buffered = true,
    stderr_buffered = true,
  })
end

-- 非同期でコンテナ状態を取得
function M._get_container_status_async(container_id, callback)
  vim.fn.jobstart({'docker', 'inspect', container_id, '--format', '{{.State.Status}}'}, {
    on_stdout = function(_, data, _)
      local status = nil
      if data and data[1] then
        status = vim.trim(data[1])
      end
      callback(status)
    end,
    stdout_buffered = true,
    stderr_buffered = true,
  })
end

-- 段階的なコンテナ起動（完全非同期版）
function M.start_step_by_step()
  print("=== Step-by-step Container Start (Async) ===")

  if not state.current_config then
    print("✗ No devcontainer configuration loaded")
    print("Run :DevcontainerOpen first")
    return false
  end

  docker = docker or require('devcontainer.docker.init')

  -- Step 1: Docker確認（非同期）
  print("Step 1: Checking Docker...")
  docker.check_docker_availability_async(function(available, err)
    vim.schedule(function()
      if not available then
        print("✗ Docker not available: " .. (err or "unknown"))
        return
      end
      print("✓ Docker is available")

      -- Step 2: イメージ確認
      print("Step 2: Checking image...")
      local has_image = state.current_config.built_image or
                       state.current_config.prepared_image or
                       state.current_config.image
      if not has_image then
        print("✗ No image specified")
        return
      end
      print("✓ Image: " .. (has_image or "unknown"))

      -- Step 3: コンテナ確認/作成（非同期）
      print("Step 3: Checking for existing containers...")
      M._list_containers_async("name=" .. state.current_config.name, function(containers)
        vim.schedule(function()
          local container_id = nil

          if #containers > 0 then
            container_id = containers[1].id
            print("✓ Found existing container: " .. container_id)
            state.current_container = container_id

            -- Step 4へ進む
            M._start_container_step4(container_id)
          else
            print("Creating new container...")
            M._create_container_async(state.current_config, function(create_result, create_err)
              vim.schedule(function()
                if not create_result then
                  print("✗ Failed to create container: " .. (create_err or "unknown"))
                  return
                end
                container_id = create_result
                print("✓ Created container: " .. container_id)
                state.current_container = container_id

                -- Step 4へ進む
                M._start_container_step4(container_id)
              end)
            end)
          end
        end)
      end)
    end)
  end)

  print("Step-by-step container start initiated (non-blocking)...")
  return true
end

-- Step 4: コンテナ起動処理
function M._start_container_step4(container_id)
  print("Step 4: Starting container...")
  docker = docker or require('devcontainer.docker.init')

  docker.start_container_async(container_id, function(success, error_msg)
    vim.schedule(function()
      if success then
        print("✓ Container started successfully and is ready!")
        print("=== Container Ready ===")

        -- LSP統合のセットアップ
        if config.get_value('lsp.auto_setup') then
          print("Setting up LSP...")
          lsp = lsp or require('devcontainer.lsp.init')
          lsp.setup(config.get_value('lsp'))
          lsp.set_container_id(container_id)

          local lsp_path = require('devcontainer.lsp.path')
          lsp_path.setup(
            vim.fn.getcwd(),
            state.current_config.workspace_mount or '/workspace',
            state.current_config.mounts or {}
          )

          lsp.setup_lsp_in_container()
          print("✓ LSP setup complete!")
        end

        print("=== DevContainer fully ready! ===")
      else
        print("✗ Failed to start container: " .. (error_msg or "unknown"))
        print("You can try again or check :DevcontainerStatus")
      end
    end)
  end)
end

-- 非同期でコンテナを作成
function M._create_container_async(config, callback)
  -- この実装は複雑なので、まずは簡単なエラーハンドリングで対応
  print("Note: Container creation requires image building/pulling.")
  print("For now, please use the standard :DevcontainerStart command.")
  print("This step-by-step version works best with existing containers.")
  callback(nil, "Container creation requires full :DevcontainerStart workflow")
end

-- 既存コンテナ専用の段階的起動
function M.start_existing_container()
  print("=== Start Existing Container (Async) ===")

  if not state.current_config then
    print("✗ No devcontainer configuration loaded")
    print("Run :DevcontainerOpen first")
    return false
  end

  docker = docker or require('devcontainer.docker.init')

  -- Step 1: Docker確認（非同期）
  print("Step 1: Checking Docker...")
  docker.check_docker_availability_async(function(available, err)
    vim.schedule(function()
      if not available then
        print("✗ Docker not available: " .. (err or "unknown"))
        return
      end
      print("✓ Docker is available")

      -- Step 2: 既存コンテナ検索
      print("Step 2: Looking for existing containers...")
      M._list_containers_async("name=" .. state.current_config.name, function(containers)
        vim.schedule(function()
          if #containers == 0 then
            print("✗ No existing container found")
            print("Please run :DevcontainerStart to create a new container")
            return
          end

          local container_id = containers[1].id
          print("✓ Found existing container: " .. container_id)
          state.current_container = container_id

          -- Step 3: コンテナ起動
          M._start_container_step4(container_id)
        end)
      end)
    end)
  end)

  print("Existing container start initiated (non-blocking)...")
  return true
end

-- コンテナの状況確認
function M.check_container_status()
  print("=== Container Status Check ===")

  if not state.current_config then
    print("✗ No devcontainer configuration loaded")
    return
  end

  docker = docker or require('devcontainer.docker.init')

  -- 非同期でコンテナリストを確認
  M._list_containers_async("name=" .. state.current_config.name, function(containers)
    vim.schedule(function()
      print("Container search completed:")
      if #containers == 0 then
        print("✗ No containers found with name pattern: " .. state.current_config.name)
        print("Try running :DevcontainerStart to create one")
      else
        for _, container in ipairs(containers) do
          print(string.format("✓ Found: %s (ID: %s, Status: %s)",
            container.name, container.id, container.status))
        end
      end
    end)
  end)

  print("Checking containers (async)...")
end

-- 詳細デバッグ情報を表示
function M.debug_detailed()
  print("=== Detailed Debug Info ===")
  print("Plugin State:")
  print("  Initialized: " .. tostring(state.initialized))
  print("  Current container: " .. (state.current_container or "none"))
  print("  Current config name: " .. (state.current_config and state.current_config.name or "none"))

  if state.current_config then
    print("  Current config image: " .. (state.current_config.image or "none"))
  end

  -- Docker の状態確認
  docker = docker or require('devcontainer.docker.init')
  docker.check_docker_availability_async(function(available, err)
    vim.schedule(function()
      print("Docker Status:")
      print("  Available: " .. tostring(available))
      if err then
        print("  Error: " .. err)
      end
    end)
  end)

  -- イメージ確認
  if state.current_config and state.current_config.image then
    print("Checking image: " .. state.current_config.image)
    docker.check_image_exists_async(state.current_config.image, function(exists, image_id)
      vim.schedule(function()
        print("Image Status:")
        print("  Exists: " .. tostring(exists))
        if image_id then
          print("  Image ID: " .. image_id)
        end
      end)
    end)
  end

  print("Async checks initiated...")
end

-- デバッグ情報を表示
function M.debug_info()
  print("=== DevContainer Debug Info ===")
  print("Initialized: " .. tostring(state.initialized))
  print("Current container: " .. (state.current_container or "none"))
  print("Current config: " .. (state.current_config and state.current_config.name or "none"))

  -- Docker の状態確認
  docker = docker or require('devcontainer.docker.init')
  local docker_available, docker_err = docker.check_docker_availability()
  print("Docker available: " .. tostring(docker_available))
  if docker_err then
    print("Docker error: " .. docker_err)
  end

  if config then
    print("\nPlugin configuration:")
    config.show_config()
  end

  if state.current_config then
    print("\nDevContainer configuration:")
    print("  Name: " .. (state.current_config.name or "none"))
    print("  Image: " .. (state.current_config.image or "none"))
    print("  Full config available via :lua print(vim.inspect(require('devcontainer').get_config()))")
  end

  if lsp then
    print("\nLSP Status:")
    M.lsp_status()
  end
end

-- シンプルなDocker pullテスト
function M.test_simple_pull()
  print("=== Simple Docker Pull Test ===")

  if not state.current_config then
    print("✗ No devcontainer configuration loaded")
    print("Run :DevcontainerOpen first")
    return false
  end

  local image = state.current_config.image
  if not image then
    print("✗ No image specified in configuration")
    return false
  end

  print("Testing docker pull with image: " .. image)
  print("This is a simplified test to isolate the pull issue...")

  docker = docker or require('devcontainer.docker.init')

  -- 直接的なテスト
  local job_id = docker.pull_image_async(
    image,
    function(progress)
      print("PROGRESS: " .. progress)
    end,
    function(success, result)
      vim.schedule(function()
        print("=== Pull Test Results ===")
        print("Success: " .. tostring(success))
        if result then
          print("Exit code: " .. tostring(result.code))
          print("Duration: " .. string.format("%.1fs", result.duration or 0))
          print("Data received: " .. tostring(result.data_received))
          if result.stdout and result.stdout ~= "" then
            print("Stdout lines: " .. #vim.split(result.stdout, "\n"))
          end
          if result.stderr and result.stderr ~= "" then
            print("Stderr lines: " .. #vim.split(result.stderr, "\n"))
          end
        end
        print("=== End Test Results ===")
      end)
    end
  )

  if job_id then
    print("✓ Pull test started with job ID: " .. job_id)
    print("Monitor progress above. Use :messages to see all output.")
  else
    print("✗ Failed to start pull test")
  end

  return true
end

-- 既存のコンテナへの再接続を試みる
function M._try_reconnect_existing_container()
  if state.current_container then
    -- 既にコンテナが設定されている場合はスキップ
    return
  end

  docker = docker or require('devcontainer.docker.init')

  -- 現在のディレクトリでdevcontainer.jsonを探す
  local cwd = vim.fn.getcwd()
  parser = parser or require('devcontainer.parser')

  local devcontainer_config, parse_err = parser.find_and_parse(cwd)
  if not devcontainer_config then
    -- devcontainer.jsonが見つからない場合は何もしない
    return
  end

  -- 正規化された設定を取得
  local normalized_config = parser.normalize_for_plugin(devcontainer_config)
  local container_name_pattern = normalized_config.name:lower():gsub("[^a-z0-9_.-]", "-") .. "_devcontainer"

  log.info("Looking for existing container with pattern: %s", container_name_pattern)

  -- 既存のコンテナを検索
  M._list_containers_async("name=" .. container_name_pattern, function(containers)
    vim.schedule(function()
      if #containers > 0 then
        local container = containers[1]
        log.info("Found existing container: %s (%s)", container.id, container.status)

        -- 状態を復元
        state.current_container = container.id
        state.current_config = normalized_config

        print("✓ Reconnected to existing container: " .. container.id:sub(1, 12))
        print("  Status: " .. container.status)
        print("  Use :DevcontainerStatus for details")

        -- LSPを自動セットアップ（設定されている場合）
        if config and config.get_value('lsp.auto_setup') and container.status == "running" then
          print("  Setting up LSP...")
          vim.defer_fn(function()
            M.lsp_setup()
          end, 2000)
        end
      else
        log.debug("No existing containers found for this project")
      end
    end)
  end)
end

-- 手動で既存コンテナに再接続
function M.reconnect()
  print("=== Reconnecting to Existing Container ===")
  state.current_container = nil
  state.current_config = nil
  M._try_reconnect_existing_container()
end

-- Docker execのデバッグテスト
function M.debug_exec()
  if not state.current_container then
    print("✗ No active container")
    return
  end

  docker = docker or require('devcontainer.docker.init')

  print("=== Docker Exec Debug Test ===")
  print("Container ID: " .. state.current_container)

  -- 手動でコマンド構築をテスト
  local args = {"exec", "--user", "vscode", state.current_container, "echo", "test"}
  print("Manual command: docker " .. table.concat(args, " "))

  -- 直接実行してみる
  local result = docker.run_docker_command and docker.run_docker_command(args) or nil
  if result then
    print("Direct execution result:")
    print("  Success: " .. tostring(result.success))
    print("  Code: " .. tostring(result.code))
    print("  Stdout: '" .. (result.stdout or "") .. "'")
    print("  Stderr: '" .. (result.stderr or "") .. "'")
  else
    print("Could not access run_docker_command function")
  end
end

-- postCreateCommand の実行
function M._run_post_create_command(container_id, callback)
  log.debug("Checking for postCreateCommand...")
  log.debug("Current config exists: %s", tostring(state.current_config ~= nil))
  
  if state.current_config then
    log.debug("Config keys: %s", vim.inspect(vim.tbl_keys(state.current_config)))
    log.debug("postCreateCommand value: %s", tostring(state.current_config.postCreateCommand))
    log.debug("post_create_command value: %s", tostring(state.current_config.post_create_command))
  end
  
  if not state.current_config or not state.current_config.post_create_command then
    print("No postCreateCommand found, skipping...")
    log.debug("No postCreateCommand found, skipping")
    callback(true)
    return
  end

  local command = state.current_config.post_create_command
  print("Step 4.5: Running postCreateCommand...")
  log.info("Executing postCreateCommand: %s", command)

  local docker = require('devcontainer.docker.init')
  local exec_args = {
    "exec", "-i", "--user", "vscode",
    "-e", "PATH=/home/vscode/.local/bin:/usr/local/python/current/bin:/usr/local/bin:/usr/bin:/bin",
    container_id, "bash", "-c", command
  }

  docker.run_docker_command_async(exec_args, {}, function(result)
    vim.schedule(function()
      if result.success then
        print("✓ postCreateCommand completed successfully")
        log.info("postCreateCommand output: %s", result.stdout)
        if result.stderr and result.stderr ~= "" then
          log.debug("postCreateCommand stderr: %s", result.stderr)
        end
        callback(true)
      else
        print("✗ postCreateCommand failed")
        log.error("postCreateCommand failed with code %d", result.code)
        log.error("Error output: %s", result.stderr or "")
        log.error("Stdout: %s", result.stdout or "")
        callback(false)
      end
    end)
  end)
end

return M

