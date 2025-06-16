-- lua/devcontainer/init.lua
-- devcontainer.nvim main entry point
--
-- This module triggers the following User autocmd events:
-- - DevcontainerOpened: When devcontainer config is loaded
-- - DevcontainerBuilt: When container image is built/prepared
-- - DevcontainerStarted: When container starts successfully
-- - DevcontainerStopped: When container stops or is killed
-- - DevcontainerClosed: When devcontainer is closed/reset

local M = {}

-- Lazy module loading
local config = nil
local parser = nil
local docker = nil
local log = nil
local lsp = nil
local notify = nil

-- Internal state
local state = {
  initialized = false,
  current_container = nil,
  current_config = nil,
  -- Cache for container status to reduce frequent Docker calls
  status_cache = {
    container_status = nil,
    last_update = 0,
    update_interval = 2000, -- Update container status every 2 seconds
  },
}

-- Clear status cache when state changes
local function clear_status_cache()
  state.status_cache.container_status = nil
  state.status_cache.last_update = 0
end

-- Configuration setup
function M.setup(user_config)
  log = require('devcontainer.utils.log')
  config = require('devcontainer.config')
  notify = require('devcontainer.utils.notify')

  local success = config.setup(user_config)
  if not success then
    log.error('Failed to setup configuration')
    return false
  end

  -- Initialize terminal system
  local terminal_ok, terminal_err = pcall(function()
    local terminal = require('devcontainer.terminal')
    terminal.setup(config.get())
  end)

  if not terminal_ok then
    log.warn('Failed to initialize terminal system: %s', terminal_err)
  end

  -- Initialize telescope integration if enabled
  if config.get().ui.use_telescope then
    local telescope_ok, telescope_err = pcall(function()
      local telescope_integration = require('devcontainer.ui.telescope')
      telescope_integration.setup()
    end)

    if not telescope_ok then
      log.warn('Failed to initialize telescope integration: %s', telescope_err)
    end
  end

  -- Initialize statusline integration if enabled
  if config.get().ui.status_line then
    local statusline_ok, statusline_err = pcall(function()
      local statusline = require('devcontainer.ui.statusline')
      statusline.setup()
    end)

    if not statusline_ok then
      log.warn('Failed to initialize statusline integration: %s', statusline_err)
    end
  end

  state.initialized = true
  log.debug('devcontainer.nvim initialized successfully')

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
    log.error('Plugin not initialized. Call setup() first.')
    return false
  end

  parser = parser or require('devcontainer.parser')
  docker = docker or require('devcontainer.docker')

  path = path or vim.fn.getcwd()
  log.info('Opening devcontainer from path: %s', path)

  -- Check Docker availability
  local docker_ok, docker_err = docker.check_docker_availability()
  if not docker_ok then
    log.error('Docker is not available: %s', docker_err)
    return false
  end

  -- Search and parse devcontainer.json
  local devcontainer_config, parse_err = parser.find_and_parse(path)
  if not devcontainer_config then
    log.error('Failed to parse devcontainer.json: %s', parse_err)
    return false
  end

  -- Validate configuration
  local validation_errors = parser.validate(devcontainer_config)
  if #validation_errors > 0 then
    for _, error in ipairs(validation_errors) do
      log.error('Configuration error: %s', error)
    end
    return false
  end

  -- Resolve dynamic ports before normalizing
  local resolved_config, port_err = parser.resolve_dynamic_ports(devcontainer_config, config.get())
  if not resolved_config then
    log.error('Failed to resolve dynamic ports: %s', port_err)
    return false
  end

  -- Validate resolved ports
  local resolved_validation_errors = parser.validate_resolved_ports(resolved_config)
  if #resolved_validation_errors > 0 then
    for _, error in ipairs(resolved_validation_errors) do
      log.error('Port resolution validation error: %s', error)
    end
    return false
  end

  -- Normalize configuration for plugin use
  local normalized_config = parser.normalize_for_plugin(resolved_config)
  normalized_config.base_path = path -- Add base path for container name generation

  -- Merge with plugin configuration
  parser.merge_with_plugin_config(resolved_config, config.get())

  state.current_config = normalized_config

  log.info('Successfully loaded devcontainer configuration: %s', normalized_config.name)
  log.debug('Config has postCreateCommand: %s', tostring(normalized_config.postCreateCommand ~= nil))
  log.debug('Config has post_create_command: %s', tostring(normalized_config.post_create_command ~= nil))
  if normalized_config.postCreateCommand then
    log.debug('postCreateCommand: %s', normalized_config.postCreateCommand)
  end
  if normalized_config.post_create_command then
    log.debug('post_create_command: %s', normalized_config.post_create_command)
  end

  -- Trigger DevcontainerOpened event
  vim.api.nvim_exec_autocmds('User', {
    pattern = 'DevcontainerOpened',
    data = {
      container_name = normalized_config.name,
      config_path = path,
    },
  })

  return true
end

-- Prepare image (build or pull)
function M.build()
  log = log or require('devcontainer.utils.log')

  if not state.current_config then
    log.error('No devcontainer configuration loaded')
    return false
  end

  docker = docker or require('devcontainer.docker')

  log.info('Preparing devcontainer image')

  return docker.prepare_image(state.current_config, function(data)
    -- Display progress
    print(data)
  end, function(success, result)
    if success then
      log.info('Successfully prepared devcontainer image')
      -- Trigger DevcontainerBuilt event
      vim.api.nvim_exec_autocmds('User', {
        pattern = 'DevcontainerBuilt',
        data = {
          container_name = state.current_config and state.current_config.name or 'unknown',
          image = state.current_config and state.current_config.image or 'unknown',
        },
      })
    else
      log.error('Failed to prepare devcontainer image: %s', result.stderr or 'unknown error')
    end
  end)
