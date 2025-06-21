-- lua/devcontainer/init.lua
-- container.nvim main entry point
--
-- This module triggers the following User autocmd events:
-- - ContainerOpened: When devcontainer config is loaded
-- - ContainerBuilt: When container image is built/prepared
-- - ContainerStarted: When container starts successfully
-- - ContainerStopped: When container stops or is killed
-- - ContainerClosed: When devcontainer is closed/reset

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
    update_interval = 5000, -- Update container status every 5 seconds
    updating = false, -- Flag to prevent concurrent updates
  },
}

-- Clear status cache when state changes
local function clear_status_cache()
  state.status_cache.container_status = nil
  state.status_cache.last_update = 0
  state.status_cache.updating = false
end

-- Configuration setup
function M.setup(user_config)
  log = require('container.utils.log')
  config = require('container.config')
  notify = require('container.utils.notify')

  local success, result = config.setup(user_config)
  if not success then
    log.error('Failed to setup configuration')
    return false
  end

  -- Initialize terminal system
  local terminal_ok, terminal_err = pcall(function()
    local terminal = require('container.terminal')
    terminal.setup(config.get())
  end)

  if not terminal_ok then
    log.warn('Failed to initialize terminal system: %s', terminal_err)
  end

  -- Initialize telescope integration if enabled
  if config.get().ui.use_telescope then
    local telescope_ok, telescope_err = pcall(function()
      local telescope_integration = require('container.ui.telescope')
      telescope_integration.setup()
    end)

    if not telescope_ok then
      log.warn('Failed to initialize telescope integration: %s', telescope_err)
    end
  end

  -- Initialize statusline integration if enabled
  if config.get().ui.status_line then
    local statusline_ok, statusline_err = pcall(function()
      local statusline = require('container.ui.statusline')
      statusline.setup()
    end)

    if not statusline_ok then
      log.warn('Failed to initialize statusline integration: %s', statusline_err)
    end
  end

  -- Initialize DAP integration
  local dap_ok, dap_err = pcall(function()
    local dap = require('container.dap')
    dap.setup()
  end)

  if not dap_ok then
    log.debug('Failed to initialize DAP integration: %s', dap_err)
  end

  state.initialized = true
  log.debug('container.nvim initialized successfully')

  -- Attempt to auto-detect and reconnect to existing containers
  vim.defer_fn(function()
    M._try_reconnect_existing_container()
  end, 1000)

  return true
end

-- Open devcontainer
function M.open(path)
  log = log or require('container.utils.log')

  if not state.initialized then
    log.error('Plugin not initialized. Call setup() first.')
    return false
  end

  parser = parser or require('container.parser')
  docker = docker or require('container.docker')

  path = path or vim.fn.getcwd()
  log.info('Opening devcontainer from path: %s', path)

  -- Check Docker availability
  local docker_ok, docker_err = docker.check_docker_availability()
  if not docker_ok then
    log.error('Docker is not available: %s', docker_err)
    -- Display detailed error message to user
    notify.error('Docker is not available', docker_err)
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

  -- Trigger ContainerOpened event
  vim.api.nvim_exec_autocmds('User', {
    pattern = 'ContainerOpened',
    data = {
      container_name = normalized_config.name,
      config_path = path,
    },
  })

  return true
end

