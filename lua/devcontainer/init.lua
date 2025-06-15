-- lua/devcontainer/init.lua
-- devcontainer.nvim main entry point

local M = {}

-- Lazy module loading
local config = nil
local parser = nil
local docker = nil
local log = nil
local lsp = nil

-- Internal state
local state = {
  initialized = false,
  current_container = nil,
  current_config = nil,
}

-- Configuration setup
function M.setup(user_config)
  log = require('devcontainer.utils.log')
  config = require('devcontainer.config')

  local success = config.setup(user_config)
  if not success then
    log.error("Failed to setup configuration")
    return false
  end

  state.initialized = true
  log.debug("devcontainer.nvim initialized successfully")

  -- Attempt to auto-detect and reconnect to existing containers
  vim.defer_fn(function()
    M._try_reconnect_existing_container()
  end, 1000)

  return true
end

-- Open devcontainer
function M.open(path)
  log = log or require('devcontainer.utils.log')
  
  if not state.initialized then
    log.error("Plugin not initialized. Call setup() first.")
    return false
  end

  parser = parser or require('devcontainer.parser')
  docker = docker or require('devcontainer.docker')

  path = path or vim.fn.getcwd()
  log.info("Opening devcontainer from path: %s", path)

  -- Check Docker availability
  local docker_ok, docker_err = docker.check_docker_availability()
  if not docker_ok then
    log.error("Docker is not available: %s", docker_err)
    return false
  end

  -- Search and parse devcontainer.json
  local devcontainer_config, parse_err = parser.find_and_parse(path)
  if not devcontainer_config then
    log.error("Failed to parse devcontainer.json: %s", parse_err)
    return false
  end

  -- Validate configuration
  local validation_errors = parser.validate(devcontainer_config)
  if #validation_errors > 0 then
    for _, error in ipairs(validation_errors) do
      log.error("Configuration error: %s", error)
    end
    return false
  end

  -- Normalize configuration for plugin use
  local normalized_config = parser.normalize_for_plugin(devcontainer_config)

  -- Merge with plugin configuration
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

-- Prepare image (build or pull)
function M.build()
  log = log or require('devcontainer.utils.log')
  
  if not state.current_config then
    log.error("No devcontainer configuration loaded")
    return false
  end

  docker = docker or require('devcontainer.docker')

  log.info("Preparing devcontainer image")

  return docker.prepare_image(state.current_config, function(data)
    -- Display progress
    print(data)
  end, function(success, result)
    if success then
      log.info("Successfully prepared devcontainer image")
    else
      log.error("Failed to prepare devcontainer image: %s", result.stderr or "unknown error")
    end
  end)
end