end

-- Start container (fully async version)
function M.start()
  log = log or require('devcontainer.utils.log')

  if not state.current_config then
    log.error('No devcontainer configuration loaded')
    return false
  end

  docker = docker or require('devcontainer.docker.init')

  log.info('Starting devcontainer...')
  print('=== DevContainer Start (Async) ===')

  -- Check if image is prepared
  local has_image = state.current_config.built_image
    or state.current_config.prepared_image
    or state.current_config.image

  if not has_image then
    log.info('Image not prepared, building/pulling first...')
    print('Building/pulling image... This may take a while.')
    print('Note: Image building is not yet fully async. This may take time.')
    M.build()
    return true
  end

  -- Check Docker availability (async)
  print('Step 1: Checking Docker...')
  docker.check_docker_availability_async(function(available, err)
    vim.schedule(function()
      if not available then
        print('✗ Docker not available: ' .. (err or 'unknown'))
        return
      end
      print('✓ Docker is available')

      -- Check for existing containers (async)
      print('Step 2: Checking for existing containers...')
      M._list_containers_async('name=' .. state.current_config.name, function(containers)
        vim.schedule(function()
          local container_id = nil

          if #containers > 0 then
            container_id = containers[1].id
            log.info('Found existing container: %s', container_id)
            print('✓ Found existing container: ' .. container_id)
            state.current_container = container_id
            clear_status_cache()

            -- Proceed to container startup
            M._start_final_step(container_id)
          else
            -- Create new container (async)
            print('Step 3: Creating new container...')
            M._create_container_full_async(state.current_config, function(create_result, create_err)
              vim.schedule(function()
                if not create_result then
                  log.error('Failed to create container: %s', create_err)
                  print('✗ Failed to create container: ' .. (create_err or 'unknown'))
                  return
                end
                container_id = create_result
                print('✓ Created container: ' .. container_id)
                state.current_container = container_id
                clear_status_cache()

                -- Proceed to container startup
                M._start_final_step(container_id)
              end)
            end)
          end
        end)
      end)
    end)
  end)

  print('DevContainer start initiated (non-blocking)...')
  return true
end

-- Final step: Container startup and setup
function M._start_final_step(container_id)
  print('Step 4: Starting container...')
  docker = docker or require('devcontainer.docker.init')

  docker.start_container_async(container_id, function(success, error_msg)
    vim.schedule(function()
      if success then
        print('✓ Container started successfully!')
        log.info('Container is ready: %s', container_id)

        -- Trigger DevcontainerStarted event
        vim.api.nvim_exec_autocmds('User', {
          pattern = 'DevcontainerStarted',
          data = {
            container_id = container_id,
            container_name = state.current_config and state.current_config.name or 'unknown',
          },
        })

        -- Execute postCreateCommand
        M._run_post_create_command(container_id, function(post_create_success)
          if not post_create_success then
            print('⚠ Warning: postCreateCommand failed, but continuing...')
          end

          -- Setup LSP integration
          if config.get_value('lsp.auto_setup') then
            print('Step 5: Setting up LSP...')
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
              log.warn('Failed to load LSP path module')
            end

            -- Setup LSP servers
            lsp.setup_lsp_in_container()
            print('✓ LSP setup complete!')
          end
        end) -- _run_post_create_command callback end

        -- Execute post-start command (existing)
        if state.current_config.post_start_command then
          print('Step 6: Running post-start command...')
          M.exec(state.current_config.post_start_command)
        end

        print('=== DevContainer is ready! ===')
      else
        log.error('Failed to start container')
        print('✗ Failed to start container: ' .. (error_msg or 'unknown'))
      end
    end)
  end)
end

-- Full container creation (fully async version)
function M._create_container_full_async(config, callback)
  local docker = require('devcontainer.docker.init')

  -- Step 1: Check image existence
  print('Step 3a: Checking if image exists locally...')
  docker.check_image_exists_async(config.image, function(exists, image_id)
    vim.schedule(function()
      if exists then
        print('✓ Image found locally: ' .. config.image)
        -- Image exists, create container directly
        M._create_container_direct(config, callback)
      else
        print('⚠ Image not found locally, pulling: ' .. config.image)
        -- Pull image then create container
        M._pull_and_create_container(config, callback)
      end
    end)
  end)
end