-- Prepare image (build or pull)
function M.build()
  log = log or require('container.utils.log')

  if not state.current_config then
    log.error('No devcontainer configuration loaded')
    return false
  end

  docker = docker or require('container.docker')

  log.info('Preparing devcontainer image')

  return docker.prepare_image(state.current_config, function(data)
    -- Display build progress via notification system
    notify.progress('image_build', nil, nil, data)
  end, function(success, result)
    if success then
      log.info('Successfully prepared devcontainer image')
      -- Trigger ContainerBuilt event
      vim.api.nvim_exec_autocmds('User', {
        pattern = 'ContainerBuilt',
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
  log = log or require('container.utils.log')

  if not state.initialized then
    log.error('Plugin not initialized. Call setup() first.')
    return false
  end

  -- If no configuration is loaded, try to load it automatically
  if not state.current_config then
    log.info('No devcontainer configuration loaded, attempting to load...')
    local success = M.open()
    if not success then
      log.error('Failed to load devcontainer configuration. Use :DevcontainerOpen first.')
      return false
    end
    -- Since open() is synchronous and includes container building/creation,
    -- we need to restart the async start process
    return M.start()
  end

  docker = docker or require('container.docker.init')

  log.info('Starting devcontainer...')
  notify.container('Starting DevContainer...', 'info')

  -- Check if image is prepared
  local has_image = state.current_config.built_image
    or state.current_config.prepared_image
    or state.current_config.image

  if not has_image then
    log.info('Image not prepared, building/pulling first...')
    notify.container('Building/pulling image... This may take a while.', 'info')
    notify.status('Image building is not yet fully async. This may take time.', 'info')
    M.build()
    return true
  end

  -- Check Docker availability (async)
  notify.progress('start', 'Step 1: Checking Docker...')
  docker.check_docker_availability_async(function(available, err)
    vim.schedule(function()
      if not available then
        notify.critical('Docker not available: ' .. (err or 'unknown'))
        return
      end
      notify.progress('start', 'Step 1: ✓ Docker is available')

      -- Check for existing containers (async)
      notify.progress('start', 'Step 2: Checking for existing containers...')

      -- Generate the expected container name using the same logic as creation
      local expected_container_name = docker.generate_container_name(state.current_config)
      log.info('Looking for container with name: %s', expected_container_name)

      M._list_containers_with_fallback(expected_container_name, function(containers)
        vim.schedule(function()
          local container_id = nil

          if #containers > 0 then
            container_id = containers[1].id
            local container_status = containers[1].status
            log.info('Found existing container: %s (status: %s)', container_id, container_status)
            notify.progress(
              'start',
              'Step 2: ✓ Found existing container: ' .. container_id:sub(1, 12) .. ' (' .. container_status .. ')'
            )
            state.current_container = container_id
            clear_status_cache()

            -- Check if container is already running
            if container_status:match('^Up') then
              -- Container is already running, proceed directly to final setup
              notify.progress('start', 'Step 3: Container already running, setting up features...')
              M._start_final_step(container_id)
            else
              -- Container exists but is not running, start it first
              notify.progress('start', 'Step 3: Starting existing container...')
              M._start_stopped_container(container_id)
            end
          else
            -- Create new container (async)
            notify.progress('start', 'Step 3: Creating new container...')
            M._create_container_full_async(state.current_config, function(create_result, create_err)
              vim.schedule(function()
                if not create_result then
                  log.error('Failed to create container: %s', create_err)
                  notify.critical('Failed to create container: ' .. (create_err or 'unknown'))
                  return
                end
                container_id = create_result
                notify.progress('start', 'Step 3: ✓ Created container: ' .. container_id:sub(1, 12))
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

  notify.status('DevContainer start initiated (non-blocking)...', 'info')
  return true
end

-- Start a stopped container and proceed to final setup
function M._start_stopped_container(container_id)
  docker = docker or require('container.docker.init')

  docker.start_container_async(container_id, function(success, error_msg)
    vim.schedule(function()
      if success then
        notify.progress('start', 'Step 3: ✓ Container started successfully')
        log.info('Stopped container started successfully: %s', container_id)
        -- Proceed to final setup
        M._start_final_step(container_id)
      else
        log.error('Failed to start stopped container: %s', error_msg or 'unknown')
        notify.critical('Failed to start existing container: ' .. (error_msg or 'unknown'))
        notify.clear_progress('start')
      end
    end)
  end)
end

-- Final step: Container feature setup (assumes container is already running)
function M._start_final_step(container_id)
  notify.progress('start', 'Step 4: Setting up container features...')

  -- Check if container is actually running before proceeding
  docker = docker or require('container.docker.init')
  local container_status = docker.get_container_status(container_id)

  if container_status ~= 'running' then
    -- Container is not running, try to start it first
    notify.progress('start', 'Step 4: Container not running, starting it...')
    docker.start_container_async(container_id, function(success, error_msg)
      vim.schedule(function()
        if success then
          log.info('Container started successfully: %s', container_id)
          M._finalize_container_setup(container_id)
        else
          log.error('Failed to start container: %s', error_msg or 'unknown')
          notify.critical('Failed to start container: ' .. (error_msg or 'unknown'))
          notify.clear_progress('start')
        end
      end)
    end)
  else
    -- Container is already running, proceed with setup
    log.info('Container is already running: %s', container_id)
    M._finalize_container_setup(container_id)
  end
end

-- Finalize container setup after ensuring it's running
function M._finalize_container_setup(container_id)
  notify.container('Container is running!', 'info')
  log.info('Container is ready: %s', container_id)

  -- Trigger ContainerStarted event
  vim.api.nvim_exec_autocmds('User', {
    pattern = 'ContainerStarted',
    data = {
      container_id = container_id,
      container_name = state.current_config and state.current_config.name or 'unknown',
    },
  })

  -- Setup core features with graceful degradation
  M._setup_container_features_gracefully(container_id)

  -- Setup test integration
  local test_config = config.get()
  if
    test_config.test_integration
    and test_config.test_integration.enabled
    and test_config.test_integration.auto_setup
  then
    log.debug('Setting up test integration...')
    vim.defer_fn(function()
      local test_runner = require('container.test_runner')
      if test_runner.setup() then
        log.info('Test integration setup complete')
      end
    end, 500) -- Small delay to ensure everything is loaded
  end

  -- Execute post-start command (existing)
  if state.current_config.post_start_command then
    notify.progress('start', 'Step 6: Running post-start command...')
    M.exec(state.current_config.post_start_command)
  end

  notify.container('DevContainer is ready!', 'info')
  notify.clear_progress('start') -- Clear progress messages
end

-- Full container creation (fully async version)
function M._create_container_full_async(config, callback)
  local docker = require('container.docker.init')

  -- Step 1: Check image existence
  notify.progress('start', 'Step 3a: Checking if image exists locally...')
  docker.check_image_exists_async(config.image, function(exists, image_id)
    vim.schedule(function()
      if exists then
        notify.progress('start', 'Step 3a: ✓ Image found locally: ' .. config.image)
        -- Image exists, create container directly
        M._create_container_direct(config, callback)
      else
        notify.status('Image not found locally, pulling: ' .. config.image, 'warn')
        -- Pull image then create container
        M._pull_and_create_container(config, callback)
      end
    end)
  end)
end

-- Create container after image pull
function M._pull_and_create_container(config, callback)
  local docker = require('container.docker.init')

  notify.container('Step 3b: Pulling image (this may take a while)...', 'info')
  notify.status('Image: ' .. config.image, 'info')
  notify.status('This is a large download and may take 5-15 minutes depending on your connection.', 'info')
  log.info('Starting image pull for: %s', config.image)

  local start_time = vim.fn.reltime()
  local progress_count = 0

  local job_id = docker.pull_image_async(config.image, function(progress)
    progress_count = progress_count + 1
    local elapsed = vim.fn.reltimestr(vim.fn.reltime(start_time))
    -- Use progress consolidation to reduce message spam
    notify.progress('pull', string.format('[%ss] %s', elapsed, progress), {
      consolidate_rapid = true,
      consolidate_threshold = 2000, -- Only show progress every 2 seconds
    })

    -- Confirm that progress is visible
    if progress_count == 1 then
      notify.status('Docker pull output started - progress tracking is working', 'info')
    end
  end, function(success, result)
    vim.schedule(function()
      local elapsed = vim.fn.reltimestr(vim.fn.reltime(start_time))
      notify.clear_progress('pull') -- Clear pull progress messages

      log.info('Pull completed with status: %s in %s', tostring(success), elapsed)

      if success then
        notify.container('Image pull completed successfully!', 'info')
        notify.status('Now proceeding to create container...', 'info')

        -- Trigger ContainerBuilt event after successful pull
        vim.api.nvim_exec_autocmds('User', {
          pattern = 'ContainerBuilt',
          data = {
            container_name = config.name or 'unknown',
            image = config.image,
          },
        })

        -- Image pull successful, create container
        M._create_container_direct(config, callback)
      else
        notify.critical('Image pull failed')
        log.error('Image pull failed for %s', config.image)

        local error_details = {}
        if result then
          if result.stderr and result.stderr ~= '' then
            table.insert(error_details, 'Error: ' .. result.stderr)
          end
          if result.error then
            table.insert(error_details, 'Error: ' .. result.error)
          end
          if result.data_received == false then
            table.insert(error_details, 'No data received from Docker command')
            table.insert(error_details, 'Docker may be unresponsive or image name invalid')
          end
        end

        -- Show error details with logging instead of direct print
        for _, detail in ipairs(error_details) do
          log.error(detail)
        end

        notify.status('Troubleshooting: Check network, verify image name: ' .. config.image, 'warn')
        callback(nil, 'Failed to pull image: ' .. (result and result.stderr or result and result.error or 'unknown'))
      end
    end)
  end)

  if job_id and job_id > 0 then
    notify.status('Pull job started successfully (ID: ' .. job_id .. ')', 'info')
    log.debug('Docker pull job started with ID: %d', job_id)

    -- Check progress after 30 seconds
    vim.defer_fn(function()
      if progress_count == 0 then
        notify.status('Warning: No progress received after 30 seconds', 'warn')
        notify.status('This may indicate a Docker or network issue', 'warn')
        log.warn('No pull progress received after 30 seconds for image: %s', config.image)
      end
    end, 30000)
  else
    notify.critical('Failed to start pull job')
    log.error('Failed to start Docker pull job, job_id: %s', tostring(job_id))
    callback(nil, 'Failed to start Docker pull job')
  end
end

-- Direct container creation with conflict handling
function M._create_container_direct(config, callback)
  local docker = require('container.docker.init')

  notify.progress('start', 'Step 3c: Creating container...')

  -- First attempt to create the container
  docker.create_container_async(config, function(container_id, error_msg)
    if container_id then
      notify.progress('start', 'Step 3c: ✓ Container created successfully: ' .. container_id:sub(1, 12))
      log.info('Container created successfully: %s', container_id)
      callback(container_id, error_msg)
    else
      -- Check if error is due to name conflict
      if error_msg and error_msg:match('already in use') then
        log.warn('Container name conflict detected, attempting to handle existing container')
        notify.progress('start', 'Step 3c: Name conflict detected, checking existing container...')

        -- Try to find and reuse the existing container
        local expected_name = docker.generate_container_name(config)
        M._list_containers_with_fallback(expected_name, function(existing_containers)
          vim.schedule(function()
            if #existing_containers > 0 then
              local existing_container = existing_containers[1]
              log.info(
                'Found existing conflicting container: %s (status: %s)',
                existing_container.id,
                existing_container.status
              )
              notify.progress('start', 'Step 3c: ✓ Using existing container: ' .. existing_container.id:sub(1, 12))

              -- Return the existing container instead of creating a new one
              callback(existing_container.id, nil)
            else
              -- Existing container not found via our search, still fail
              notify.critical('Container creation failed: ' .. (error_msg or 'unknown'))
              log.error('Container creation failed: %s', error_msg or 'unknown')
              callback(nil, error_msg)
            end
          end)
        end)
      else
        -- Other creation error, propagate it
        notify.critical('Container creation failed: ' .. (error_msg or 'unknown'))
        log.error('Container creation failed: %s', error_msg or 'unknown')
        callback(container_id, error_msg)
      end
    end
  end)
end

-- Stop container
function M.stop()
  log = log or require('container.utils.log')

  if not state.current_container then
    log.error('No active container')
    return false
  end

  docker = docker or require('container.docker.init')
  local notify = require('container.utils.notify')

  -- Stop LSP clients
  if lsp then
    lsp.stop_all()
  end

  -- Clean up port allocations
  if state.current_config and state.current_config.project_id then
    local port_utils = require('container.utils.port')
    port_utils.release_project_ports(state.current_config.project_id)
  end

  log.info('Stopping container: %s', state.current_container)
  notify.container('Stopping container...', 'info')

  -- Use async version to prevent freezing
  docker.stop_container_async(state.current_container, function(success, error_msg)
    vim.schedule(function()
      if success then
        notify.container('Container stopped successfully', 'info')
        log.info('Container stopped successfully: %s', state.current_container)

        -- Trigger ContainerStopped event
        vim.api.nvim_exec_autocmds('User', {
          pattern = 'ContainerStopped',
          data = {
            container_id = state.current_container,
            container_name = state.current_config and state.current_config.name or 'unknown',
          },
        })

        -- Clear state after successful stop
        state.current_container = nil
        clear_status_cache()
        state.current_config = nil
      else
        notify.critical('Failed to stop container: ' .. (error_msg or 'unknown'))
        log.error('Failed to stop container: %s', error_msg or 'unknown')
      end
    end)
  end)

  return true
end

-- Kill container (immediate termination)
function M.kill()
  log = log or require('container.utils.log')

  if not state.current_container then
    log.error('No active container')
    return false
  end

  docker = docker or require('container.docker.init')

  -- Stop LSP clients
  if lsp then
    lsp.stop_all()
  end

  -- Clean up port allocations
  if state.current_config and state.current_config.project_id then
    local port_utils = require('container.utils.port')
    port_utils.release_project_ports(state.current_config.project_id)
  end

  log.info('Killing container: %s', state.current_container)
  docker.kill_container(state.current_container, function(success, error_msg)
    vim.schedule(function()
      if success then
        notify.container('Container killed successfully', 'info')
        log.info('Container killed successfully: %s', state.current_container)
        -- Trigger ContainerStopped event before clearing state
        vim.api.nvim_exec_autocmds('User', {
          pattern = 'ContainerStopped',
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
        notify.critical('Failed to kill container: ' .. (error_msg or 'unknown'))
        log.error('Failed to kill container: %s', error_msg or 'unknown')
      end
    end)
  end)

  return true
end

-- Terminate container (alias for kill)
function M.terminate()
  log = log or require('container.utils.log')

  if not state.current_container then
    log.error('No active container')
    return false
  end

  docker = docker or require('container.docker.init')

  -- Stop LSP clients
  if lsp then
    lsp.stop_all()
  end

  -- Clean up port allocations
  if state.current_config and state.current_config.project_id then
    local port_utils = require('container.utils.port')
    port_utils.release_project_ports(state.current_config.project_id)
  end

  log.info('Terminating container: %s', state.current_container)
  docker.terminate_container(state.current_container, function(success, error_msg)
    vim.schedule(function()
      if success then
        notify.container('Container terminated successfully', 'info')
        log.info('Container terminated successfully: %s', state.current_container)
        -- Trigger ContainerStopped event before clearing state
        vim.api.nvim_exec_autocmds('User', {
          pattern = 'ContainerStopped',
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
        notify.critical('Failed to terminate container: ' .. (error_msg or 'unknown'))
        log.error('Failed to terminate container: %s', error_msg or 'unknown')
      end
    end)
  end)

  return true
end

-- Remove container
function M.remove()
  log = log or require('container.utils.log')

  if not state.current_container then
    log.error('No active container')
    return false
  end

  docker = docker or require('container.docker.init')

  -- Stop LSP clients
  if lsp then
    lsp.stop_all()
  end

  -- Clean up port allocations
  if state.current_config and state.current_config.project_id then
    local port_utils = require('container.utils.port')
    port_utils.release_project_ports(state.current_config.project_id)
  end

  log.info('Removing container: %s', state.current_container)
  docker.remove_container_async(state.current_container, false, function(success, error_msg)
    vim.schedule(function()
      if success then
        print('✓ Container removed successfully')
        -- Trigger ContainerStopped event before clearing state
        vim.api.nvim_exec_autocmds('User', {
          pattern = 'ContainerStopped',
          data = {
            container_id = state.current_container,
            container_name = state.current_config and state.current_config.name or 'unknown',
          },
        })
        state.current_container = nil
        clear_status_cache()
        state.current_config = nil
      else
        print('✗ Failed to remove container: ' .. (error_msg or 'unknown'))
      end
    end)
  end)

  return true
end

-- Stop and remove container
function M.stop_and_remove()
  log = log or require('container.utils.log')

  if not state.current_container then
    log.error('No active container')
    return false
  end

  docker = docker or require('container.docker.init')

  -- Stop LSP clients
  if lsp then
    lsp.stop_all()
  end

  -- Clean up port allocations
  if state.current_config and state.current_config.project_id then
    local port_utils = require('container.utils.port')
    port_utils.release_project_ports(state.current_config.project_id)
  end

  log.info('Stopping and removing container: %s', state.current_container)
  docker.stop_and_remove_container(state.current_container, 30, function(success, error_msg)
    vim.schedule(function()
      if success then
        print('✓ Container stopped and removed successfully')
        -- Trigger ContainerStopped event before clearing state
        vim.api.nvim_exec_autocmds('User', {
          pattern = 'ContainerStopped',
          data = {
            container_id = state.current_container,
            container_name = state.current_config and state.current_config.name or 'unknown',
          },
        })
        state.current_container = nil
        clear_status_cache()
        state.current_config = nil
      else
        print('✗ Failed to stop and remove container: ' .. (error_msg or 'unknown'))
      end
    end)
  end)

  return true
end

-- Enhanced terminal functions

-- Create or switch to terminal session
function M.terminal(opts)
  local terminal = require('container.terminal')
  return terminal.terminal(opts)
end

-- Create new terminal session
function M.terminal_new(name)
  local terminal = require('container.terminal')
  return terminal.new_session(name)
end

-- List terminal sessions
function M.terminal_list()
  local terminal = require('container.terminal')
  return terminal.list_sessions()
end

-- Close terminal session
function M.terminal_close(name)
  local terminal = require('container.terminal')
  return terminal.close_session(name)
end

-- Close all terminal sessions
function M.terminal_close_all()
  local terminal = require('container.terminal')
  return terminal.close_all_sessions()
end

-- Rename terminal session
function M.terminal_rename(old_name, new_name)
  local terminal = require('container.terminal')
  return terminal.rename_session(old_name, new_name)
end

-- Switch to next terminal session
function M.terminal_next()
  local terminal = require('container.terminal')
  return terminal.next_session()
end

-- Switch to previous terminal session
function M.terminal_prev()
  local terminal = require('container.terminal')
  return terminal.prev_session()
end

-- Show terminal status
function M.terminal_status()
  local terminal = require('container.terminal')
  return terminal.show_status()
end

-- Clean up terminal history
function M.terminal_cleanup_history(days)
  local terminal = require('container.terminal')
  return terminal.cleanup_history(days)
end

-- Attach to existing container
function M.attach(container_name)
  log = log or require('container.utils.log')
  docker = docker or require('container.docker')

  docker.attach_to_container(container_name, function(success, error_msg)
    if success then
      state.current_container = container_name
      clear_status_cache()
      log.info('Attached to container: %s', container_name)
      notify.container('Attached to container: ' .. container_name)

      -- Trigger ContainerOpened event for attach
      vim.api.nvim_exec_autocmds('User', {
        pattern = 'ContainerOpened',
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
  log = log or require('container.utils.log')
  docker = docker or require('container.docker')

  docker.start_existing_container(container_name, function(success, error_msg)
    if success then
      log.info('Started container: %s', container_name)
      notify.container('Started container: ' .. container_name)

      -- Trigger ContainerStarted event
      vim.api.nvim_exec_autocmds('User', {
        pattern = 'ContainerStarted',
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
  log = log or require('container.utils.log')
  docker = docker or require('container.docker')

  docker.stop_existing_container(container_name, function(success, error_msg)
    if success then
      log.info('Stopped container: %s', container_name)
      notify.container('Stopped container: ' .. container_name)

      -- Trigger ContainerStopped event
      vim.api.nvim_exec_autocmds('User', {
        pattern = 'ContainerStopped',
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

-- Restart the current DevContainer
function M.restart()
  log = log or require('container.utils.log')

  if not state.current_container then
    log.error('No active container to restart')
    notify.error('No active container to restart')
    return false
  end

  local container_id = state.current_container
  notify.container('Restarting DevContainer...', 'info')
  log.info('Restarting current container: %s', container_id)

  docker = docker or require('container.docker.init')

  -- First stop the container
  docker.stop_container_async(container_id, function(stop_success, stop_error)
    vim.schedule(function()
      if stop_success then
        log.info('Container stopped for restart: %s', container_id)
        notify.progress('restart', 'Step 1: ✓ Container stopped')

        -- Wait a moment then start again
        vim.defer_fn(function()
          notify.progress('restart', 'Step 2: Starting container...')
          docker.start_container_async(container_id, function(start_success, start_error)
            vim.schedule(function()
              if start_success then
                notify.progress('restart', 'Step 2: ✓ Container started')
                log.info('Container restarted successfully: %s', container_id)

                -- Trigger ContainerStarted event
                vim.api.nvim_exec_autocmds('User', {
                  pattern = 'ContainerStarted',
                  data = {
                    container_id = container_id,
                    container_name = state.current_config and state.current_config.name or 'unknown',
                    restarted = true,
                  },
                })

                notify.container('DevContainer restarted successfully!', 'info')
                notify.clear_progress('restart')
              else
                log.error('Failed to start container after stop: %s', start_error or 'unknown')
                notify.critical('Failed to start container after restart: ' .. (start_error or 'unknown'))
                notify.clear_progress('restart')
              end
            end)
          end)
        end, 1000) -- Wait 1 second between stop and start
      else
        log.error('Failed to stop container for restart: %s', stop_error or 'unknown')
        notify.critical('Failed to stop container for restart: ' .. (stop_error or 'unknown'))
        notify.clear_progress('restart')
      end
    end)
  end)

  return true
end

-- Restart a specific container by name
function M.restart_container(container_name)
  log = log or require('container.utils.log')
  docker = docker or require('container.docker')

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
  log = log or require('container.utils.log')

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
  log = log or require('container.utils.log')

  if not state.current_container then
    notify.status('No active container', 'info')
    return nil
  end

  docker = docker or require('container.docker')

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
      local port_utils = require('container.utils.port')
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
  log = log or require('container.utils.log')

  if not state.current_container then
    log.error('No active container')
    return false
  end

  docker = docker or require('container.docker')
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

-- Execute command in container
function M.execute(command, opts)
  log = log or require('container.utils.log')
  docker = docker or require('container.docker')

  if not state.current_container then
    log.error('No active container')
    return nil, 'No active container'
  end

  opts = opts or {}

  -- Set default working directory from config if not specified
  if not opts.workdir and state.current_config and state.current_config.workspace_folder then
    opts.workdir = state.current_config.workspace_folder
  end

  -- Set default user from config if not specified
  if not opts.user and state.current_config and state.current_config.remote_user then
    opts.user = state.current_config.remote_user
  end

  -- Log command execution
  local command_str = type(command) == 'string' and command or table.concat(command, ' ')
  log.info('Executing command in container: %s', command_str)

  -- Execute command
  local result = docker.execute_command(state.current_container, command, opts)

  -- Handle result based on mode
  if opts.mode == 'async' or opts.mode == 'fire_and_forget' then
    return result -- Job ID or nil
  else
    -- Sync mode returns result
    if result and result.success then
      log.debug('Command executed successfully')
      return result.stdout, nil
    else
      local error_msg = result and result.stderr or 'Command execution failed'
      log.error('Command execution failed: %s', error_msg)
      return nil, error_msg
    end
  end
end

-- Execute command with streaming output
function M.execute_stream(command, opts)
  log = log or require('container.utils.log')
  docker = docker or require('container.docker')

  if not state.current_container then
    log.error('No active container')
    return nil, 'No active container'
  end

  opts = opts or {}

  -- Set default working directory from config if not specified
  if not opts.workdir and state.current_config and state.current_config.workspace_folder then
    opts.workdir = state.current_config.workspace_folder
  end

  -- Set default user from config if not specified
  if not opts.user and state.current_config and state.current_config.remote_user then
    opts.user = state.current_config.remote_user
  end

  -- Log command execution
  local command_str = type(command) == 'string' and command or table.concat(command, ' ')
  log.info('Executing streaming command in container: %s', command_str)

  -- Execute command with streaming
  return docker.execute_command_stream(state.current_container, command, opts)
end

-- Build complex command with environment setup
function M.build_command(base_command, opts)
  docker = docker or require('container.docker')
  return docker.build_command(base_command, opts)
end

-- Run test command in container
function M.run_test(test_cmd, opts)
  log = log or require('container.utils.log')

  opts = opts or {}
  local config_data = config.get()

  -- Set appropriate output mode
  if config_data.test_integration.output_mode == 'terminal' then
    -- Use terminal for interactive output
    local terminal = require('container.terminal')
    return terminal.execute(
      test_cmd,
      vim.tbl_extend('force', {
        name = 'test',
        close_on_exit = false,
      }, opts)
    )
  else
    -- Use buffer mode with streaming
    local stdout_lines = {}
    local stderr_lines = {}

    local stream_opts = vim.tbl_extend('force', {
      on_stdout = function(line)
        table.insert(stdout_lines, line)
        if opts.on_stdout then
          opts.on_stdout(line)
        end
      end,
      on_stderr = function(line)
        table.insert(stderr_lines, line)
        if opts.on_stderr then
          opts.on_stderr(line)
        end
      end,
      on_exit = function(exit_code)
        local result = {
          success = exit_code == 0,
          code = exit_code,
          stdout = table.concat(stdout_lines, '\n'),
          stderr = table.concat(stderr_lines, '\n'),
        }
        if opts.on_complete then
          opts.on_complete(result)
        end
      end,
    }, opts)

    return M.execute_stream(test_cmd, stream_opts)
  end
end

-- Reset plugin state
function M.reset()
  log = log or require('container.utils.log')

  -- Trigger ContainerClosed event before clearing state
  if state.current_container or state.current_config then
    vim.api.nvim_exec_autocmds('User', {
      pattern = 'ContainerClosed',
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
  log = log or require('container.utils.log')

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
  local port_utils = require('container.utils.port')
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
    docker = docker or require('container.docker')
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
  local port_utils = require('container.utils.port')
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
function M.lsp_status(detailed)
  log = log or require('container.utils.log')
  config = config or require('container.config')

  -- Initialize LSP module (if not already done)
  if not lsp then
    if not state.initialized then
      log.warn('Plugin not fully initialized')
      return nil
    end

    lsp = require('container.lsp.init')
    lsp.setup(config.get_value('lsp') or {})
  end

  local lsp_state = lsp.get_state()
  print('=== DevContainer LSP Status ===')
  print('Container ID: ' .. (lsp_state.container_id or 'none'))
  print('Auto setup: ' .. tostring(lsp_state.config and lsp_state.config.auto_setup or 'unknown'))

  if lsp_state.servers and next(lsp_state.servers) then
    print('\nDetected servers:')
    for name, server in pairs(lsp_state.servers) do
      if detailed then
        print(string.format('  📋 %s:', name))
        print(string.format('    Command: %s', server.cmd))
        print(string.format('    Available: %s', tostring(server.available)))
        if server.path then
          print(string.format('    Path: %s', server.path))
        end
        if server.languages then
          print(string.format('    Languages: %s', table.concat(server.languages, ', ')))
        end
      else
        print(string.format('  %s: %s (available: %s)', name, server.cmd, tostring(server.available)))
      end
    end
  else
    print('\nNo servers detected (container may not be running)')
    if detailed then
      print('  💡 Possible reasons:')
      print('    • LSP servers not installed in container')
      print('    • Container not running')
      print('    • PATH configuration issues')
    end
  end

  if lsp_state.clients and #lsp_state.clients > 0 then
    print('\nActive clients:')
    for _, client_name in ipairs(lsp_state.clients) do
      if detailed then
        -- Get additional client info
        local clients = vim.lsp.get_active_clients({ name = client_name })
        if #clients > 0 then
          local client = clients[1]
          print(string.format('  🔌 %s (ID: %d)', client_name, client.id))
          if client.config and client.config.root_dir then
            print(string.format('    Root: %s', client.config.root_dir))
          end
          local attached_buffers = vim.lsp.get_buffers_by_client_id(client.id)
          print(string.format('    Buffers: %d attached', #attached_buffers))
        else
          print('  ⚠️  ' .. client_name .. ' (client not found)')
        end
      else
        print('  ' .. client_name)
      end
    end
  else
    print('\nNo active LSP clients')
    if detailed then
      print('  💡 Try:')
      print('    • :ContainerLspSetup - initialize servers')
      print('    • :ContainerLspRecover - recover failed servers')
    end
  end

  if detailed then
    print('\n🔧 Available commands:')
    print('  :ContainerLspDiagnose - health check and troubleshooting')
    print('  :ContainerLspRecover - recover all failed servers')
    print('  :ContainerLspRetry <server> - retry specific server')
    print('  :ContainerLspSetup - setup LSP servers')
  else
    print('\nFor detailed info: :ContainerLspStatus true')
    print('For troubleshooting: :ContainerLspDiagnose')
  end

  return lsp_state
end

-- Manually setup LSP servers
function M.lsp_setup()
  -- Basic initialization checks
  log = log or require('container.utils.log')
  config = config or require('container.config')

  if not state.initialized then
    log.error('Plugin not initialized. Call setup() first.')
    return false
  end

  if not state.current_container then
    log.error('No active container. Start container first with :DevcontainerStart')
    return false
  end

  -- Check if container is actually running
  docker = docker or require('container.docker.init')
  local container_status = docker.get_container_status(state.current_container)

  if container_status ~= 'running' then
    log.error('Container is not running (status: %s). Start container first.', container_status or 'unknown')
    return false
  end

  -- Initialize LSP module
  lsp = lsp or require('container.lsp.init')
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
      -- Use cached value while updating asynchronously
      container_status = cache.container_status or 'unknown'

      -- Trigger async update if not already in progress
      if not cache.updating then
        cache.updating = true
        M._get_container_status_async(state.current_container, function(status)
          if status then
            cache.container_status = status
            cache.last_update = vim.loop.now()
          end
          cache.updating = false
        end)
      end
    end
  end

  return {
    initialized = state.initialized,
    current_container = state.current_container,
    current_config = state.current_config,
    container_status = container_status,
  }
end

-- Enhanced container search with fallback methods
function M._list_containers_with_fallback(expected_name, callback)
  log.debug('Searching for container: %s', expected_name)

  -- Method 1: Try name filter first
  M._list_containers_async('name=' .. expected_name, function(containers)
    if #containers > 0 then
      log.info('Found container using name filter: %s', expected_name)
      callback(containers)
      return
    end

    log.debug('No containers found with name filter, trying full list search...')

    -- Method 2: Get all containers and search manually
    M._list_containers_async(nil, function(all_containers)
      local matched_containers = {}

      for _, container in ipairs(all_containers) do
        local container_name = container.name
        -- Remove leading slash if present (Docker sometimes returns /container_name)
        if container_name:sub(1, 1) == '/' then
          container_name = container_name:sub(2)
        end

        log.debug('Checking container: %s (original: %s)', container_name, container.name)

        if container_name == expected_name then
          log.info('Found matching container: %s (ID: %s, Status: %s)', container_name, container.id, container.status)
          table.insert(matched_containers, container)
        end
      end

      if #matched_containers == 0 then
        log.info('No containers found matching name: %s', expected_name)
        log.debug('Available containers:')
        for _, container in ipairs(all_containers) do
          log.debug('  - %s (ID: %s)', container.name, container.id)
        end
      end

      callback(matched_containers)
    end)
  end)
end

-- Get container list asynchronously
function M._list_containers_async(filter, callback)
  local args = { 'ps', '-a', '--format', '{{.ID}}\\t{{.Names}}\\t{{.Status}}\\t{{.Image}}' }

  if filter then
    table.insert(args, '--filter')
    table.insert(args, filter)
  end

  local docker = require('container.docker.init')
  docker.run_docker_command_async(args, {}, function(result)
    local containers = {}

    if result.success and result.stdout then
      for line in result.stdout:gmatch('[^\n]+') do
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
    else
      log.warn('Failed to list containers: %s', result.stderr or 'unknown error')
    end

    callback(containers)
  end)
end

-- Get container status asynchronously
function M._get_container_status_async(container_id, callback)
  local docker = require('container.docker.init')
  docker.run_docker_command_async({ 'inspect', container_id, '--format', '{{.State.Status}}' }, {}, function(result)
    local status = nil

    if result.success and result.stdout then
      status = vim.trim(result.stdout)
    else
      log.debug('Failed to get container status: %s', result.stderr or 'unknown error')
    end

    callback(status)
  end)
end

-- Step 4: Container startup process
function M._start_container_step4(container_id)
  notify.progress('container_start', 4, 4, 'Starting container...')
  docker = docker or require('container.docker.init')

  docker.start_container_async(container_id, function(success, error_msg)
    vim.schedule(function()
      if success then
        notify.success('Container started successfully and is ready!')
        notify.container('Container is now ready for development')

        -- Trigger ContainerStarted event
        vim.api.nvim_exec_autocmds('User', {
          pattern = 'ContainerStarted',
          data = {
            container_id = container_id,
            container_name = state.current_config and state.current_config.name or 'unknown',
          },
        })

        -- Setup LSP integration
        if config.get_value('lsp.auto_setup') then
          print('Setting up LSP...')
          lsp = lsp or require('container.lsp.init')
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
  notify.status('Note: Container creation requires image building/pulling.')
  notify.status('For now, please use the standard :ContainerStart command.')
  notify.status('This step-by-step version works best with existing containers.')
  callback(nil, 'Container creation requires full :DevcontainerStart workflow')
end

-- Display comprehensive debug information
function M.debug_info()
  print('=== DevContainer Debug Info ===')
  print('Plugin initialized: ' .. tostring(state.initialized))
  print('Current container ID: ' .. (state.current_container or 'none'))
  print('Current config name: ' .. (state.current_config and state.current_config.name or 'none'))

  -- Docker status check
  docker = docker or require('container.docker.init')
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

    print("Full config: :lua print(vim.inspect(require('container').get_config()))")
  end

  -- LSP status
  print('\n--- LSP Status ---')
  if lsp then
    M.lsp_status()
  else
    local lsp_module = require('container.lsp.init')
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
  log = log or require('container.utils.log')

  if state.current_container then
    -- Skip if container is already configured
    return
  end

  docker = docker or require('container.docker.init')

  -- Search for devcontainer.json in current directory
  local cwd = vim.fn.getcwd()
  parser = parser or require('container.parser')

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
  M._list_containers_with_fallback(expected_container_name, function(containers)
    vim.schedule(function()
      if #containers > 0 then
        local container = containers[1]
        log.info('Found existing container: %s (%s)', container.id, container.status)

        -- Restore state
        state.current_container = container.id
        clear_status_cache()
        state.current_config = normalized_config

        notify.success('Reconnected to existing container: ' .. container.id:sub(1, 12))
        notify.container('Status: ' .. container.status)
        notify.info('Use :ContainerStatus for details')

        -- Trigger ContainerOpened event for reconnection
        vim.api.nvim_exec_autocmds('User', {
          pattern = 'ContainerOpened',
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
  notify.container('Reconnecting to existing container...')
  state.current_container = nil
  clear_status_cache()
  state.current_config = nil
  M._try_reconnect_existing_container()
end

-- Execute postCreateCommand
function M._run_post_create_command(container_id, callback)
  log = log or require('container.utils.log')

  log.debug('Checking for postCreateCommand...')
  log.debug('Current config exists: %s', tostring(state.current_config ~= nil))

  if state.current_config then
    log.debug('Config keys: %s', vim.inspect(vim.tbl_keys(state.current_config)))
    log.debug('postCreateCommand value: %s', tostring(state.current_config.postCreateCommand))
    log.debug('post_create_command value: %s', tostring(state.current_config.post_create_command))
  end

  if not state.current_config or not state.current_config.post_create_command then
    notify.debug('No postCreateCommand found, skipping...')
    log.debug('No postCreateCommand found, skipping')
    callback(true)
    return
  end

  local command = state.current_config.post_create_command
  notify.progress('container_setup', 5, 5, 'Running postCreateCommand...')
  log.info('Executing postCreateCommand: %s', command)

  local docker = require('container.docker.init')
  local environment = require('container.environment')

  -- Build exec args with environment-specific settings
  local exec_args = {
    'exec',
    '-i',
  }

  -- Add environment-specific args (includes user and env vars)
  local env_args = environment.build_postcreate_args(state.current_config)
  for _, arg in ipairs(env_args) do
    table.insert(exec_args, arg)
  end

  -- Set working directory to workspace
  local workspace_folder = state.current_config.workspaceFolder or '/workspace'
  table.insert(exec_args, '-w')
  table.insert(exec_args, workspace_folder)

  -- Add container and command
  table.insert(exec_args, container_id)
  table.insert(exec_args, 'bash')
  table.insert(exec_args, '-c')
  table.insert(exec_args, command)

  docker.run_docker_command_async(exec_args, {}, function(result)
    vim.schedule(function()
      if result.success then
        notify.success('postCreateCommand completed successfully')
        log.info('postCreateCommand output: %s', result.stdout)
        if result.stderr and result.stderr ~= '' then
          log.debug('postCreateCommand stderr: %s', result.stderr)
        end
        callback(true)
      else
        notify.critical('postCreateCommand failed')
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

  local statusline = require('container.ui.statusline')
  return statusline.get_status()
end

function M.statusline_component()
  if not state.initialized then
    return function()
      return ''
    end
  end

  local statusline = require('container.ui.statusline')
  return statusline.lualine_component()
end

-- LSP diagnostic and recovery functions

-- Diagnose LSP server issues with enhanced troubleshooting
function M.diagnose_lsp()
  if not lsp then
    print('✗ LSP module not initialized')
    return false
  end

  local health = lsp.health_check()

  print('=== LSP Diagnostic Report ===')
  print('Container connected: ' .. (health.container_connected and '✓' or '✗'))
  print('LSPConfig available: ' .. (health.lspconfig_available and '✓' or '✗'))
  print('Servers detected: ' .. health.servers_detected)
  print('Active clients: ' .. health.clients_active)

  if #health.issues > 0 then
    print('\n🔍 Issues found:')
    for _, issue in ipairs(health.issues) do
      print('  • ' .. issue)
    end

    print('\n💡 Recommended actions:')
    if not health.container_connected then
      print('  1. Start a container: :ContainerStart')
      print('  2. Open a devcontainer: :ContainerOpen')
    end

    if not health.lspconfig_available then
      print('  1. Install nvim-lspconfig plugin')
      print('  2. Check plugin configuration')
    end

    if health.servers_detected == 0 then
      print('  1. Install LSP servers in container')
      print('  2. Check devcontainer.json postCreateCommand')
      print('  3. Verify container PATH includes server binaries')
    end

    if health.clients_active == 0 and health.servers_detected > 0 then
      print('  1. Try LSP recovery: :ContainerLspRecover')
      print('  2. Check logs: :ContainerLogs')
      print('  3. Restart container: :ContainerRestart')
    end

    print('\n🔧 Advanced troubleshooting:')
    print('  • Detailed status: :ContainerLspStatus')
    print('  • Debug info: :ContainerDebug')
    print('  • Retry specific server: :ContainerLspRetry <server_name>')
  else
    print('\n✅ No issues found - LSP system is healthy')
    print('\nNext steps:')
    print('  • View detailed status: :ContainerLspStatus')
    print('  • Open a file to test LSP features')
  end

  return #health.issues == 0
end

-- Recover LSP servers
function M.recover_lsp()
  if not lsp then
    lsp = require('container.lsp')
  end

  notify.status('Starting LSP recovery process...')
  lsp.recover_all_lsp_servers()

  return true
end

-- Retry specific LSP server setup
function M.retry_lsp_server(server_name)
  if not lsp then
    lsp = require('container.lsp')
  end

  if not server_name then
    print('✗ Server name required')
    return false
  end

  notify.status('Retrying LSP server setup: ' .. server_name)
  lsp.retry_lsp_server_setup(server_name, 3)

  return true
end

-- Graceful degradation for container feature setup
function M._setup_container_features_gracefully(container_id)
  local features_status = {
    post_create_command = 'pending',
    lsp_setup = 'pending',
    test_integration = 'pending',
    post_start_command = 'pending',
  }

  local function update_status(feature, status, message)
    features_status[feature] = status
    if status == 'success' then
      print('✓ ' .. feature .. ': ' .. (message or 'completed'))
    elseif status == 'warning' then
      print('⚠ ' .. feature .. ': ' .. (message or 'completed with warnings'))
    elseif status == 'failed' then
      print('✗ ' .. feature .. ': ' .. (message or 'failed'))
    end
  end

  local function check_completion()
    local completed = 0
    local total = 0
    local warnings = 0
    local errors = 0

    for feature, status in pairs(features_status) do
      total = total + 1
      if status ~= 'pending' then
        completed = completed + 1
        if status == 'warning' then
          warnings = warnings + 1
        elseif status == 'failed' then
          errors = errors + 1
        end
      end
    end

    if completed == total then
      print('=== Container Setup Complete ===')
      if errors > 0 then
        print(
          string.format('Status: %d succeeded, %d warnings, %d errors', total - warnings - errors, warnings, errors)
        )
        print('Container is partially functional. Some features may not work.')
      elseif warnings > 0 then
        print(string.format('Status: %d succeeded, %d warnings', total - warnings, warnings))
        print('Container is functional with minor issues.')
      else
        print('Status: All features configured successfully!')
        print('Container is fully operational.')
      end
    end
  end

  -- 1. Execute postCreateCommand
  print('Setting up container features...')
  if state.current_config.post_create_command then
    print('Step 4.5: Running postCreateCommand...')
    M._run_post_create_command(container_id, function(success)
      if success then
        update_status('post_create_command', 'success', 'postCreateCommand completed')
      else
        update_status('post_create_command', 'warning', 'postCreateCommand failed but continuing')
      end
      check_completion()
    end)
  else
    update_status('post_create_command', 'success', 'no postCreateCommand defined')
    check_completion()
  end

  -- 2. Setup LSP integration with error handling
  if config.get_value('lsp.auto_setup') then
    print('Step 5: Setting up LSP...')
    local lsp_success = pcall(function()
      lsp = lsp or require('container.lsp.init')
      lsp.setup(config.get_value('lsp'))
      lsp.set_container_id(container_id)

      -- Configure path mapping with error handling
      local path_ok, lsp_path = pcall(require, 'container.lsp.path')
      if path_ok then
        lsp_path.setup(
          vim.fn.getcwd(),
          state.current_config.workspace_mount or '/workspace',
          state.current_config.mounts or {}
        )
      else
        log.warn('Failed to load LSP path module: %s', lsp_path)
      end

      -- Setup LSP servers with error handling
      vim.defer_fn(function()
        local setup_ok, setup_err = pcall(function()
          lsp.setup_lsp_in_container()
        end)

        if setup_ok then
          update_status('lsp_setup', 'success', 'LSP servers configured')
        else
          log.error('LSP setup failed: %s', setup_err)
          update_status('lsp_setup', 'warning', 'LSP setup failed: ' .. tostring(setup_err))
        end
        check_completion()
      end, 500)
    end)

    if not lsp_success then
      update_status('lsp_setup', 'failed', 'LSP module failed to load')
      check_completion()
    end
  else
    update_status('lsp_setup', 'success', 'LSP auto-setup disabled')
    check_completion()
  end

  -- 3. Setup test integration with error handling
  local test_config = config.get()
  if
    test_config.test_integration
    and test_config.test_integration.enabled
    and test_config.test_integration.auto_setup
  then
    vim.defer_fn(function()
      local test_ok, test_err = pcall(function()
        local test_runner = require('container.test_runner')
        return test_runner.setup()
      end)

      if test_ok and test_err then
        update_status('test_integration', 'success', 'test plugins integrated')
      elseif test_ok then
        update_status('test_integration', 'warning', 'test integration partially configured')
      else
        update_status('test_integration', 'failed', 'test integration failed: ' .. tostring(test_err))
      end
      check_completion()
    end, 700)
  else
    update_status('test_integration', 'success', 'test integration disabled')
    check_completion()
  end

  -- 4. Execute post-start command with error handling
  if state.current_config.post_start_command then
    print('Step 6: Running post-start command...')
    vim.defer_fn(function()
      local exec_ok, exec_err = pcall(function()
        M.exec(state.current_config.post_start_command, {
          on_complete = function(result)
            if result.success then
              update_status('post_start_command', 'success', 'post-start command completed')
            else
              update_status('post_start_command', 'warning', 'post-start command failed')
            end
            check_completion()
          end,
        })
      end)

      if not exec_ok then
        update_status('post_start_command', 'failed', 'post-start command error: ' .. tostring(exec_err))
        check_completion()
      end
    end, 1000)
  else
    update_status('post_start_command', 'success', 'no post-start command defined')
    check_completion()
  end
end

-- DAP integration API

-- Start debugging in container
function M.dap_start(opts)
  if not state.initialized then
    log.error('Plugin not initialized. Call setup() first.')
    return false
  end

  if not state.current_container then
    log.error('No active container')
    return false
  end

  local dap = require('container.dap')
  return dap.start_debugging(opts)
end

-- Stop debugging
function M.dap_stop()
  local dap = require('container.dap')
  return dap.stop_debugging()
end

-- Get DAP status
function M.dap_status()
  local dap = require('container.dap')
  return dap.get_debug_status()
end

-- List debug sessions
function M.dap_list_sessions()
  local dap = require('container.dap')
  return dap.list_debug_sessions()
end

return M