-- Start container (fully async version)
function M.start()
  log = log or require('devcontainer.utils.log')
  
  if not state.current_config then
    log.error("No devcontainer configuration loaded")
    return false
  end

  docker = docker or require('devcontainer.docker.init')

  log.info("Starting devcontainer...")
  print("=== DevContainer Start (Async) ===")

  -- Check if image is prepared
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

  -- Check Docker availability (async)
  print("Step 1: Checking Docker...")
  docker.check_docker_availability_async(function(available, err)
    vim.schedule(function()
      if not available then
        print("✗ Docker not available: " .. (err or "unknown"))
        return
      end
      print("✓ Docker is available")

      -- Check for existing containers (async)
      print("Step 2: Checking for existing containers...")
      M._list_containers_async("name=" .. state.current_config.name, function(containers)
        vim.schedule(function()
          local container_id = nil

          if #containers > 0 then
            container_id = containers[1].id
            log.info("Found existing container: %s", container_id)
            print("✓ Found existing container: " .. container_id)
            state.current_container = container_id

            -- Proceed to container startup
            M._start_final_step(container_id)
          else
            -- Create new container (async)
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

                -- Proceed to container startup
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

-- Final step: Container startup and setup
function M._start_final_step(container_id)
  print("Step 4: Starting container...")
  docker = docker or require('devcontainer.docker.init')

  docker.start_container_async(container_id, function(success, error_msg)
    vim.schedule(function()
      if success then
        print("✓ Container started successfully!")
        log.info("Container is ready: %s", container_id)

        -- Execute postCreateCommand
        M._run_post_create_command(container_id, function(post_create_success)
          if not post_create_success then
            print("⚠ Warning: postCreateCommand failed, but continuing...")
          end

          -- Setup LSP integration
          if config.get_value('lsp.auto_setup') then
            print("Step 5: Setting up LSP...")
            lsp = lsp or require('devcontainer.lsp.init')
            lsp.setup(config.get_value('lsp'))
            lsp.set_container_id(container_id)

            -- Configure path mapping
            local ok, lsp_path = pcall(require, 'devcontainer.lsp.path')
            if ok then
              lsp_path.setup(
                vim.fn.getcwd(),
                state.current_config.workspace_mount or '/workspace',
                state.current_config.mounts or {}
              )
            else
              log.warn("Failed to load LSP path module")
            end

            -- Setup LSP servers
            lsp.setup_lsp_in_container()
            print("✓ LSP setup complete!")
          end
        end) -- _run_post_create_command callback end

        -- Execute post-start command (existing)
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

-- Full container creation (fully async version)
function M._create_container_full_async(config, callback)
  local docker = require('devcontainer.docker.init')

  -- Step 1: Check image existence
  print("Step 3a: Checking if image exists locally...")
  docker.check_image_exists_async(config.image, function(exists, image_id)
    vim.schedule(function()
      if exists then
        print("✓ Image found locally: " .. config.image)
        -- Image exists, create container directly
        M._create_container_direct(config, callback)
      else
        print("⚠ Image not found locally, pulling: " .. config.image)
        -- Pull image then create container
        M._pull_and_create_container(config, callback)
      end
    end)
  end)
end

-- Create container after image pull
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

      -- Confirm that progress is visible
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
          -- Image pull successful, create container
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

    -- Check progress after 30 seconds
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

-- Direct container creation
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

-- Stop container
function M.stop()
  log = log or require('devcontainer.utils.log')
  
  if not state.current_container then
    log.error("No active container")
    return false
  end

  docker = docker or require('devcontainer.docker')

  -- Stop LSP clients
  if lsp then
    lsp.stop_all()
  end

  log.info("Stopping container: %s", state.current_container)
  docker.stop_container(state.current_container)

  return true
end

-- Execute command in container
function M.exec(command, opts)
  log = log or require('devcontainer.utils.log')
  
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

-- Open terminal
function M.shell(shell)
  log = log or require('devcontainer.utils.log')
  
  if not state.current_container then
    log.error("No active container")
    return false
  end

  shell = shell or "/bin/bash"

  -- Open new terminal buffer
  vim.cmd("split")
  local term_opts = string.format("docker exec -it %s %s", state.current_container, shell)
  vim.cmd("terminal " .. term_opts)
  vim.cmd("startinsert")

  return true
end

-- Get container status
function M.status()
  log = log or require('devcontainer.utils.log')
  
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

-- Display logs
function M.logs(opts)
  log = log or require('devcontainer.utils.log')
  
  if not state.current_container then
    log.error("No active container")
    return false
  end

  docker = docker or require('devcontainer.docker')
  opts = opts or { tail = 100 }

  return docker.get_logs(state.current_container, opts)
end

-- Get current configuration
function M.get_config()
  return state.current_config
end

-- Get current container ID
function M.get_container_id()
  return state.current_container
end

-- Reset plugin state
function M.reset()
  log = log or require('devcontainer.utils.log')
  
  state.current_container = nil
  state.current_config = nil
  log.info("Plugin state reset")
end

-- Get LSP status
function M.lsp_status()
  log = log or require('devcontainer.utils.log')
  config = config or require('devcontainer.config')
  
  -- Initialize LSP module (if not already done)
  if not lsp then

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

-- Manually setup LSP servers
function M.lsp_setup()
  -- Basic initialization checks
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

  -- Initialize LSP module
  lsp = lsp or require('devcontainer.lsp.init')
  lsp.setup(config.get_value('lsp') or {})
  lsp.set_container_id(state.current_container)

  -- Configure path mapping
  local ok, lsp_path = pcall(require, 'devcontainer.lsp.path')
  if ok then
    lsp_path.setup(
      vim.fn.getcwd(),
      (state.current_config and state.current_config.workspace_mount) or '/workspace',
      (state.current_config and state.current_config.mounts) or {}
    )
  else
    log.warn("Failed to load LSP path module")
  end

  -- Setup LSP servers
  lsp.setup_lsp_in_container()

  log.info("LSP setup completed")
  return true
end

-- Minimal test (non-blocking)
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

-- Basic Docker operation test (async version)
function M.test_docker()
  print("=== Docker Test (Async) ===")
  print("Testing Docker availability...")

  -- Check Docker version asynchronously
  vim.fn.jobstart({'docker', '--version'}, {
    on_exit = function(_, exit_code, _)
      vim.schedule(function()
        if exit_code == 0 then
          print("✓ Docker is available")

          -- Check Docker daemon
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

-- Simple container test (fully async version)
function M.test_container_basic()
  print("=== Basic Container Test (Async) ===")

  if not state.current_config then
    print("✗ No devcontainer configuration loaded")
    print("Run :DevcontainerOpen first")
    return false
  end

  docker = docker or require('devcontainer.docker.init')

  -- Step 1: Check Docker (async)
  print("Step 1: Checking Docker...")
  docker.check_docker_availability_async(function(available, err)
    vim.schedule(function()
      if not available then
        print("✗ Docker not available: " .. (err or "unknown"))
        return
      end
      print("✓ Docker is available")

      -- Step 2: Check image
      print("Step 2: Checking image...")
      local has_image = state.current_config.built_image or
                       state.current_config.prepared_image or
                       state.current_config.image
      if not has_image then
        print("✗ No image specified")
        return
      end
      print("✓ Image: " .. has_image)

      -- Step 3: Check container list (async)
      print("Step 3: Checking for existing containers...")
      M._list_containers_async("name=" .. state.current_config.name, function(containers)
        vim.schedule(function()
          local container_id = nil

          if #containers > 0 then
            container_id = containers[1].id
            print("✓ Found existing container: " .. container_id)
            state.current_container = container_id

            -- Step 4: Check container status
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

-- Get container list asynchronously
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

-- Get container status asynchronously
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

-- Step-by-step container startup (fully async version)
function M.start_step_by_step()
  print("=== Step-by-step Container Start (Async) ===")

  if not state.current_config then
    print("✗ No devcontainer configuration loaded")
    print("Run :DevcontainerOpen first")
    return false
  end

  docker = docker or require('devcontainer.docker.init')

  -- Step 1: Check Docker (async)
  print("Step 1: Checking Docker...")
  docker.check_docker_availability_async(function(available, err)
    vim.schedule(function()
      if not available then
        print("✗ Docker not available: " .. (err or "unknown"))
        return
      end
      print("✓ Docker is available")

      -- Step 2: Check image
      print("Step 2: Checking image...")
      local has_image = state.current_config.built_image or
                       state.current_config.prepared_image or
                       state.current_config.image
      if not has_image then
        print("✗ No image specified")
        return
      end
      print("✓ Image: " .. has_image)

      -- Step 3: Check/create container (async)
      print("Step 3: Checking for existing containers...")
      M._list_containers_async("name=" .. state.current_config.name, function(containers)
        vim.schedule(function()
          local container_id = nil

          if #containers > 0 then
            container_id = containers[1].id
            print("✓ Found existing container: " .. container_id)
            state.current_container = container_id

            -- Proceed to Step 4
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

                -- Proceed to Step 4
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

-- Step 4: Container startup process
function M._start_container_step4(container_id)
  print("Step 4: Starting container...")
  docker = docker or require('devcontainer.docker.init')

  docker.start_container_async(container_id, function(success, error_msg)
    vim.schedule(function()
      if success then
        print("✓ Container started successfully and is ready!")
        print("=== Container Ready ===")

        -- Setup LSP integration
        if config.get_value('lsp.auto_setup') then
          print("Setting up LSP...")
          lsp = lsp or require('devcontainer.lsp.init')
          lsp.setup(config.get_value('lsp'))
          lsp.set_container_id(container_id)

          local ok, lsp_path = pcall(require, 'devcontainer.lsp.path')
          if ok then
            lsp_path.setup(
              vim.fn.getcwd(),
              state.current_config.workspace_mount or '/workspace',
              state.current_config.mounts or {}
            )
          else
            log.warn("Failed to load LSP path module")
          end

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

-- Create container asynchronously
function M._create_container_async(config, callback)
  -- This implementation is complex, so handle with simple error handling for now
  print("Note: Container creation requires image building/pulling.")
  print("For now, please use the standard :DevcontainerStart command.")
  print("This step-by-step version works best with existing containers.")
  callback(nil, "Container creation requires full :DevcontainerStart workflow")
end

-- Step-by-step startup for existing containers only
function M.start_existing_container()
  print("=== Start Existing Container (Async) ===")

  if not state.current_config then
    print("✗ No devcontainer configuration loaded")
    print("Run :DevcontainerOpen first")
    return false
  end

  docker = docker or require('devcontainer.docker.init')

  -- Step 1: Check Docker (async)
  print("Step 1: Checking Docker...")
  docker.check_docker_availability_async(function(available, err)
    vim.schedule(function()
      if not available then
        print("✗ Docker not available: " .. (err or "unknown"))
        return
      end
      print("✓ Docker is available")

      -- Step 2: Search for existing containers
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

          -- Step 3: Start container
          M._start_container_step4(container_id)
        end)
      end)
    end)
  end)

  print("Existing container start initiated (non-blocking)...")
  return true
end

-- Check container status
function M.check_container_status()
  print("=== Container Status Check ===")

  if not state.current_config then
    print("✗ No devcontainer configuration loaded")
    return
  end

  docker = docker or require('devcontainer.docker.init')

  -- Check container list asynchronously
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

-- Display detailed debug information
function M.debug_detailed()
  print("=== Detailed Debug Info ===")
  print("Plugin State:")
  print("  Initialized: " .. tostring(state.initialized))
  print("  Current container: " .. (state.current_container or "none"))
  print("  Current config name: " .. (state.current_config and state.current_config.name or "none"))

  if state.current_config then
    print("  Current config image: " .. (state.current_config.image or "none"))
  end

  -- Check Docker status
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

  -- Check image
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

-- Display debug information
function M.debug_info()
  print("=== DevContainer Debug Info ===")
  print("Initialized: " .. tostring(state.initialized))
  print("Current container: " .. (state.current_container or "none"))
  print("Current config: " .. (state.current_config and state.current_config.name or "none"))

  -- Check Docker status
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

-- Simple Docker pull test
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

  -- Direct test
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

-- Attempt to reconnect to existing container
function M._try_reconnect_existing_container()
  log = log or require('devcontainer.utils.log')
  
  if state.current_container then
    -- Skip if container is already configured
    return
  end

  docker = docker or require('devcontainer.docker.init')

  -- Search for devcontainer.json in current directory
  local cwd = vim.fn.getcwd()
  parser = parser or require('devcontainer.parser')

  local devcontainer_config, parse_err = parser.find_and_parse(cwd)
  if not devcontainer_config then
    -- Do nothing if devcontainer.json is not found
    return
  end

  -- Get normalized configuration
  local normalized_config = parser.normalize_for_plugin(devcontainer_config)
  local container_name_pattern = normalized_config.name:lower():gsub("[^a-z0-9_.-]", "-") .. "_devcontainer"

  log.info("Looking for existing container with pattern: %s", container_name_pattern)

  -- Search for existing containers
  M._list_containers_async("name=" .. container_name_pattern, function(containers)
    vim.schedule(function()
      if #containers > 0 then
        local container = containers[1]
        log.info("Found existing container: %s (%s)", container.id, container.status)

        -- Restore state
        state.current_container = container.id
        state.current_config = normalized_config

        print("✓ Reconnected to existing container: " .. container.id:sub(1, 12))
        print("  Status: " .. container.status)
        print("  Use :DevcontainerStatus for details")

        -- Auto-setup LSP (if configured)
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

-- Manually reconnect to existing container
function M.reconnect()
  print("=== Reconnecting to Existing Container ===")
  state.current_container = nil
  state.current_config = nil
  M._try_reconnect_existing_container()
end

-- Debug test for Docker exec
function M.debug_exec()
  if not state.current_container then
    print("✗ No active container")
    return
  end

  docker = docker or require('devcontainer.docker.init')

  print("=== Docker Exec Debug Test ===")
  print("Container ID: " .. state.current_container)

  -- Test manual command construction
  local args = {"exec", "--user", "vscode", state.current_container, "echo", "test"}
  print("Manual command: docker " .. table.concat(args, " "))

  -- Try direct execution
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

-- Execute postCreateCommand
function M._run_post_create_command(container_id, callback)
  log = log or require('devcontainer.utils.log')
  
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
    "-e", "PATH=/home/vscode/.local/bin:/usr/local/go/bin:/go/bin:/usr/local/python/current/bin:/usr/local/bin:/usr/bin:/bin",
    "-e", "GOPATH=/go",
    "-e", "GOROOT=/usr/local/go",
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