-- Create container after image pull
function M._pull_and_create_container(config, callback)
  local docker = require('devcontainer.docker.init')

  print('Step 3b: Pulling image (this may take a while)...')
  print('   Image: ' .. config.image)
  print('   This is a large download and may take 5-15 minutes depending on your connection.')
  print('   Progress will be shown below. You can continue using Neovim while this runs.')
  print('   Note: If no progress appears after 30 seconds, there may be an issue.')

  local start_time = vim.fn.reltime()
  local progress_count = 0

  local job_id = docker.pull_image_async(config.image, function(progress)
    progress_count = progress_count + 1
    local elapsed = vim.fn.reltimestr(vim.fn.reltime(start_time))
    print(string.format('   [%ss] %s', elapsed, progress))

    -- Confirm that progress is visible
    if progress_count == 1 then
      print('   ✓ Docker pull output started - progress tracking is working')
    end
  end, function(success, result)
    vim.schedule(function()
      local elapsed = vim.fn.reltimestr(vim.fn.reltime(start_time))
      print(string.format('   [%ss] Pull completed with status: %s', elapsed, tostring(success)))

      if success then
        print('✓ Image pull completed successfully!')
        print('   Now proceeding to create container...')

        -- Trigger DevcontainerBuilt event after successful pull
        vim.api.nvim_exec_autocmds('User', {
          pattern = 'DevcontainerBuilt',
          data = {
            container_name = config.name or 'unknown',
            image = config.image,
          },
        })

        -- Image pull successful, create container
        M._create_container_direct(config, callback)
      else
        print('✗ Image pull failed:')

        if result then
          if result.stderr and result.stderr ~= '' then
            print('   Error output: ' .. result.stderr)
          end
          if result.error then
            print('   Error: ' .. result.error)
          end
          if result.data_received == false then
            print('   Issue: No data was received from Docker command')
            print('   This suggests Docker may be unresponsive or the image name is invalid')
          end
          if result.duration then
            print(string.format('   Duration: %.1f seconds', result.duration))
          end
        end

        print('   Troubleshooting steps:')
        print('   1. Check your internet connection')
        print('   2. Verify the image name: ' .. config.image)
        print('   3. Try manually: docker pull ' .. config.image)
        print('   4. Check if Docker daemon is responsive: docker info')
        print('   5. Use :DevcontainerTestPull for isolated testing')

        callback(nil, 'Failed to pull image: ' .. (result and result.stderr or result and result.error or 'unknown'))
      end
    end)
  end)

  if job_id and job_id > 0 then
    print('   ✓ Pull job started successfully (ID: ' .. job_id .. ')')
    print('   Tip: Use :messages to see all progress, or :DevcontainerTestPull for testing')

    -- Check progress after 30 seconds
    vim.defer_fn(function()
      if progress_count == 0 then
        print('   ⚠ Warning: No progress received after 30 seconds')
        print('   This may indicate a Docker or network issue')
        print("   Try :DevcontainerTestPull or manual 'docker pull " .. config.image .. "'")
      end
    end, 30000)
  else
    print('   ✗ Failed to start pull job (job_id: ' .. tostring(job_id) .. ')')
    callback(nil, 'Failed to start Docker pull job')
  end
end

-- Direct container creation
function M._create_container_direct(config, callback)
  local docker = require('devcontainer.docker.init')

  print('Step 3c: Creating container...')
  docker.create_container_async(config, function(container_id, error_msg)
    if container_id then
      print('✓ Container created successfully: ' .. container_id)
    else
      print('✗ Container creation failed: ' .. (error_msg or 'unknown'))
    end
    callback(container_id, error_msg)
  end)
end

-- Stop container
function M.stop()
  log = log or require('devcontainer.utils.log')

  if not state.current_container then
    log.error('No active container')
    return false
  end

  docker = docker or require('devcontainer.docker')

  -- Stop LSP clients
  if lsp then
    lsp.stop_all()
  end

  -- Clean up port allocations
  if state.current_config and state.current_config.project_id then
    local port_utils = require('devcontainer.utils.port')
    port_utils.release_project_ports(state.current_config.project_id)
  end

  log.info('Stopping container: %s', state.current_container)
  docker.stop_container(state.current_container)

  -- Trigger DevcontainerStopped event
  vim.api.nvim_exec_autocmds('User', {
    pattern = 'DevcontainerStopped',
    data = {
      container_id = state.current_container,
      container_name = state.current_config and state.current_config.name or 'unknown',
    },
  })

  return true
end

-- Kill container (immediate termination)
function M.kill()
  log = log or require('devcontainer.utils.log')

  if not state.current_container then
    log.error('No active container')
    return false
  end

  docker = docker or require('devcontainer.docker.init')

  -- Stop LSP clients
  if lsp then
    lsp.stop_all()
  end

  -- Clean up port allocations
  if state.current_config and state.current_config.project_id then
    local port_utils = require('devcontainer.utils.port')
    port_utils.release_project_ports(state.current_config.project_id)
  end

  log.info('Killing container: %s', state.current_container)
  docker.kill_container(state.current_container, function(success, error_msg)
    vim.schedule(function()
      if success then
        print('✓ Container killed successfully')
        -- Trigger DevcontainerStopped event before clearing state
        vim.api.nvim_exec_autocmds('User', {
          pattern = 'DevcontainerStopped',
          data = {
            container_id = state.current_container,
            container_name = state.current_config and state.current_config.name or 'unknown',
          },
        })
        state.current_container = nil
        clear_status_cache()
        clear_status_cache()
        state.current_config = nil
      else
        print('✗ Failed to kill container: ' .. (error_msg or 'unknown'))
      end
    end)
  end)

  return true
end

