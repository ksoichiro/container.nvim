local M = {}
local log = require('container.utils.log')
local path = require('container.lsp.path')
-- local async = require('container.utils.async')  -- Reserved for future use

-- State for active forwardings
local active_forwards = {}
local stdio_bridges = {}

-- Find an available local port
local function find_available_port(start_port)
  start_port = start_port or 50000
  local max_attempts = 100

  for i = 0, max_attempts do
    local port = start_port + i
    local sock = vim.loop.new_tcp()
    local success = sock:bind('127.0.0.1', port)
    sock:close()

    if success then
      return port
    end
  end

  return nil
end

-- Setup port forwarding for a TCP-based LSP server
function M.setup_port_forwarding(container_id, container_port, server_name)
  local local_port = find_available_port()
  if not local_port then
    log.error('Forwarding: Could not find available local port')
    return nil
  end

  -- Check if container is using host network
  local docker = require('container.docker.init')
  local inspect_result =
    docker.exec_command(container_id, 'docker inspect ' .. container_id .. ' --format "{{.HostConfig.NetworkMode}}"')
  if
    inspect_result
    and inspect_result.code == 0
    and inspect_result.output
    and vim.trim(inspect_result.output) == 'host'
  then
    log.info('Forwarding: Container using host network, no forwarding needed')
    return container_port
  end

  -- Setup port forwarding using docker port mapping
  -- Note: This requires the container to be started with port mapping
  -- For dynamic forwarding, we'll use SSH or socat inside the container

  -- Try to setup socat forwarding inside the container
  -- local socat_cmd = string.format(
  --   'socat TCP-LISTEN:%d,reuseaddr,fork TCP:localhost:%d',
  --   local_port, container_port
  -- )

  -- Check if socat is available
  local socat_check = docker.exec_command(container_id, 'which socat', { output = false })
  if not socat_check or socat_check.code ~= 0 then
    log.warn('Forwarding: socat not available in container, trying direct connection')
    -- Fall back to direct container IP connection
    local ip_result = docker.exec_command(
      container_id,
      'docker inspect ' .. container_id .. ' --format "{{.NetworkSettings.IPAddress}}"'
    )
    if ip_result and ip_result.code == 0 and ip_result.output and ip_result.output ~= '' then
      local container_ip = vim.trim(ip_result.output)
      active_forwards[server_name] = {
        type = 'direct',
        host = container_ip,
        port = container_port,
      }
      log.info('Forwarding: Using direct connection to ' .. container_ip .. ':' .. container_port)
      return container_port, container_ip
    end
  end

  -- Store forwarding info
  active_forwards[server_name] = {
    type = 'port',
    local_port = local_port,
    container_port = container_port,
    container_id = container_id,
  }

  log.info(
    string.format(
      'Forwarding: Set up port forwarding %s - localhost:%d -> container:%d',
      server_name,
      local_port,
      container_port
    )
  )

  return local_port, 'localhost'
end

-- Create stdio bridge for stdio-based LSP servers
function M.create_stdio_bridge(container_id, cmd, server_name)
  log.info('Forwarding: Creating stdio bridge for ' .. server_name)

  -- Create pipes for communication
  local stdin = vim.loop.new_pipe(false)
  local stdout = vim.loop.new_pipe(false)
  local stderr = vim.loop.new_pipe(false)

  -- Build docker exec command
  local docker_cmd = {
    'docker',
    'exec',
    '-i',
    container_id,
  }

  -- Add the LSP server command
  for _, arg in ipairs(cmd) do
    table.insert(docker_cmd, arg)
  end

  -- Spawn the process
  local handle, pid = vim.loop.spawn(docker_cmd[1], {
    args = vim.list_slice(docker_cmd, 2),
    stdio = { stdin, stdout, stderr },
    detached = false,
  }, function(code, signal)
    log.info('Forwarding: stdio bridge process exited - ' .. server_name)
    M.stop_stdio_bridge(server_name)
  end)

  if not handle then
    log.error('Forwarding: Failed to create stdio bridge for ' .. server_name)
    stdin:close()
    stdout:close()
    stderr:close()
    return nil
  end

  -- Store bridge info
  stdio_bridges[server_name] = {
    handle = handle,
    pid = pid,
    stdin = stdin,
    stdout = stdout,
    stderr = stderr,
    container_id = container_id,
  }

  log.info('Forwarding: stdio bridge created for ' .. server_name .. ' (pid: ' .. pid .. ')')

  -- Return the stdio handles for LSP client
  return {
    stdin = stdin,
    stdout = stdout,
    stderr = stderr,
  }
end

-- Transform LSP requests/responses for path mapping
function M.create_request_handler(original_handler, direction)
  return function(err, result, ctx, config)
    if err then
      return original_handler(err, result, ctx, config)
    end

    -- Transform the result based on direction
    local transformed_result = result
    if result then
      transformed_result = path.transform_lsp_params(result, direction)
    end

    -- Call original handler with transformed result
    return original_handler(err, transformed_result, ctx, config)
  end
end

