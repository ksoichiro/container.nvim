-- lua/devcontainer/docker/init.lua
-- Docker operations abstraction (fixed version)

local M = {}
local log = require('container.utils.log')

-- Shell detection cache to avoid repeated checks
local shell_cache = {}

-- Detect available shell in container
local function detect_shell(container_id)
  if shell_cache[container_id] then
    return shell_cache[container_id]
  end

  -- Check if container is running first
  local status_cmd = string.format('docker inspect -f "{{.State.Status}}" %s 2>/dev/null', container_id)
  local status_result = vim.fn.system(status_cmd)
  if vim.v.shell_error ~= 0 or not status_result:match('running') then
    log.debug('Container %s not running, using default shell: sh', container_id)
    return 'sh'
  end

  local shells = { 'bash', 'zsh', 'sh' }

  for _, shell in ipairs(shells) do
    local cmd = string.format('docker exec %s which %s 2>/dev/null', container_id, shell)
    local result = vim.fn.system(cmd)
    if vim.v.shell_error == 0 and result:match(shell) then
      log.debug('Detected shell in container %s: %s', container_id, shell)
      shell_cache[container_id] = shell
      return shell
    end
  end

  -- Fallback to sh (should be available in all POSIX systems)
  log.warn('No preferred shell found in container %s, using fallback: sh', container_id)
  shell_cache[container_id] = 'sh'
  return 'sh'
end

-- Public shell detection function
function M.detect_shell(container_id)
  return detect_shell(container_id)
end

-- Clear shell cache for container (useful when container restarts)
function M.clear_shell_cache(container_id)
  if container_id then
    shell_cache[container_id] = nil
    log.debug('Cleared shell cache for container: %s', container_id)
  else
    shell_cache = {}
    log.debug('Cleared all shell cache')
  end
end

-- Docker command availability check (sync version)
function M.check_docker_availability()
  log.debug('Checking Docker availability (sync)')

  local _ = vim.fn.system('docker --version 2>/dev/null')
  local exit_code = vim.v.shell_error

  if exit_code ~= 0 then
    log.error('Docker is not available')
    local error_msg = M._build_docker_not_found_error()
    return false, error_msg
  end

  -- Check Docker daemon operation
  _ = vim.fn.system('docker info 2>/dev/null')
  exit_code = vim.v.shell_error

  if exit_code ~= 0 then
    log.error('Docker daemon is not running')
    local error_msg = M._build_docker_daemon_error()
    return false, error_msg
  end

  log.info('Docker is available and running')
  return true
end

-- Docker command availability check (async version)
-- Helper function to detect headless mode
local function is_headless_mode()
  -- Check if we're in headless mode where jobstart callbacks may not work
  return vim.v.servername == '' or vim.fn.argc() == 0
end

-- Helper function to run jobstart with proper event loop handling in headless mode
local function run_job_with_wait(cmd_args, job_opts, timeout_ms)
  timeout_ms = timeout_ms or 30000 -- 30 second default timeout

  if not is_headless_mode() then
    -- Normal mode: just use jobstart as usual
    return vim.fn.jobstart(cmd_args, job_opts)
  end

  -- Headless mode: use vim.wait() to ensure event loop processes callbacks
  log.debug('Headless mode: Using vim.wait() for jobstart event loop processing')

  local job_completed = false

  -- Wrap the original callbacks to track completion
  local original_on_exit = job_opts.on_exit
  job_opts.on_exit = function(job_id, exit_code, event)
    job_completed = true
    if original_on_exit then
      original_on_exit(job_id, exit_code, event)
    end
  end

  -- Start the job
  local job_id = vim.fn.jobstart(cmd_args, job_opts)

  if job_id <= 0 then
    return job_id -- Return error immediately
  end

  -- Use vim.wait() to process the event loop until job completes
  local wait_result = vim.wait(timeout_ms, function()
    return job_completed
  end, 100) -- Check every 100ms

  if not wait_result then
    log.warn('Job timed out after %dms in headless mode', timeout_ms)
    -- Try to stop the job
    vim.fn.jobstop(job_id)
  end

  return job_id
end

function M.check_docker_availability_async(callback)
  log.debug('Checking Docker availability (async)')

  -- Docker version check
  local version_job_opts = {
    on_exit = function(_, exit_code, _)
      if exit_code ~= 0 then
        log.error('Docker is not available')
        local error_msg = M._build_docker_not_found_error()
        callback(false, error_msg)
        return
      end

      -- Docker daemon check
      local daemon_job_opts = {
        on_exit = function(_, daemon_exit_code, _)
          if daemon_exit_code ~= 0 then
            log.error('Docker daemon is not running')
            local error_msg = M._build_docker_daemon_error()
            callback(false, error_msg)
          else
            log.info('Docker is available and running')
            callback(true)
          end
        end,
        stdout_buffered = true,
        stderr_buffered = true,
      }

      run_job_with_wait({ 'docker', 'info' }, daemon_job_opts, 15000)
    end,
    stdout_buffered = true,
    stderr_buffered = true,
  }

  run_job_with_wait({ 'docker', '--version' }, version_job_opts, 10000)
end

-- Execute command synchronously
-- Synchronous Docker command execution (kept for compatibility)
function M.run_docker_command(args, opts)
  opts = opts or {}

  -- Properly escape arguments for shell
  local escaped_args = {}
  for _, arg in ipairs(args) do
    table.insert(escaped_args, vim.fn.shellescape(arg))
  end
  local cmd = 'docker ' .. table.concat(escaped_args, ' ')

  if opts.cwd then
    cmd = 'cd ' .. vim.fn.shellescape(opts.cwd) .. ' && ' .. cmd
  end

  -- Determine if this is a lightweight status check command
  local is_lightweight_command = false
  if #args > 0 then
    local first_arg = args[1]
    -- Commands that are frequently called for status checks
    if first_arg == 'inspect' or first_arg == 'images' or first_arg == 'ps' then
      is_lightweight_command = true
    end
  end

  -- Only log important commands, suppress frequent status checks
  if not is_lightweight_command or (opts and opts.verbose) then
    log.debug('Executing (sync): %s', cmd)
  end

  local stdout = vim.fn.system(cmd)
  local exit_code = vim.v.shell_error

  return {
    success = exit_code == 0,
    code = exit_code,
    stdout = stdout or '',
    stderr = exit_code ~= 0 and stdout or '',
  }
end