-- Terminate container (alias for kill)
function M.terminate()
  log = log or require('devcontainer.utils.log')

  if not state.current_container then
    log.error('No active container')
    return false
  end

  docker = docker or require('devcontainer.docker.init')

  -- Stop LSP clients
  if lsp then
    lsp.stop_all()
  end

  -- Clean up port allocations
  if state.current_config and state.current_config.project_id then
    local port_utils = require('devcontainer.utils.port')
    port_utils.release_project_ports(state.current_config.project_id)
  end

  log.info('Terminating container: %s', state.current_container)
  docker.terminate_container(state.current_container, function(success, error_msg)
    vim.schedule(function()
      if success then
        print('✓ Container terminated successfully')
        -- Trigger DevcontainerStopped event before clearing state
        vim.api.nvim_exec_autocmds('User', {
          pattern = 'DevcontainerStopped',
          data = {
            container_id = state.current_container,
            container_name = state.current_config and state.current_config.name or 'unknown',
          },
        })
        state.current_container = nil
        clear_status_cache()
        clear_status_cache()
        state.current_config = nil
      else
        print('✗ Failed to terminate container: ' .. (error_msg or 'unknown'))
      end
    end)
  end)

  return true
end

-- Execute command in container
function M.exec(command, opts)
  log = log or require('devcontainer.utils.log')

  if not state.current_container then
    print('✗ No active container')
    log.error('No active container')
    return false
  end

  docker = docker or require('devcontainer.docker.init')
  opts = opts or {}

  -- Use the remote user from devcontainer config if available
  if state.current_config and state.current_config.remote_user and not opts.user then
    opts.user = state.current_config.remote_user
  end

  print('Executing in container: ' .. command)
  if opts.user then
    print('  As user: ' .. opts.user)
  end

  -- Track start time for duration
  local start_time = vim.loop.hrtime()

  -- Add callback to display output
  opts.on_complete = function(result)
    vim.schedule(function()
      local duration = (vim.loop.hrtime() - start_time) / 1e9

      -- Add to history
      local history = require('devcontainer.history')
      history.add_exec_command(command, state.current_container, result.code or -1, result.stdout, duration)

      if result.success then
        if result.stdout and result.stdout ~= '' then
          print('=== Command Output ===')
          for line in result.stdout:gmatch('[^\n]+') do
            print(line)
          end
        else
          print('Command completed (no output)')
        end
      else
        print('✗ Command failed:')
        if result.stderr and result.stderr ~= '' then
          for line in result.stderr:gmatch('[^\n]+') do
            print('Error: ' .. line)
          end
        else
          print('No error details available')
        end
      end
    end)
  end

  return docker.exec_command(state.current_container, command, opts)
end

-- Enhanced terminal functions

-- Create or switch to terminal session
function M.terminal(opts)
  local terminal = require('devcontainer.terminal')
  return terminal.terminal(opts)
end

-- Create new terminal session
function M.terminal_new(name)
  local terminal = require('devcontainer.terminal')
  return terminal.new_session(name)
end

-- List terminal sessions
function M.terminal_list()
  local terminal = require('devcontainer.terminal')
  return terminal.list_sessions()
end

-- Close terminal session
function M.terminal_close(name)
  local terminal = require('devcontainer.terminal')
  return terminal.close_session(name)
end

-- Close all terminal sessions
function M.terminal_close_all()
  local terminal = require('devcontainer.terminal')
  return terminal.close_all_sessions()
end

-- Rename terminal session
function M.terminal_rename(old_name, new_name)
  local terminal = require('devcontainer.terminal')
  return terminal.rename_session(old_name, new_name)
end

-- Switch to next terminal session
function M.terminal_next()
  local terminal = require('devcontainer.terminal')
  return terminal.next_session()
end

-- Switch to previous terminal session
function M.terminal_prev()
  local terminal = require('devcontainer.terminal')
  return terminal.prev_session()
end

-- Show terminal status
function M.terminal_status()
  local terminal = require('devcontainer.terminal')
  return terminal.show_status()
end

-- Clean up terminal history
function M.terminal_cleanup_history(days)
  local terminal = require('devcontainer.terminal')
  return terminal.cleanup_history(days)
end

-- Attach to existing container
function M.attach(container_name)
  log = log or require('devcontainer.utils.log')
  docker = docker or require('devcontainer.docker')

  docker.attach_to_container(container_name, function(success, error_msg)
    if success then
      state.current_container = container_name
      clear_status_cache()
      log.info('Attached to container: %s', container_name)
      notify.container('Attached to container: ' .. container_name)

      -- Trigger DevcontainerOpened event for attach
      vim.api.nvim_exec_autocmds('User', {
        pattern = 'DevcontainerOpened',
        data = {
          container_name = container_name,
          attached = true,
        },
      })
    else
      log.error('Failed to attach to container: %s', error_msg)
      notify.critical('Failed to attach: ' .. error_msg)
    end
  end)
end

-- Start a specific container by name
function M.start_container(container_name)
  log = log or require('devcontainer.utils.log')
  docker = docker or require('devcontainer.docker')

  docker.start_existing_container(container_name, function(success, error_msg)
    if success then
      log.info('Started container: %s', container_name)
      notify.container('Started container: ' .. container_name)

      -- Trigger DevcontainerStarted event
      vim.api.nvim_exec_autocmds('User', {
        pattern = 'DevcontainerStarted',
        data = {
          container_id = container_name,
          container_name = container_name,
        },
      })
    else
      log.error('Failed to start container: %s', error_msg)
      notify.critical('Failed to start: ' .. error_msg)
    end
  end)
end