-- Create middleware for LSP client
function M.create_client_middleware()
  return {
    -- Handle window/showMessage notifications from LSP server
    ['window/showMessage'] = function(err, result, ctx, config)
      -- Check if the default handler exists, otherwise provide fallback
      local handler = vim.lsp.handlers['window/showMessage']
      if handler then
        return handler(err, result, ctx, config)
      else
        -- Fallback: Simple notification display
        if result and result.message then
          local level = result.type or 1 -- 1=Error, 2=Warning, 3=Info, 4=Log
          local level_names = { [1] = 'ERROR', [2] = 'WARN', [3] = 'INFO', [4] = 'DEBUG' }
          local level_name = level_names[level] or 'INFO'

          log.info('LSP %s: %s', level_name, result.message)

          -- Also show as vim notification if available
          if vim.notify then
            local notify_level = vim.log.levels.INFO -- luacheck: ignore 311
            if level == 1 then
              notify_level = vim.log.levels.ERROR
            elseif level == 2 then
              notify_level = vim.log.levels.WARN
            elseif level == 3 then
              notify_level = vim.log.levels.INFO
            else
              notify_level = vim.log.levels.DEBUG
            end

            if notify_level == vim.log.levels.ERROR then
              require('container.utils.notify').critical(result.message)
            elseif notify_level == vim.log.levels.WARN then
              require('container.utils.notify').container(result.message, { level = 'warn' })
            else
              require('container.utils.notify').container(result.message)
            end
          end
        end
      end
    end,

    -- Transform paths in common handlers with safety checks
    ['textDocument/definition'] = function(err, result, ctx, config)
      if result then
        result = path.transform_lsp_params(result, 'to_local')
      end

      local handler = vim.lsp.handlers['textDocument/definition']
      if handler then
        return handler(err, result, ctx, config)
      else
        log.warn('LSP handler for textDocument/definition not found')
        return nil
      end
    end,

    ['textDocument/references'] = function(err, result, ctx, config)
      if result then
        result = path.transform_lsp_params(result, 'to_local')
      end

      local handler = vim.lsp.handlers['textDocument/references']
      if handler then
        return handler(err, result, ctx, config)
      else
        log.warn('LSP handler for textDocument/references not found')
        return nil
      end
    end,

    ['textDocument/implementation'] = function(err, result, ctx, config)
      if result then
        result = path.transform_lsp_params(result, 'to_local')
      end

      local handler = vim.lsp.handlers['textDocument/implementation']
      if handler then
        return handler(err, result, ctx, config)
      else
        log.warn('LSP handler for textDocument/implementation not found')
        return nil
      end
    end,
  }
end

-- Get LSP client command configuration
function M.get_client_cmd(server_name, server_config, container_id)
  -- For now, use a simpler approach: create a docker exec command
  -- This bypasses the complexity of stdio bridges and should work reliably

  local cmd = {
    'docker',
    'exec',
    '-i',
  }

  -- Add environment-specific args (includes user and env vars)
  local environment = require('container.environment')
  local config = require('container').get_state().current_config
  local env_args = environment.build_lsp_args(config)
  for _, arg in ipairs(env_args) do
    table.insert(cmd, arg)
  end

  -- Add container
  table.insert(cmd, container_id)

  -- Special handling for Go language server
  if server_name == 'gopls' then
    -- Create a wrapper script that sets up proper configuration
    local docker = require('container.docker.init')
    local shell = docker.detect_shell and docker.detect_shell(container_id) or 'sh'
    table.insert(cmd, shell)
    table.insert(cmd, '-c')
    local gopls_script = [[
      # Change to workspace directory
      cd /workspace || exit 1

      # Set environment variables for Go
      export GO111MODULE=on
      export GOPATH=/go
      export GOROOT=/usr/local/go
      export PATH=/usr/local/go/bin:/go/bin:$PATH

      # Configure gopls to reduce file watching and improve stability
      export GOPLSREMOTEDEBUG=off
      export GOPLSREMOTELOG=off

      # Set up signal handlers to ensure clean shutdown
      trap 'exit 0' TERM INT

      # Start gopls with minimal configuration for stdio mode
      gopls -mode=stdio -remote=auto -rpc.trace=false -logfile=/tmp/gopls.log
    ]]
    table.insert(cmd, gopls_script)
  else
    table.insert(cmd, server_config.cmd or server_config.path or server_name)
  end

  log.info('Forwarding: Creating LSP command for ' .. server_name .. ': ' .. table.concat(cmd, ' '))

  return cmd
end

-- Stop stdio bridge
function M.stop_stdio_bridge(server_name)
  local bridge = stdio_bridges[server_name]
  if not bridge then
    return
  end

  -- Close pipes
  if bridge.stdin and not bridge.stdin:is_closing() then
    bridge.stdin:close()
  end
  if bridge.stdout and not bridge.stdout:is_closing() then
    bridge.stdout:close()
  end
  if bridge.stderr and not bridge.stderr:is_closing() then
    bridge.stderr:close()
  end

  -- Kill process
  if bridge.handle and not bridge.handle:is_closing() then
    bridge.handle:kill('sigterm')
  end

  stdio_bridges[server_name] = nil
  log.info('Forwarding: Stopped stdio bridge for ' .. server_name)
end

-- Stop port forwarding
function M.stop_port_forwarding(server_name)
  local forward = active_forwards[server_name]
  if not forward then
    return
  end

  active_forwards[server_name] = nil
  log.info('Forwarding: Stopped port forwarding for ' .. server_name)
end

-- Stop all forwardings
function M.stop_all()
  -- Stop all stdio bridges
  for server_name, _ in pairs(stdio_bridges) do
    M.stop_stdio_bridge(server_name)
  end

  -- Clear port forwardings
  active_forwards = {}

  log.info('Forwarding: Stopped all forwardings')
end

-- Get active forwardings
function M.get_active_forwardings()
  local result = {
    ports = {},
    stdio = {},
  }

  for name, info in pairs(active_forwards) do
    table.insert(result.ports, {
      name = name,
      type = info.type,
      local_port = info.local_port,
      container_port = info.container_port,
    })
  end

  for name, _ in pairs(stdio_bridges) do
    table.insert(result.stdio, name)
  end

  return result
end

return M