-- Asynchronous Docker command execution
function M.run_docker_command_async(args, opts, callback)
  opts = opts or {}

  local cmd_args = { 'docker' }
  for _, arg in ipairs(args) do
    table.insert(cmd_args, arg)
  end

  -- Determine if this is a lightweight status check command
  local is_lightweight_command = false
  if #args > 0 then
    local first_arg = args[1]
    -- Commands that are frequently called for status checks
    if first_arg == 'inspect' or first_arg == 'images' or first_arg == 'ps' then
      is_lightweight_command = true
    end
  end

  -- Only log important commands, suppress frequent status checks
  if not is_lightweight_command or (opts and opts.verbose) then
    log.debug('Executing (async): %s', table.concat(cmd_args, ' '))
  end

  local stdout_lines = {}
  local stderr_lines = {}

  local job_opts = {
    on_stdout = function(_, data, _)
      if data then
        for _, line in ipairs(data) do
          if line ~= '' then
            table.insert(stdout_lines, line)
          end
        end
      end
    end,
    on_stderr = function(_, data, _)
      if data then
        for _, line in ipairs(data) do
          if line ~= '' then
            table.insert(stderr_lines, line)
          end
        end
      end
    end,
    on_exit = function(_, exit_code, _)
      local result = {
        success = exit_code == 0,
        code = exit_code,
        stdout = table.concat(stdout_lines, '\n'),
        stderr = table.concat(stderr_lines, '\n'),
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

  -- Use the new helper function that handles headless mode properly
  local timeout_ms = (opts.timeout or 30) * 1000 -- Convert seconds to milliseconds
  return run_job_with_wait(cmd_args, job_opts, timeout_ms)
end

-- Check Docker image existence
function M.check_image_exists(image_name)
  log.debug('Checking if image exists: %s', image_name)

  local result = M.run_docker_command({ 'images', '-q', image_name })

  if result.success then
    local image_id = result.stdout:gsub('%s+', '')
    return image_id ~= ''
  else
    log.error('Failed to check image existence: %s', result.stderr or 'unknown error')
    return false
  end
end

-- Check Docker image existence (async version)
function M.check_image_exists_async(image_name, callback)
  log.debug('Checking if image exists (async): %s', image_name)

  M.run_docker_command_async({ 'images', '-q', image_name }, {}, function(result)
    if result.success then
      local image_id = result.stdout:gsub('%s+', '')
      callback(image_id ~= '', image_id)
    else
      log.error('Failed to check image existence: %s', result.stderr or 'unknown error')
      callback(false, nil)
    end
  end)
end

-- Docker image pull with retry mechanism
function M.pull_image_async(image_name, on_progress, on_complete, retry_count)
  retry_count = retry_count or 0
  local max_retries = 2

  log.info('Pulling Docker image (async): %s (attempt %d/%d)', image_name, retry_count + 1, max_retries + 1)

  -- Debug information immediately after start
  if on_progress then
    on_progress('Starting image pull...')
    on_progress('   Command: docker pull ' .. image_name)
  end

  local stdout_lines = {}
  local stderr_lines = {}
  local start_time = vim.loop.hrtime()
  local data_received = false

  log.debug('About to start docker pull job for: %s', image_name)

  local job_id = run_job_with_wait({ 'docker', 'pull', image_name }, {
    on_stdout = function(job_id, data, event)
      log.debug('Docker pull stdout callback triggered (job: %d, event: %s)', job_id, event)
      data_received = true

      if data then
        log.debug('Docker pull stdout data length: %d', #data)
        for i, line in ipairs(data) do
          log.debug("Docker pull stdout[%d]: '%s'", i, line or '<nil>')
          if line and line ~= '' then
            table.insert(stdout_lines, line)
            if on_progress then
              local progress_line = '   [stdout] ' .. line
              on_progress(progress_line)

              -- Special handling for common docker pull messages
              if
                line:match('Pulling')
                or line:match('Downloading')
                or line:match('Extracting')
                or line:match('Pull complete')
              then
                log.info('Docker pull progress: %s', line)
              end
            end
          end
        end
      else
        log.debug('Docker pull stdout: data is nil')
      end
    end,

    on_stderr = function(job_id, data, event)
      log.debug('Docker pull stderr callback triggered (job: %d, event: %s)', job_id, event)
      data_received = true

      if data then
        log.debug('Docker pull stderr data length: %d', #data)
        for i, line in ipairs(data) do
          log.debug("Docker pull stderr[%d]: '%s'", i, line or '<nil>')
          if line and line ~= '' then
            table.insert(stderr_lines, line)
            if on_progress then
              local progress_line = '   [stderr] ' .. line
              on_progress(progress_line)
            end
          end
        end
      else
        log.debug('Docker pull stderr: data is nil')
      end
    end,

    on_exit = function(job_id, exit_code, event)
      local end_time = vim.loop.hrtime()
      local duration = (end_time - start_time) / 1e9 -- seconds

      log.debug(
        'Docker pull exit callback (job: %d, exit_code: %d, event: %s, duration: %.1fs)',
        job_id,
        exit_code,
        event,
        duration
      )
      log.debug('Data received during job: %s', tostring(data_received))
      log.debug('Total stdout lines: %d', #stdout_lines)
      log.debug('Total stderr lines: %d', #stderr_lines)

      local result = {
        success = exit_code == 0,
        code = exit_code,
        stdout = table.concat(stdout_lines, '\n'),
        stderr = table.concat(stderr_lines, '\n'),
        duration = duration,
        data_received = data_received,
      }

      if exit_code == 0 then
        log.info('Successfully pulled Docker image: %s (%.1fs)', image_name, duration)
        if on_progress then
          on_progress(string.format('✓ Image pull completed (%.1fs)', duration))
        end
      else
        log.error('Failed to pull Docker image: %s (exit code: %d)', image_name, exit_code)
        local error_msg = M.handle_network_error(table.concat(stderr_lines, '\n'))
        if on_progress then
          on_progress('✗ Image pull failed (exit code: ' .. exit_code .. ')')
          on_progress('Network error details:')
          for line in error_msg:gmatch('[^\n]+') do
            on_progress('  ' .. line)
          end
        end
      end

      if on_complete then
        vim.schedule(function()
          -- Retry logic for network failures
          if not result.success and retry_count < max_retries then
            -- Check if error is potentially retryable (network-related)
            local stderr_output = table.concat(stderr_lines, '\n'):lower()
            local is_retryable = stderr_output:match('timeout')
              or stderr_output:match('network')
              or stderr_output:match('connection')
              or stderr_output:match('temporary failure')
              or exit_code == 124 -- timeout exit code

            if is_retryable then
              local wait_time = (retry_count + 1) * 2000 -- 2s, 4s, 6s
              log.info('Retrying image pull in %d seconds...', wait_time / 1000)
              if on_progress then
                on_progress(
                  string.format(
                    'Retrying in %d seconds... (attempt %d/%d)',
                    wait_time / 1000,
                    retry_count + 2,
                    max_retries + 1
                  )
                )
              end

              vim.defer_fn(function()
                M.pull_image_async(image_name, on_progress, on_complete, retry_count + 1)
              end, wait_time)
              return
            end
          end

          on_complete(result.success, result)
        end)
      end
    end,

    -- Try without buffering to see if that helps
    stdout_buffered = false,
    stderr_buffered = false,
  }, 300000) -- 5 minute timeout for image pulls

  log.debug('jobstart returned job_id: %s', tostring(job_id))

  if job_id == 0 then
    log.error('Failed to start docker pull job (jobstart returned 0)')
    if on_progress then
      on_progress('✗ Failed to start docker pull job')
    end
    if on_complete then
      vim.schedule(function()
        on_complete(false, { error = 'Failed to start docker pull job' })
      end)
    end
    return nil
  elseif job_id == -1 then
    log.error('Invalid arguments for docker pull job')
    if on_progress then
      on_progress('✗ Invalid arguments for docker pull job')
    end
    if on_complete then
      vim.schedule(function()
        on_complete(false, { error = 'Invalid arguments for docker pull job' })
      end)
    end
    return nil
  end

  log.info('Started docker pull job with ID: %d', job_id)

  if on_progress then
    on_progress('   Pull job started (ID: ' .. job_id .. ')')
    on_progress('   Waiting for Docker output...')
  end

  -- Add progress check with configurable timeout
  local progress_check_count = 0
  local timeout_seconds = 600 -- 10 minutes default, make this configurable

  local function check_progress()
    progress_check_count = progress_check_count + 1
    local elapsed = (vim.loop.hrtime() - start_time) / 1e9

    -- Check if job is still running
    local job_status = vim.fn.jobwait({ job_id }, 0)[1]

    if job_status == -1 then -- Still running
      log.debug(
        'Progress check #%d: job still running (%.1fs elapsed, data_received: %s)',
        progress_check_count,
        elapsed,
        tostring(data_received)
      )

      if on_progress then
        on_progress(string.format('   [%.0fs] Pull in progress... (check #%d)', elapsed, progress_check_count))

        if not data_received and elapsed > 30 then
          on_progress('   Warning: No data received from Docker yet. This might indicate a network problem.')
        end

        -- Show timeout countdown
        if elapsed > timeout_seconds - 60 then -- Last minute warning
          local remaining = timeout_seconds - elapsed
          on_progress(string.format('   ⚠ Timeout in %.0f seconds', remaining))
        end
      end

      -- Configurable timeout
      if elapsed < timeout_seconds then
        vim.defer_fn(check_progress, 10000) -- Check every 10 seconds
      else
        log.warn('Docker pull timeout after %d seconds, stopping job: %d', timeout_seconds, job_id)
        vim.fn.jobstop(job_id)
        if on_progress then
          on_progress(string.format('⚠ Image pull timed out (%d minutes)', timeout_seconds / 60))
          on_progress('This may be due to:')
          on_progress('  • Slow internet connection')
          on_progress('  • Large image size')
          on_progress('  • Docker registry issues')
          on_progress('  • Network configuration problems')
        end
        if on_complete then
          vim.schedule(function()
            on_complete(false, {
              error = 'Timeout',
              duration = elapsed,
              timeout_seconds = timeout_seconds,
            })
          end)
        end
      end
    else
      log.debug('Progress check #%d: job finished with code %d', progress_check_count, job_status)
    end
  end

  -- Start first progress check after 5 seconds
  vim.defer_fn(check_progress, 5000)

  return job_id
end

-- Docker image pull (old version, kept for compatibility)
function M.pull_image(image_name, on_progress, on_complete)
  log.info('Pulling Docker image: %s', image_name)

  -- Simulate asynchronous processing
  vim.defer_fn(function()
    local result = M.run_docker_command({ 'pull', image_name })

    if result.success then
      log.info('Successfully pulled Docker image: %s', image_name)
    else
      log.error('Failed to pull Docker image: %s', result.stderr)
    end

    if on_complete then
      vim.schedule(function()
        on_complete(result.success, result)
      end)
    end
  end, 100)
end

-- Docker image build
function M.build_image(config, on_progress, on_complete)
  log.info('Building Docker image: %s', config.name)

  vim.defer_fn(function()
    local args = { 'build' }

    -- Set tag
    local tag = config.name:lower():gsub('[^a-z0-9_.-]', '-')
    table.insert(args, '-t')
    table.insert(args, tag)

    -- Build arguments
    if config.build_args then
      for key, value in pairs(config.build_args) do
        table.insert(args, '--build-arg')
        table.insert(args, string.format('%s=%s', key, value))
      end
    end

    -- Specify Dockerfile
    if config.dockerfile then
      table.insert(args, '-f')
      table.insert(args, config.dockerfile)
    end

    -- Build context
    local context = config.context or '.'
    table.insert(args, context)

    local result = M.run_docker_command(args, { cwd = config.base_path })

    if result.success then
      log.info('Successfully built Docker image: %s', tag)
      config.built_image = tag
    else
      log.error('Failed to build Docker image: %s', result.stderr)
    end

    if on_complete then
      vim.schedule(function()
        on_complete(result.success, result)
      end)
    end
  end, 100)
end

-- Prepare image (build or pull)
function M.prepare_image(config, on_progress, on_complete)
  -- Build if Dockerfile is specified
  if config.dockerfile then
    return M.build_image(config, on_progress, on_complete)
  end

  -- If image is specified
  if config.image then
    -- Check if image exists locally
    local exists = M.check_image_exists(config.image)

    if exists then
      log.info('Image already exists locally: %s', config.image)
      config.prepared_image = config.image
      if on_complete then
        vim.schedule(function()
          on_complete(true, { success = true, stdout = '', stderr = '' })
        end)
      end
      return
    else
      -- Pull if image doesn't exist
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

  -- If neither Dockerfile nor Image is specified
  local error_msg = 'No dockerfile or image specified'
  log.error(error_msg)
  if on_complete then
    vim.schedule(function()
      on_complete(false, { success = false, stderr = error_msg })
    end)
  end
end

-- Container creation
-- Container creation (async version)
function M.create_container_async(config, callback)
  log.info('Creating Docker container (async): %s', config.name)

  local args = M._build_create_args(config)

  M.run_docker_command_async(args, {}, function(result)
    if result.success then
      local container_id = result.stdout:gsub('%s+', '')
      log.info('Successfully created container: %s', container_id)
      callback(container_id, nil)
    else
      local error_parts = {}
      if result.stderr and result.stderr ~= '' then
        table.insert(error_parts, 'Error output: ' .. result.stderr)
      end
      if result.code then
        table.insert(error_parts, 'Exit code: ' .. tostring(result.code))
      end

      local error_msg = 'Docker create command failed'
      if #error_parts > 0 then
        error_msg = error_msg .. ' | ' .. table.concat(error_parts, ' | ')
      end

      log.error('Failed to create container: %s', error_msg)
      callback(nil, error_msg)
    end
  end)
end

-- Generate unique container name with project path hash
function M.generate_container_name(config)
  -- Get project root path for uniqueness
  local project_path = config.base_path or vim.fn.getcwd()

  -- Create hash of project path for uniqueness
  local path_hash = vim.fn.sha256(project_path):sub(1, 8)

  -- Clean the config name
  local clean_name = config.name:lower():gsub('[^a-z0-9_.-]', '-')

  -- Combine name, hash, and suffix for uniqueness
  local container_name = string.format('%s-%s-devcontainer', clean_name, path_hash)

  log.debug('Generated container name: %s (from project: %s)', container_name, project_path)
  return container_name
end

-- Build container creation arguments
function M._build_create_args(config)
  local args = { 'create' }

  -- Container name (unique per project)
  local container_name = M.generate_container_name(config)
  table.insert(args, '--name')
  table.insert(args, container_name)

  -- Interactive mode
  table.insert(args, '-it')

  -- Work directory
  if config.workspace_folder then
    table.insert(args, '-w')
    table.insert(args, config.workspace_folder)
  end

  -- Environment variables
  if config.environment then
    for key, value in pairs(config.environment) do
      table.insert(args, '-e')
      table.insert(args, string.format('%s=%s', key, value))
    end
  end

  -- Volume mount
  if config.mounts then
    for _, mount in ipairs(config.mounts) do
      table.insert(args, '--mount')
      local mount_str = string.format('type=%s,source=%s,target=%s', mount.type, mount.source, mount.target)
      if mount.readonly then
        mount_str = mount_str .. ',readonly'
      end
      if mount.consistency then
        mount_str = mount_str .. ',consistency=' .. mount.consistency
      end
      table.insert(args, mount_str)
    end
  end

  -- Port forwarding
  if config.ports then
    for _, port in ipairs(config.ports) do
      table.insert(args, '-p')
      table.insert(args, string.format('%d:%d', port.host_port, port.container_port))
    end
  end

  -- Privileged mode
  if config.privileged then
    table.insert(args, '--privileged')
  end

  -- init process
  if config.init then
    table.insert(args, '--init')
  end

  -- User specification
  if config.remote_user then
    table.insert(args, '--user')
    table.insert(args, config.remote_user)
  end

  -- Workspace mount (default)
  local workspace_source = config.workspace_source or vim.fn.getcwd()
  local workspace_target = config.workspace_mount or '/workspace'
  table.insert(args, '-v')
  table.insert(args, workspace_source .. ':' .. workspace_target)

  -- Image
  table.insert(args, config.image)

  return args
end

-- Container creation (sync version, kept for compatibility)
function M.create_container(config)
  log.info('Creating Docker container: %s', config.name)

  local args = { 'create' }

  -- Container name (unique per project)
  local container_name = M.generate_container_name(config)
  table.insert(args, '--name')
  table.insert(args, container_name)

  -- Interactive mode
  table.insert(args, '-it')

  -- Work directory
  if config.workspace_folder then
    table.insert(args, '-w')
    table.insert(args, config.workspace_folder)
  end

  -- Environment variables
  if config.environment then
    for key, value in pairs(config.environment) do
      table.insert(args, '-e')
      table.insert(args, string.format('%s=%s', key, value))
    end
  end

  -- Volume mount
  if config.mounts then
    for _, mount in ipairs(config.mounts) do
      table.insert(args, '--mount')
      local mount_str = string.format('type=%s,source=%s,target=%s', mount.type, mount.source, mount.target)
      if mount.readonly then
        mount_str = mount_str .. ',readonly'
      end
      if mount.consistency then
        mount_str = mount_str .. ',consistency=' .. mount.consistency
      end
      table.insert(args, mount_str)
    end
  end

  -- Port forwarding
  if config.ports then
    for _, port in ipairs(config.ports) do
      table.insert(args, '-p')
      table.insert(args, string.format('%d:%d', port.host_port, port.container_port))
    end
  end

  -- Privileged mode
  if config.privileged then
    table.insert(args, '--privileged')
  end

  -- init process
  if config.init then
    table.insert(args, '--init')
  end

  -- User specification
  if config.remote_user then
    table.insert(args, '--user')
    table.insert(args, config.remote_user)
  end

  -- Image to use (built image or specified image)
  local image = config.built_image or config.prepared_image or config.image
  if not image then
    local error_msg = 'No image available for container creation'
    log.error(error_msg)
    return nil, error_msg
  end
  -- Override any bash-dependent entrypoint from base image
  table.insert(args, '--entrypoint')
  table.insert(args, 'sh')

  table.insert(args, image)

  -- Default command (keep container running with POSIX sh)
  table.insert(args, '-c')
  table.insert(args, 'while true; do sleep 3600; done')

  log.info('Docker create command: docker %s', table.concat(args, ' '))
  log.debug('Using POSIX sh entrypoint to avoid bash dependency')

  local result = M.run_docker_command(args)

  if result.success then
    local container_id = result.stdout:gsub('%s+', '')
    if container_id == '' then
      local error_msg = 'Docker create command succeeded but returned empty container ID'
      log.error(error_msg)
      return nil, error_msg
    end
    log.info('Successfully created container: %s (%s)', container_name, container_id)
    return container_id
  else
    -- Build detailed error information
    local error_parts = {}

    -- Basic error information
    table.insert(error_parts, 'Docker create command failed')

    -- Exit code
    if result.code then
      table.insert(error_parts, string.format('Exit code: %d', result.code))
    end

    -- stderr output
    if result.stderr and result.stderr ~= '' then
      table.insert(error_parts, string.format('Error output: %s', result.stderr:gsub('%s+$', '')))
    end

    -- stdout output (may contain error information)
    if result.stdout and result.stdout ~= '' then
      table.insert(error_parts, string.format('Standard output: %s', result.stdout:gsub('%s+$', '')))
    end

    -- Executed command
    table.insert(error_parts, string.format('Command: docker %s', table.concat(args, ' ')))

    local error_msg = table.concat(error_parts, ' | ')
    log.error('Failed to create container: %s', error_msg)
    return nil, error_msg
  end
end

-- Container startup (async version)
function M.start_container(container_id, on_ready)
  log.info('Starting container: %s', container_id)

  vim.defer_fn(function()
    local result = M.run_docker_command({ 'start', container_id })

    if result.success then
      log.info('Successfully started container: %s', container_id)

      -- Wait for container to be ready
      M.wait_for_container_ready(container_id, function(ready)
        if on_ready then
          vim.schedule(function()
            on_ready(ready)
          end)
        end
      end)
    else
      local error_msg = result.stderr or 'unknown error'
      log.error('Failed to start container: %s', error_msg)
      if on_ready then
        vim.schedule(function()
          on_ready(false)
        end)
      end
    end
  end, 100)
end

-- Container startup (improved version - non-blocking)
function M.start_container_async(container_id, callback)
  log.info('Starting container asynchronously: %s', container_id)

  -- Start container
  local result = M.run_docker_command({ 'start', container_id })
  if not result.success then
    local error_msg = result.stderr or 'unknown error'
    log.error('Failed to start container: %s', error_msg)
    callback(false, error_msg)
    return
  end

  log.info('Container started, checking readiness...')

  -- Wait for readiness non-blocking
  local attempts = 0
  local max_attempts = 30

  local function check_ready()
    attempts = attempts + 1

    local status = M.get_container_status(container_id)
    if status == 'running' then
      -- Check with simple command
      local test_result = M.run_docker_command({ 'exec', container_id, 'echo', 'ready' })
      if test_result.success then
        log.info('Container is ready: %s', container_id)
        callback(true)
        return
      end
    end

    if attempts < max_attempts then
      -- Retry after 1 second (non-blocking)
      vim.defer_fn(check_ready, 1000)
    else
      log.warn('Container readiness check timed out: %s', container_id)
      callback(false, 'timeout')
    end
  end

  -- Start first check
  vim.defer_fn(check_ready, 500)
end

-- Simple container startup test
function M.start_container_simple(container_id)
  log.info('Starting container (simple): %s', container_id)

  -- Start container
  local result = M.run_docker_command({ 'start', container_id })
  if not result.success then
    local error_msg = result.stderr or 'unknown error'
    log.error('Failed to start container: %s', error_msg)
    return false, error_msg
  end

  log.info('Container start command completed: %s', container_id)

  -- Status check (once only)
  local status = M.get_container_status(container_id)
  return status == 'running', status
end

-- Container stop (synchronous version - kept for compatibility)
function M.stop_container(container_id, timeout)
  timeout = timeout or 30
  log.info('Stopping container: %s', container_id)

  local args = { 'stop' }
  if timeout then
    table.insert(args, '-t')
    table.insert(args, tostring(timeout))
  end
  table.insert(args, container_id)

  vim.defer_fn(function()
    local result = M.run_docker_command(args)

    if result.success then
      log.info('Successfully stopped container: %s', container_id)
    else
      log.error('Failed to stop container: %s', result.stderr)
    end
  end, 100)
end

-- Container stop (async version)
function M.stop_container_async(container_id, callback, timeout)
  timeout = timeout or 30
  log.info('Stopping container: %s', container_id)

  local args = { 'stop' }
  if timeout then
    table.insert(args, '-t')
    table.insert(args, tostring(timeout))
  end
  table.insert(args, container_id)

  M.run_docker_command_async(args, {}, function(result)
    if result.success then
      log.info('Successfully stopped container: %s', container_id)
      if callback then
        callback(true)
      end
    else
      log.error('Failed to stop container: %s', result.stderr)
      if callback then
        callback(false, result.stderr)
      end
    end
  end)
end

-- Container kill (immediate termination)
function M.kill_container(container_id, callback)
  log.info('Killing container: %s', container_id)

  local args = { 'kill', container_id }

  M.run_docker_command_async(args, {}, function(result)
    if result.success then
      log.info('Successfully killed container: %s', container_id)
      if callback then
        vim.schedule(function()
          callback(true, nil)
        end)
      end
    else
      local error_msg = result.stderr or 'unknown error'
      log.error('Failed to kill container: %s', error_msg)
      if callback then
        vim.schedule(function()
          callback(false, error_msg)
        end)
      end
    end
  end)
end

-- Container terminate (alias for kill with additional cleanup)
function M.terminate_container(container_id, callback)
  log.info('Terminating container: %s', container_id)

  -- First try to kill the container
  M.kill_container(container_id, function(success, error_msg)
    if success then
      log.info('Container terminated successfully: %s', container_id)
      if callback then
        callback(true, nil)
      end
    else
      log.error('Failed to terminate container: %s', error_msg or 'unknown error')
      if callback then
        callback(false, error_msg)
      end
    end
  end)
end

-- Container removal (sync version, kept for compatibility)
function M.remove_container(container_id, force)
  log.info('Removing container: %s', container_id)

  local args = { 'rm' }
  if force then
    table.insert(args, '-f')
  end
  table.insert(args, container_id)

  vim.defer_fn(function()
    local result = M.run_docker_command(args)

    if result.success then
      log.info('Successfully removed container: %s', container_id)
    else
      log.error('Failed to remove container: %s', result.stderr)
    end
  end, 100)
end

-- Container removal (async version)
function M.remove_container_async(container_id, force, callback)
  log.info('Removing container (async): %s', container_id)

  local args = { 'rm' }
  if force then
    table.insert(args, '-f')
  end
  table.insert(args, container_id)

  M.run_docker_command_async(args, {}, function(result)
    if result.success then
      log.info('Successfully removed container: %s', container_id)
      if callback then
        vim.schedule(function()
          callback(true, nil)
        end)
      end
    else
      local error_msg = result.stderr or 'unknown error'
      log.error('Failed to remove container: %s', error_msg)
      if callback then
        vim.schedule(function()
          callback(false, error_msg)
        end)
      end
    end
  end)
end

-- Stop and remove container (async)
function M.stop_and_remove_container(container_id, stop_timeout, callback)
  log.info('Stopping and removing container: %s', container_id)

  stop_timeout = stop_timeout or 30

  -- First stop the container
  local args = { 'stop' }
  if stop_timeout then
    table.insert(args, '-t')
    table.insert(args, tostring(stop_timeout))
  end
  table.insert(args, container_id)

  M.run_docker_command_async(args, {}, function(stop_result)
    if stop_result.success then
      log.info('Container stopped: %s', container_id)

      -- Then remove the container
      M.remove_container_async(container_id, false, function(remove_success, remove_error)
        if remove_success then
          log.info('Container stopped and removed: %s', container_id)
          if callback then
            callback(true, nil)
          end
        else
          log.error('Failed to remove container after stopping: %s', remove_error or 'unknown error')
          if callback then
            callback(false, remove_error)
          end
        end
      end)
    else
      -- If stop fails, try force removal
      log.warn('Failed to stop container, attempting force removal: %s', container_id)
      M.remove_container_async(container_id, true, function(force_remove_success, force_remove_error)
        if force_remove_success then
          log.info('Container force removed: %s', container_id)
          if callback then
            callback(true, nil)
          end
        else
          log.error('Failed to force remove container: %s', force_remove_error or 'unknown error')
          if callback then
            callback(false, force_remove_error)
          end
        end
      end)
    end
  end)
end

-- Execute command in container
function M.exec_command(container_id, command, opts)
  opts = opts or {}
  log.debug('Executing command in container %s: %s', container_id, command)

  local args = { 'exec' }

  -- Interactive mode
  if opts.interactive then
    table.insert(args, '-it')
  else
    table.insert(args, '-i')
  end

  -- Working directory
  if opts.workdir then
    table.insert(args, '-w')
    table.insert(args, opts.workdir)
  end

  -- User specification
  if opts.user then
    table.insert(args, '--user')
    table.insert(args, opts.user)
  end

  -- Environment variables
  if opts.env then
    for key, value in pairs(opts.env) do
      table.insert(args, '-e')
      table.insert(args, string.format('%s=%s', key, value))
    end
  end

  table.insert(args, container_id)

  -- Split command
  if type(command) == 'string' then
    -- Execute as shell command (properly escaped)
    local shell = opts.shell or detect_shell(container_id)
    table.insert(args, shell)
    table.insert(args, '-c')
    -- Pass entire command as single argument
    table.insert(args, string.format('%s', command))
  elseif type(command) == 'table' then
    -- Execute as command array
    for _, cmd_part in ipairs(command) do
      table.insert(args, cmd_part)
    end
  end

  -- Debug: Log command to be executed
  log.debug('Docker exec command: docker %s', table.concat(args, ' '))

  vim.defer_fn(function()
    local result = M.run_docker_command(args)

    -- Debug: Log result
    log.debug(
      'Docker exec result: success=%s, code=%s, stdout_len=%s, stderr_len=%s',
      tostring(result.success),
      tostring(result.code),
      tostring(result.stdout and #result.stdout or 0),
      tostring(result.stderr and #result.stderr or 0)
    )

    if opts.on_complete then
      opts.on_complete(result)
    end
  end, 100)
end

-- Execute command in container (async version with enhanced options)
function M.exec_command_async(container_id, command, opts, callback)
  opts = opts or {}
  log.debug('Executing command in container (async) %s: %s', container_id, vim.inspect(command))

  local args = { 'exec' }

  -- Interactive mode
  if opts.interactive then
    table.insert(args, '-it')
  else
    table.insert(args, '-i')
  end

  -- Working directory
  if opts.workdir then
    table.insert(args, '-w')
    table.insert(args, opts.workdir)
  end

  -- User specification
  if opts.user then
    table.insert(args, '--user')
    table.insert(args, opts.user)
  end

  -- Environment variables
  if opts.env then
    for key, value in pairs(opts.env) do
      table.insert(args, '-e')
      table.insert(args, string.format('%s=%s', key, value))
    end
  end

  -- Detached mode
  if opts.detach then
    table.insert(args, '-d')
  end

  -- TTY allocation
  if opts.tty then
    table.insert(args, '-t')
  end

  table.insert(args, container_id)

  -- Split command
  if type(command) == 'string' then
    -- Detect shell
    local shell = opts.shell or detect_shell(container_id)
    table.insert(args, shell)
    table.insert(args, '-c')
    table.insert(args, command)
  elseif type(command) == 'table' then
    -- Execute as command array
    for _, cmd_part in ipairs(command) do
      table.insert(args, cmd_part)
    end
  end

  -- Use async version
  M.run_docker_command_async(args, opts, function(result)
    if callback then
      vim.schedule(function()
        callback(result)
      end)
    end
  end)
end

-- General command execution API
function M.execute_command(container_id, command, opts)
  opts = opts or {}

  -- Determine execution mode
  local mode = opts.mode or 'sync' -- 'sync', 'async', 'fire_and_forget'

  -- Build options for exec_command
  local exec_opts = {
    interactive = opts.interactive or false,
    workdir = opts.workdir,
    user = opts.user,
    env = opts.env,
    detach = opts.detach or false,
    tty = opts.tty or false,
    shell = opts.shell or detect_shell(container_id),
    timeout = opts.timeout,
    cwd = opts.cwd, -- For run_docker_command compatibility
  }

  -- Handle different execution modes
  if mode == 'async' then
    -- Async execution with callback
    return M.exec_command_async(container_id, command, exec_opts, opts.callback)
  elseif mode == 'fire_and_forget' then
    -- Fire and forget (detached execution)
    exec_opts.detach = true
    return M.exec_command_async(container_id, command, exec_opts, function(result)
      if result.success then
        log.debug('Command launched in background: %s', vim.inspect(command))
      else
        log.error('Failed to launch background command: %s', result.stderr or 'unknown error')
      end
    end)
  else
    -- Sync execution (default)
    local result_container = {}
    local completed = false

    M.exec_command_async(container_id, command, exec_opts, function(result)
      result_container.result = result
      completed = true
    end)

    -- Wait for completion with timeout
    local timeout = opts.timeout or 30000 -- 30 seconds default
    local start_time = vim.loop.hrtime()

    while not completed do
      vim.wait(100) -- Wait 100ms
      local elapsed = (vim.loop.hrtime() - start_time) / 1e6 -- Convert to milliseconds
      if elapsed > timeout then
        log.error('Command execution timed out: %s', vim.inspect(command))
        return {
          success = false,
          code = -1,
          stdout = '',
          stderr = 'Command execution timed out',
          timeout = true,
        }
      end
    end

    return result_container.result
  end
end

-- Execute command with output streaming
function M.execute_command_stream(container_id, command, opts)
  opts = opts or {}
  log.debug('Executing command with streaming in container %s: %s', container_id, vim.inspect(command))

  -- In headless mode, fall back to non-streaming execution
  if is_headless_mode() then
    log.debug('Headless mode detected, using non-streaming command execution')
    local result = M.execute_command(container_id, command, opts)
    if opts.on_exit then
      vim.schedule(function()
        opts.on_exit(result.success and 0 or 1)
      end)
    end
    return 1 -- Return a dummy job ID for compatibility
  end

  local cmd_args = { 'docker', 'exec' }

  -- Interactive mode
  if opts.interactive then
    table.insert(cmd_args, '-it')
  else
    table.insert(cmd_args, '-i')
  end

  -- Working directory
  if opts.workdir then
    table.insert(cmd_args, '-w')
    table.insert(cmd_args, opts.workdir)
  end

  -- User specification
  if opts.user then
    table.insert(cmd_args, '--user')
    table.insert(cmd_args, opts.user)
  end

  -- Environment variables
  if opts.env then
    for key, value in pairs(opts.env) do
      table.insert(cmd_args, '-e')
      table.insert(cmd_args, string.format('%s=%s', key, value))
    end
  end

  table.insert(cmd_args, container_id)

  -- Split command
  if type(command) == 'string' then
    local shell = opts.shell or detect_shell(container_id)
    table.insert(cmd_args, shell)
    table.insert(cmd_args, '-c')
    table.insert(cmd_args, command)
  elseif type(command) == 'table' then
    for _, cmd_part in ipairs(command) do
      table.insert(cmd_args, cmd_part)
    end
  end

  -- Setup streaming callbacks
  local job_opts = {
    on_stdout = function(_, data, _)
      if data and opts.on_stdout then
        for _, line in ipairs(data) do
          if line ~= '' then
            opts.on_stdout(line)
          end
        end
      end
    end,
    on_stderr = function(_, data, _)
      if data and opts.on_stderr then
        for _, line in ipairs(data) do
          if line ~= '' then
            opts.on_stderr(line)
          end
        end
      end
    end,
    on_exit = function(_, exit_code, _)
      if opts.on_exit then
        opts.on_exit(exit_code)
      end
    end,
    stdout_buffered = false,
    stderr_buffered = false,
  }

  if opts.cwd then
    job_opts.cwd = opts.cwd
  end

  -- Start job and return job ID for control
  local timeout_ms = (opts.timeout or 60) * 1000 -- Default 60 second timeout
  local job_id = run_job_with_wait(cmd_args, job_opts, timeout_ms)

  if job_id == 0 then
    log.error('Failed to start command stream job')
    if opts.on_exit then
      opts.on_exit(-1)
    end
    return nil
  elseif job_id == -1 then
    log.error('Invalid arguments for command stream job')
    if opts.on_exit then
      opts.on_exit(-1)
    end
    return nil
  end

  log.debug('Started command stream job with ID: %d', job_id)
  return job_id
end

-- Helper function to build complex commands
function M.build_command(base_command, opts)
  opts = opts or {}

  local command_parts = {}

  -- Add environment setup if needed
  if opts.setup_env then
    table.insert(
      command_parts,
      '[ -f ~/.bashrc ] && source ~/.bashrc 2>/dev/null || [ -f ~/.profile ] && source ~/.profile 2>/dev/null || true'
    )
  end

  -- Add directory change if needed
  if opts.cd then
    table.insert(command_parts, string.format('cd %s', vim.fn.shellescape(opts.cd)))
  end

  -- Add the main command
  if type(base_command) == 'string' then
    table.insert(command_parts, base_command)
  elseif type(base_command) == 'table' then
    table.insert(command_parts, table.concat(base_command, ' '))
  end

  -- Combine with && to ensure proper execution order
  return table.concat(command_parts, ' && ')
end

-- Get container status
function M.get_container_status(container_id)
  -- Removed verbose debug log that was called every second
  local result = M.run_docker_command({ 'inspect', container_id, '--format', '{{.State.Status}}' })

  if result.success then
    return result.stdout:gsub('%s+', '')
  else
    return nil
  end
end

-- Get container detailed information
function M.get_container_info(container_id)
  log.debug('Getting container info: %s', container_id)

  local result = M.run_docker_command({ 'inspect', container_id })

  if result.success then
    local success, info = pcall(vim.json.decode, result.stdout)
    if success and info[1] then
      return info[1]
    end
  end

  return nil
end

-- Get container list
function M.list_containers(filter)
  log.debug('Listing containers with filter: %s', filter or 'all')

  local args = { 'ps', '-a', '--format', '{{.ID}}\\t{{.Names}}\\t{{.Status}}\\t{{.Image}}' }

  if filter then
    table.insert(args, '--filter')
    table.insert(args, filter)
  end

  local result = M.run_docker_command(args)

  if result.success then
    local containers = {}
    for line in result.stdout:gmatch('[^\n]+') do
      local id, name, status, image = line:match('([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)')
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

-- Wait for container to be ready
function M.wait_for_container_ready(container_id, callback, max_attempts)
  max_attempts = max_attempts or 30
  local attempts = 0

  local function check_ready()
    attempts = attempts + 1

    -- Check container status
    local status = M.get_container_status(container_id)
    if status == 'running' then
      -- Check by executing simple command
      M.exec_command(container_id, "echo 'ready'", {
        on_complete = function(result)
          if result.success then
            log.debug('Container is ready: %s', container_id)
            callback(true)
          elseif attempts < max_attempts then
            -- Wait 1 second and retry
            vim.defer_fn(check_ready, 1000)
          else
            log.warn('Container readiness check timed out: %s', container_id)
            callback(false)
          end
        end,
      })
    elseif attempts < max_attempts then
      -- Wait 1 second and retry
      vim.defer_fn(check_ready, 1000)
    else
      log.warn('Container failed to start: %s', container_id)
      callback(false)
    end
  end

  check_ready()
end

-- Get logs
function M.get_logs(container_id, opts)
  opts = opts or {}
  log.debug('Getting logs for container: %s', container_id)

  local args = { 'logs' }

  if opts.follow then
    table.insert(args, '-f')
  end

  if opts.tail then
    table.insert(args, '--tail')
    table.insert(args, tostring(opts.tail))
  end

  if opts.since then
    table.insert(args, '--since')
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

-- List devcontainers (containers created by this plugin)
function M.list_devcontainers()
  log.debug('Listing devcontainers')

  -- Filter for containers with "-devcontainer" suffix
  local containers = M.list_containers()
  local devcontainers = {}

  for _, container in ipairs(containers) do
    if container.name:match('-devcontainer$') then
      -- Parse status to determine if running
      local running = container.status:match('^Up') ~= nil

      table.insert(devcontainers, {
        id = container.id,
        name = container.name,
        status = container.status,
        image = container.image,
        running = running,
      })
    end
  end

  return devcontainers
end

-- Get container name for a project path
function M.get_container_name(project_path)
  local path_hash = vim.fn.sha256(project_path):sub(1, 8)
  local project_name = vim.fn.fnamemodify(project_path, ':t')
  return string.format('%s-%s-devcontainer', project_name:lower():gsub('[^a-z0-9_.-]', '-'), path_hash)
end

-- Get forwarded ports for all containers
function M.get_forwarded_ports()
  log.debug('Getting forwarded ports')

  local ports = {}
  local containers = M.list_devcontainers()

  for _, container in ipairs(containers) do
    if container.running then
      local success, info = pcall(M.get_container_info, container.id)
      if success and info and info.NetworkSettings and info.NetworkSettings.Ports then
        log.debug('Container %s has NetworkSettings.Ports: %s', container.name, vim.inspect(info.NetworkSettings.Ports))

        for container_port, bindings in pairs(info.NetworkSettings.Ports) do
          log.debug('Processing container_port: %s, bindings: %s', container_port, vim.inspect(bindings))

          if bindings and #bindings > 0 then
            for _, binding in ipairs(bindings) do
              log.debug('Processing binding: %s', vim.inspect(binding))

              local port_num = container_port:match('(%d+)')
              local host_port = binding.HostPort and tonumber(binding.HostPort)
              local container_port_num = port_num and tonumber(port_num)

              -- Only add if both ports are valid
              if host_port and container_port_num and host_port > 0 and container_port_num > 0 then
                table.insert(ports, {
                  container_name = container.name,
                  container_id = container.id,
                  container_port = container_port_num,
                  local_port = host_port,
                  protocol = container_port:match('/(%w+)') or 'tcp',
                  bind_address = binding.HostIp or '0.0.0.0',
                })
                log.debug('Added port mapping: %d->%d for container %s', host_port, container_port_num, container.name)
              else
                log.debug(
                  'Skipping invalid port mapping: host_port=%s, container_port=%s',
                  tostring(host_port),
                  tostring(container_port_num)
                )
              end
            end
          elseif bindings == vim.NIL or (bindings and type(bindings) == 'table') then
            -- Port is exposed but not bound to host
            local port_num = container_port:match('(%d+)')
            local container_port_num = port_num and tonumber(port_num)
            if container_port_num then
              log.debug('Port %s is exposed but not bound to host', container_port)
            end
          else
            log.debug('No bindings or empty bindings for port %s', container_port)
          end
        end
      elseif success then
        log.debug('Container %s has no NetworkSettings.Ports or missing NetworkSettings', container.name)
      else
        log.warn('Failed to get container info for %s: %s', container.name, tostring(info))
      end
    else
      log.debug('Container %s is not running', container.name)
    end
  end

  log.debug('Total forwarded ports found: %d', #ports)
  return ports
end

-- Stop port forwarding (requires recreating container)
function M.stop_port_forward(port_info)
  log.warn('Stopping individual port forwarding requires container recreation')
  -- This would require complex container recreation logic
  -- For now, just log a warning
  return false, 'Individual port forwarding cannot be stopped without recreating the container'
end

-- Attach to existing container
function M.attach_to_container(container_name, callback)
  log.info('Attaching to container: %s', container_name)

  -- First check if container exists
  local containers = M.list_containers()
  local found = false

  for _, container in ipairs(containers) do
    if container.name == container_name then
      found = true
      break
    end
  end

  if not found then
    if callback then
      callback(false, 'Container not found')
    end
    return
  end

  -- Return the container name as we'll use it for operations
  if callback then
    callback(true, container_name)
  end
end

-- Start existing container
function M.start_existing_container(container_name, callback)
  log.info('Starting existing container: %s', container_name)

  M.start_container_async(container_name, function(success, error_msg)
    if callback then
      callback(success, error_msg)
    end
  end)
end

-- Stop existing container
function M.stop_existing_container(container_name, callback)
  log.info('Stopping container: %s', container_name)

  local result = M.run_docker_command({ 'stop', container_name })

  if callback then
    callback(result.success, result.success and nil or result.stderr)
  end
end

-- Restart container
function M.restart_container(container_name, callback)
  log.info('Restarting container: %s', container_name)

  M.stop_existing_container(container_name, function(stop_success, stop_error)
    if not stop_success then
      if callback then
        callback(false, stop_error)
      end
      return
    end

    -- Wait a bit before starting
    vim.defer_fn(function()
      M.start_existing_container(container_name, callback)
    end, 1000)
  end)
end

-- Enhanced error message builders

-- Build detailed error message when Docker command is not found
function M._build_docker_not_found_error()
  local error_lines = {
    'Docker command not found.',
    '',
    'Please install Docker:',
    '• macOS: Install Docker Desktop from https://docker.com/products/docker-desktop',
    '• Linux: Use your package manager (e.g., apt install docker.io, yum install docker)',
    '• Windows: Install Docker Desktop from https://docker.com/products/docker-desktop',
    '',
    'After installation, ensure Docker is in your PATH and restart your terminal.',
  }
  return table.concat(error_lines, '\n')
end

-- Build detailed error message when Docker daemon is not running
function M._build_docker_daemon_error()
  local error_lines = {
    'Docker is installed but the daemon is not running.',
    '',
    'To start Docker daemon:',
    '• macOS/Windows: Start Docker Desktop application',
    '• Linux: Run "sudo systemctl start docker" or "sudo service docker start"',
    '',
    'If using Docker Desktop, check that it has started completely.',
    'You may need to wait a few moments after starting Docker Desktop.',
  }
  return table.concat(error_lines, '\n')
end

-- Force remove container (for shell compatibility issues)
function M.force_remove_container(container_id)
  log.info('Force removing container: %s', container_id)

  -- Stop container first if running
  M.run_docker_command({ 'stop', container_id })

  -- Remove container
  local result = M.run_docker_command({ 'rm', '-f', container_id })

  if result.success then
    log.info('Successfully removed container: %s', container_id)
    -- Clear shell cache for this container
    M.clear_shell_cache(container_id)
    return true
  else
    log.error('Failed to remove container: %s', result.stderr or 'unknown error')
    return false
  end
end

-- Enhanced network error handling
function M.handle_network_error(error_details)
  local error_lines = {
    'Network operation failed.',
    '',
    'Common causes:',
    '• No internet connection',
    '• Docker registry is unreachable',
    '• Firewall or proxy configuration issues',
    '',
    'Troubleshooting:',
    '• Check your internet connection',
    '• Try pulling a simple image: docker pull hello-world',
    '• Configure proxy settings if behind a corporate firewall',
  }

  if error_details then
    table.insert(error_lines, '')
    table.insert(error_lines, 'Error details: ' .. tostring(error_details))
  end

  return table.concat(error_lines, '\n')
end

-- Enhanced container operation error handling
function M.handle_container_error(operation, container_id, error_details)
  local error_lines = {
    string.format('Container %s operation failed.', operation),
    '',
  }

  if operation == 'create' then
    vim.list_extend(error_lines, {
      'Common causes:',
      '• Image not found or invalid',
      '• Port already in use',
      '• Insufficient resources (memory, disk space)',
      '• Invalid configuration in devcontainer.json',
      '',
      'Try:',
      '• Check if the specified image exists: docker images',
      '• Verify port availability: netstat -an | grep <port>',
      '• Check available disk space: df -h',
      '• Review your devcontainer.json configuration',
    })
  elseif operation == 'start' then
    vim.list_extend(error_lines, {
      'Common causes:',
      '• Container configuration conflicts',
      '• Resource constraints',
      '• Missing dependencies in container',
      '',
      'Try:',
      '• Check container logs: docker logs ' .. (container_id or '<container>'),
      '• Inspect container: docker inspect ' .. (container_id or '<container>'),
      '• Remove and recreate the container',
    })
  elseif operation == 'exec' then
    vim.list_extend(error_lines, {
      'Common causes:',
      '• Container not running',
      '• Command not found in container',
      '• Permission issues',
      '',
      'Try:',
      '• Check container status: docker ps',
      '• Verify command exists in container',
      '• Check user permissions and working directory',
    })
  end

  if error_details then
    table.insert(error_lines, '')
    table.insert(error_lines, 'Error details: ' .. tostring(error_details))
  end

  return table.concat(error_lines, '\n')
end

-- Timeout handling with retry mechanism
function M.with_timeout_and_retry(operation_name, operation_func, timeout_ms, max_retries)
  timeout_ms = timeout_ms or 30000 -- 30 seconds default
  max_retries = max_retries or 2 -- 2 retries default

  local function attempt(retry_count)
    local success = false
    local timed_out = false

    -- Set up timeout
    local timeout_timer = vim.defer_fn(function()
      timed_out = true
      log.warn('%s operation timed out (attempt %d/%d)', operation_name, retry_count + 1, max_retries + 1)
    end, timeout_ms)

    -- Execute operation
    operation_func(function(op_success, op_result)
      if not timed_out then
        success = op_success
        pcall(vim.fn.timer_stop, timeout_timer) -- Stop timeout timer

        if not success and retry_count < max_retries then
          log.info('Retrying %s operation (attempt %d/%d)', operation_name, retry_count + 2, max_retries + 1)
          vim.defer_fn(function()
            attempt(retry_count + 1)
          end, 2000) -- Wait 2 seconds before retry
        end
      end
    end)
  end

  attempt(0)
end

return M