-- Stop a specific container by name
function M.stop_container(container_name)
  log = log or require('devcontainer.utils.log')
  docker = docker or require('devcontainer.docker')

  docker.stop_existing_container(container_name, function(success, error_msg)
    if success then
      log.info('Stopped container: %s', container_name)
      notify.container('Stopped container: ' .. container_name)

      -- Trigger DevcontainerStopped event
      vim.api.nvim_exec_autocmds('User', {
        pattern = 'DevcontainerStopped',
        data = {
          container_id = container_name,
          container_name = container_name,
        },
      })
    else
      log.error('Failed to stop container: %s', error_msg)
      notify.critical('Failed to stop: ' .. error_msg)
    end
  end)
end

-- Restart a specific container by name
function M.restart_container(container_name)
  log = log or require('devcontainer.utils.log')
  docker = docker or require('devcontainer.docker')

  docker.restart_container(container_name, function(success, error_msg)
    if success then
      log.info('Restarted container: %s', container_name)
      notify.container('Restarted container: ' .. container_name)
    else
      log.error('Failed to restart container: %s', error_msg)
      notify.critical('Failed to restart: ' .. error_msg)
    end
  end)
end

-- Rebuild container for a project
function M.rebuild(project_path)
  log = log or require('devcontainer.utils.log')

  -- First stop existing container if any
  if state.current_container then
    M.stop()
  end

  -- Force rebuild on next open
  notify.status('Container will be rebuilt on next open')

  -- Open with force rebuild
  M.open(project_path, { force_rebuild = true })
end

-- Get container status
function M.status()
  log = log or require('devcontainer.utils.log')

  if not state.current_container then
    print('No active container')
    return nil
  end

  docker = docker or require('devcontainer.docker')

  local status = docker.get_container_status(state.current_container)
  local info = docker.get_container_info(state.current_container)

  print('=== DevContainer Status ===')
  print('Container ID: ' .. state.current_container)
  print('Status: ' .. (status or 'unknown'))

  if info then
    print('Image: ' .. (info.Config.Image or 'unknown'))
    print('Created: ' .. (info.Created or 'unknown'))

    -- Show configured ports from devcontainer.json
    if
      state.current_config
      and state.current_config.normalized_ports
      and #state.current_config.normalized_ports > 0
    then
      print('\nConfigured Ports (from devcontainer.json):')
      for _, port_config in ipairs(state.current_config.normalized_ports) do
        local port_desc = string.format('  Container:%d', port_config.container_port)
        if port_config.type == 'fixed' and port_config.host_port then
          port_desc = port_desc .. string.format(' -> Host:%d (fixed)', port_config.host_port)
        elseif port_config.type == 'auto' then
          port_desc = port_desc .. ' -> Host:auto-allocated'
        elseif port_config.type == 'range' then
          port_desc = port_desc
            .. string.format(' -> Host:range(%d-%d)', port_config.range_start, port_config.range_end)
        end
        if port_config.protocol and port_config.protocol ~= 'tcp' then
          port_desc = port_desc .. ' (' .. port_config.protocol .. ')'
        end
        print(port_desc)
      end
    end

    -- Show active port mappings from Docker
    if info.NetworkSettings and info.NetworkSettings.Ports then
      print('\nActive Port Mappings (Docker):')
      local has_active_ports = false
      for container_port, host_bindings in pairs(info.NetworkSettings.Ports) do
        if host_bindings and #host_bindings > 0 then
          for _, binding in ipairs(host_bindings) do
            print(string.format('  %s -> %s:%s', container_port, binding.HostIp, binding.HostPort))
            has_active_ports = true
          end
        end
      end
      if not has_active_ports then
        print('  (no active port mappings)')
      end
    end

    -- Show project port allocations
    if state.current_config and state.current_config.project_id then
      local port_utils = require('devcontainer.utils.port')
      local project_ports = port_utils.get_project_ports(state.current_config.project_id)

      if next(project_ports) then
        print('\nAllocated Ports (Project: ' .. state.current_config.project_id .. '):')
        for port, allocation_info in pairs(project_ports) do
          local time_str = os.date('%Y-%m-%d %H:%M:%S', allocation_info.allocated_at)
          print(string.format('  Host:%d (%s, allocated: %s)', port, allocation_info.purpose, time_str))
        end
      end
    end
  end

  return {
    container_id = state.current_container,
    status = status,
    info = info,
    configured_ports = state.current_config and state.current_config.normalized_ports or {},
    project_id = state.current_config and state.current_config.project_id or nil,
  }
end

-- Display logs
function M.logs(opts)
  log = log or require('devcontainer.utils.log')

  if not state.current_container then
    log.error('No active container')
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

  -- Trigger DevcontainerClosed event before clearing state
  if state.current_container or state.current_config then
    vim.api.nvim_exec_autocmds('User', {
      pattern = 'DevcontainerClosed',
      data = {
        container_id = state.current_container,
        container_name = state.current_config and state.current_config.name or 'unknown',
      },
    })
  end

  state.current_container = nil
  clear_status_cache()
  state.current_config = nil
  log.info('Plugin state reset')
end

-- Show detailed port information
function M.show_ports()
  log = log or require('devcontainer.utils.log')

  if not state.current_config then
    print('No active devcontainer configuration')
    return
  end

  print('=== DevContainer Port Information ===')
  print('Project: ' .. (state.current_config.name or 'unknown'))
  print('Project ID: ' .. (state.current_config.project_id or 'unknown'))
  print()

  -- Show configured ports
  if state.current_config.ports and #state.current_config.ports > 0 then
    print('Configured Ports:')
    for i, port in ipairs(state.current_config.ports) do
      local type_info = ''
      if port.type == 'auto' then
        type_info = ' (auto-allocated)'
      elseif port.type == 'range' then
        type_info = string.format(' (range: %d-%d)', port.range_start or 0, port.range_end or 0)
      elseif port.type == 'fixed' then
        type_info = ' (fixed)'
      end

      local protocol = port.protocol ~= 'tcp' and '/' .. port.protocol or ''
      print(
        string.format(
          '  %d. Container:%d -> Host:%s%s%s',
          i,
          port.container_port,
          tostring(port.host_port),
          protocol,
          type_info
        )
      )
      if port.original_spec then
        print(string.format('     Original spec: %s', vim.inspect(port.original_spec)))
      end
    end
    print()
  else
    print('No ports configured')
    print()
  end

  -- Show port allocation statistics
  local port_utils = require('devcontainer.utils.port')
  local allocated_ports = port_utils.get_project_ports(state.current_config.project_id or 'unknown')

  if next(allocated_ports) then
    print('Allocated Ports for this Project:')
    for port, info in pairs(allocated_ports) do
      local allocated_time = os.date('%Y-%m-%d %H:%M:%S', info.allocated_at)
      print(string.format('  Port %d: %s (allocated: %s)', port, info.purpose, allocated_time))
    end
    print()
  end

  -- Show Docker port mappings if container is running
  if state.current_container then
    docker = docker or require('devcontainer.docker')
    local container_info = docker.get_container_info(state.current_container)

    if container_info and container_info.NetworkSettings and container_info.NetworkSettings.Ports then
      local ports = container_info.NetworkSettings.Ports
      if next(ports) then
        print('Active Docker Port Mappings:')
        for container_port, host_info in pairs(ports) do
          if host_info and host_info[1] then
            print(
              string.format('  %s -> %s:%s', container_port, host_info[1].HostIp or '0.0.0.0', host_info[1].HostPort)
            )
          end
        end
      else
        print('No active Docker port mappings')
      end
    else
      print('No port mapping information available')
    end
  else
    print('Container not running - no active port mappings')
  end
end

-- Show port allocation statistics
function M.show_port_stats()
  local port_utils = require('devcontainer.utils.port')
  local stats = port_utils.get_port_statistics()

  print('=== Port Allocation Statistics ===')
  print('Total allocated ports: ' .. stats.total_allocated)
  print()

  if next(stats.by_project) then
    print('Allocation by Project:')
    for project_id, count in pairs(stats.by_project) do
      print(string.format('  %s: %d ports', project_id, count))
    end
    print()
  end

  if next(stats.by_purpose) then
    print('Allocation by Purpose:')
    for purpose, count in pairs(stats.by_purpose) do
      print(string.format('  %s: %d ports', purpose, count))
    end
    print()
  end

  print('Dynamic Port Range Usage:')
  print(string.format('  Range: %d - %d', stats.port_range_usage.start, stats.port_range_usage.end_port))
  print(string.format('  Allocated in range: %d', stats.port_range_usage.allocated_in_range))

  local total_range = stats.port_range_usage.end_port - stats.port_range_usage.start + 1
  local usage_percent = math.floor((stats.port_range_usage.allocated_in_range / total_range) * 100)
  print(string.format('  Range utilization: %d%%', usage_percent))
end

-- Get LSP status
function M.lsp_status()
  log = log or require('devcontainer.utils.log')
  config = config or require('devcontainer.config')

  -- Initialize LSP module (if not already done)
  if not lsp then
    if not state.initialized then
      log.warn('Plugin not fully initialized')
      return nil
    end

    lsp = require('devcontainer.lsp.init')
    lsp.setup(config.get_value('lsp') or {})
  end

  local lsp_state = lsp.get_state()
  print('=== DevContainer LSP Status ===')
  print('Container ID: ' .. (lsp_state.container_id or 'none'))
  print('Auto setup: ' .. tostring(lsp_state.config and lsp_state.config.auto_setup or 'unknown'))

  if lsp_state.servers and next(lsp_state.servers) then
    print('Detected servers:')
    for name, server in pairs(lsp_state.servers) do
      print(string.format('  %s: %s (available: %s)', name, server.cmd, tostring(server.available)))
    end
  else
    print('No servers detected (container may not be running)')
  end

  if lsp_state.clients and #lsp_state.clients > 0 then
    print('Active clients:')
    for _, client_name in ipairs(lsp_state.clients) do
      print('  ' .. client_name)
    end
  else
    print('No active LSP clients')
  end

  return lsp_state
end

-- Manually setup LSP servers
function M.lsp_setup()
  -- Basic initialization checks
  log = log or require('devcontainer.utils.log')
  config = config or require('devcontainer.config')

  if not state.initialized then
    log.error('Plugin not initialized. Call setup() first.')
    return false
  end

  if not state.current_container then
    log.error('No active container. Start container first with :DevcontainerStart')
    return false
  end

  -- Check if container is actually running
  docker = docker or require('devcontainer.docker.init')
  local container_status = docker.get_container_status(state.current_container)

  if container_status ~= 'running' then
    log.error('Container is not running (status: %s). Start container first.', container_status or 'unknown')
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
    log.warn('Failed to load LSP path module')
  end

  -- Check current LSP state before setup
  local current_state = lsp.get_state()
  log.info(
    'Current LSP state - Container: %s, Clients: %d',
    current_state.container_id or 'none',
    #current_state.clients
  )

  -- Setup LSP servers (now with duplicate detection)
  lsp.setup_lsp_in_container()

  log.info('LSP setup completed')
  return true
end

-- Get current plugin state
function M.get_state()
  local container_status = nil

  if state.current_container and docker then
    local now = vim.loop.now()
    local cache = state.status_cache

    -- Check if we have cached status and it's still valid
    if cache.container_status ~= nil and (now - cache.last_update) < cache.update_interval then
      container_status = cache.container_status
    else
      -- Refresh container status
      container_status = docker.get_container_status(state.current_container)

      -- Cache the result
      cache.container_status = container_status
      cache.last_update = now
    end
  end

  return {
    initialized = state.initialized,
    current_container = state.current_container,
    current_config = state.current_config,
    container_status = container_status,
  }
end

-- Get container list asynchronously
function M._list_containers_async(filter, callback)
  local args = { 'ps', '-a', '--format', '{{.ID}}\\t{{.Names}}\\t{{.Status}}\\t{{.Image}}' }

  if filter then
    table.insert(args, '--filter')
    table.insert(args, filter)
  end

  vim.fn.jobstart(vim.list_extend({ 'docker' }, args), {
    on_stdout = function(_, data, _)
      local containers = {}
      if data then
        for _, line in ipairs(data) do
          if line and line ~= '' then
            local parts = vim.split(line, '\t')
            if #parts >= 4 then
              table.insert(containers, {
                id = parts[1],
                name = parts[2],
                status = parts[3],
                image = parts[4],
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
  vim.fn.jobstart({ 'docker', 'inspect', container_id, '--format', '{{.State.Status}}' }, {
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

-- Step 4: Container startup process
function M._start_container_step4(container_id)
  print('Step 4: Starting container...')
  docker = docker or require('devcontainer.docker.init')

  docker.start_container_async(container_id, function(success, error_msg)
    vim.schedule(function()
      if success then
        print('✓ Container started successfully and is ready!')
        print('=== Container Ready ===')

        -- Trigger DevcontainerStarted event
        vim.api.nvim_exec_autocmds('User', {
          pattern = 'DevcontainerStarted',
          data = {
            container_id = container_id,
            container_name = state.current_config and state.current_config.name or 'unknown',
          },
        })

        -- Setup LSP integration
        if config.get_value('lsp.auto_setup') then
          print('Setting up LSP...')
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
            log.warn('Failed to load LSP path module')
          end

          lsp.setup_lsp_in_container()
          print('✓ LSP setup complete!')
        end

        print('=== DevContainer fully ready! ===')
      else
        print('✗ Failed to start container: ' .. (error_msg or 'unknown'))
        print('You can try again or check :DevcontainerStatus')
      end
    end)
  end)
end

-- Create container asynchronously
function M._create_container_async(config, callback)
  -- This implementation is complex, so handle with simple error handling for now
  print('Note: Container creation requires image building/pulling.')
  print('For now, please use the standard :DevcontainerStart command.')
  print('This step-by-step version works best with existing containers.')
  callback(nil, 'Container creation requires full :DevcontainerStart workflow')
end

-- Display comprehensive debug information
function M.debug_info()
  print('=== DevContainer Debug Info ===')
  print('Plugin initialized: ' .. tostring(state.initialized))
  print('Current container ID: ' .. (state.current_container or 'none'))
  print('Current config name: ' .. (state.current_config and state.current_config.name or 'none'))

  -- Docker status check
  docker = docker or require('devcontainer.docker.init')
  local docker_available, docker_err = docker.check_docker_availability()
  print('\n--- Docker Status ---')
  print('Docker available: ' .. tostring(docker_available))
  if docker_err then
    print('Docker error: ' .. docker_err)
  end

  -- Container status check (if container exists)
  if state.current_container then
    print('\n--- Container Status ---')
    local container_status = docker.get_container_status(state.current_container)
    local container_info = docker.get_container_info(state.current_container)

    print('Container status: ' .. (container_status or 'unknown'))
    if container_info then
      print('Container image: ' .. (container_info.Config.Image or 'unknown'))
      print('Container created: ' .. (container_info.Created or 'unknown'))

      -- Show ports if any
      if container_info.NetworkSettings and container_info.NetworkSettings.Ports then
        print('Exposed ports:')
        local has_ports = false
        for container_port, host_bindings in pairs(container_info.NetworkSettings.Ports) do
          if host_bindings and #host_bindings > 0 then
            for _, binding in ipairs(host_bindings) do
              print('  ' .. container_port .. ' -> ' .. (binding.HostIp or '0.0.0.0') .. ':' .. binding.HostPort)
              has_ports = true
            end
          end
        end
        if not has_ports then
          print('  (no ports mapped)')
        end
      end
    end
  end

  -- Plugin configuration
  if config then
    print('\n--- Plugin Configuration ---')
    config.show_config()
  end

  -- DevContainer configuration details
  if state.current_config then
    print('\n--- DevContainer Configuration ---')
    print('Name: ' .. (state.current_config.name or 'none'))
    print('Image: ' .. (state.current_config.image or 'none'))
    print('Workspace folder: ' .. (state.current_config.workspace_folder or 'none'))
    print('Base path: ' .. (state.current_config.base_path or 'none'))

    if state.current_config.post_create_command then
      print('Post-create command: ' .. state.current_config.post_create_command)
    end

    if state.current_config.mounts and #state.current_config.mounts > 0 then
      print('Mounts:')
      for _, mount in ipairs(state.current_config.mounts) do
        print('  ' .. mount.source .. ' -> ' .. mount.target .. ' (' .. mount.type .. ')')
      end
    end

    print("Full config: :lua print(vim.inspect(require('devcontainer').get_config()))")
  end

  -- LSP status
  print('\n--- LSP Status ---')
  if lsp then
    M.lsp_status()
  else
    local lsp_module = require('devcontainer.lsp.init')
    local lsp_state = lsp_module.get_state()
    if lsp_state and lsp_state.container_id then
      print('LSP container ID: ' .. lsp_state.container_id)
      print('Detected servers: ' .. table.concat(vim.tbl_keys(lsp_state.servers or {}), ', '))
      print('Active clients: ' .. table.concat(lsp_state.clients or {}, ', '))
    else
      print('LSP not initialized or no container')
    end
  end

  print('\n=== Debug Info Complete ===')
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
  normalized_config.base_path = cwd -- Add base path for container name generation

  -- Generate expected container name using same logic as creation
  local expected_container_name = docker.generate_container_name(normalized_config)

  log.info('Looking for existing container: %s', expected_container_name)

  -- Search for existing containers
  M._list_containers_async('name=' .. expected_container_name, function(containers)
    vim.schedule(function()
      if #containers > 0 then
        local container = containers[1]
        log.info('Found existing container: %s (%s)', container.id, container.status)

        -- Restore state
        state.current_container = container.id
        clear_status_cache()
        state.current_config = normalized_config

        print('✓ Reconnected to existing container: ' .. container.id:sub(1, 12))
        print('  Status: ' .. container.status)
        print('  Use :DevcontainerStatus for details')

        -- Trigger DevcontainerOpened event for reconnection
        vim.api.nvim_exec_autocmds('User', {
          pattern = 'DevcontainerOpened',
          data = {
            container_name = normalized_config.name,
            config_path = cwd,
            reconnected = true,
          },
        })

        -- Auto-setup LSP (if configured)
        if config and config.get_value('lsp.auto_setup') and container.status == 'running' then
          print('  Setting up LSP...')
          vim.defer_fn(function()
            -- Check if LSP is already configured for this container
            if lsp then
              local current_state = lsp.get_state()
              if current_state.container_id == container.id then
                print('  ✓ LSP already configured for this container')
                return
              end
            end

            local success = M.lsp_setup()
            if success then
              print('  ✓ LSP setup complete')
            else
              print('  ⚠ LSP setup failed')
            end
          end, 2000)
        end
      else
        log.debug('No existing containers found for this project')
      end
    end)
  end)
end

-- Manually reconnect to existing container
function M.reconnect()
  print('=== Reconnecting to Existing Container ===')
  state.current_container = nil
  clear_status_cache()
  state.current_config = nil
  M._try_reconnect_existing_container()
end

-- Execute postCreateCommand
function M._run_post_create_command(container_id, callback)
  log = log or require('devcontainer.utils.log')

  log.debug('Checking for postCreateCommand...')
  log.debug('Current config exists: %s', tostring(state.current_config ~= nil))

  if state.current_config then
    log.debug('Config keys: %s', vim.inspect(vim.tbl_keys(state.current_config)))
    log.debug('postCreateCommand value: %s', tostring(state.current_config.postCreateCommand))
    log.debug('post_create_command value: %s', tostring(state.current_config.post_create_command))
  end

  if not state.current_config or not state.current_config.post_create_command then
    print('No postCreateCommand found, skipping...')
    log.debug('No postCreateCommand found, skipping')
    callback(true)
    return
  end

  local command = state.current_config.post_create_command
  print('Step 4.5: Running postCreateCommand...')
  log.info('Executing postCreateCommand: %s', command)

  local docker = require('devcontainer.docker.init')
  local exec_args = {
    'exec',
    '-i',
    '--user',
    'vscode',
    '-e',
    'PATH=/home/vscode/.local/bin:/usr/local/go/bin:/go/bin:/usr/local/python/current/bin:/usr/local/bin:/usr/bin:/bin',
    '-e',
    'GOPATH=/go',
    '-e',
    'GOROOT=/usr/local/go',
    container_id,
    'bash',
    '-c',
    command,
  }

  docker.run_docker_command_async(exec_args, {}, function(result)
    vim.schedule(function()
      if result.success then
        print('✓ postCreateCommand completed successfully')
        log.info('postCreateCommand output: %s', result.stdout)
        if result.stderr and result.stderr ~= '' then
          log.debug('postCreateCommand stderr: %s', result.stderr)
        end
        callback(true)
      else
        print('✗ postCreateCommand failed')
        log.error('postCreateCommand failed with code %d', result.code)
        log.error('Error output: %s', result.stderr or '')
        log.error('Stdout: %s', result.stdout or '')
        callback(false)
      end
    end)
  end)
end

-- StatusLine integration API
function M.statusline()
  if not state.initialized then
    return ''
  end

  local statusline = require('devcontainer.ui.statusline')
  return statusline.get_status()
end

function M.statusline_component()
  if not state.initialized then
    return function()
      return ''
    end
  end

  local statusline = require('devcontainer.ui.statusline')
  return statusline.lualine_component()
end

return M
