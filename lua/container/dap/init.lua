local M = {}

local log = require('container.utils.log')
local docker = require('container.docker')
-- local port = require('container.utils.port')
-- local async = require('container.utils.async')
local config = require('container.config')
local notify = require('container.utils.notify')

M._state = {
  adapters = {},
  configurations = {},
  forwarded_ports = {},
  active_sessions = {},
}

function M.setup()
  log.debug('Setting up nvim-dap integration')

  local ok = pcall(require, 'dap')
  if not ok then
    log.debug('nvim-dap not installed, skipping DAP integration')
    return false
  end

  M._setup_autocmds()
  return true
end

function M._setup_autocmds()
  local group = vim.api.nvim_create_augroup('container_nvim_dap', { clear = true })

  vim.api.nvim_create_autocmd('User', {
    pattern = 'ContainerStarted',
    group = group,
    callback = function(event)
      -- Get container ID from event data
      local container_id = event.data.container_id
      if container_id then
        M._configure_for_container(container_id)
      end
    end,
  })

  vim.api.nvim_create_autocmd('User', {
    pattern = 'ContainerStopped',
    group = group,
    callback = function(event)
      local container_name = event.data.container_name
      if container_name then
        M._cleanup_container_config(container_name)
      end
    end,
  })
end

function M._configure_for_container(container_id)
  local dap_config = config.get().dap

  -- Check if DAP auto-setup is enabled
  if not dap_config.auto_setup then
    log.debug('DAP auto-setup is disabled')
    return
  end

  log.debug('Configuring DAP for container: ' .. container_id)

  local container_config = M._get_container_config(container_id)
  if not container_config then
    return
  end

  local language = container_config.language or M._detect_language(container_id)
  if not language then
    log.debug('Could not detect language for container')
    return
  end

  local adapter_config = M._get_adapter_config(language, container_id)
  if adapter_config then
    M._register_adapter(language, adapter_config)
    M._register_configuration(language, container_id)

    -- Auto-start debugger server if enabled and supported
    if dap_config.auto_start_debugger then
      if language == 'go' then
        M._start_dlv_server(container_id)
      end
      -- Add support for other languages here in the future
    end
  end
end

-- Start dlv debugger server in container
function M._start_dlv_server(container_id)
  local dap_config = config.get().dap
  local port = dap_config.ports.go

  log.debug('Checking dlv server in container: ' .. container_id .. ' on port ' .. port)

  -- Check for existing dlv processes on the configured port
  local check_result = docker.run_docker_command({ 'exec', container_id, 'pgrep', '-f', 'dlv.*listen.*:' .. port })

  if check_result.success and check_result.stdout ~= '' then
    log.debug('dlv server already running on port ' .. port)
    notify.info('Debug server ready on port ' .. port .. '. Use :DapNew to start debugging')
    return
  end

  log.debug('Starting new dlv server on port ' .. port .. '...')

  -- Cleanup old dlv processes
  docker.run_docker_command({ 'exec', container_id, 'pkill', '-f', 'dlv' })
  vim.fn.system('sleep 1')

  local workspace = dap_config.path_mappings.container_workspace

  -- Start dlv server with configured port
  local result = docker.run_docker_command({
    'exec',
    '-d',
    '-w',
    workspace,
    container_id,
    'dlv',
    'debug',
    '--headless',
    '--listen=:' .. port,
    '--api-version=2',
    '--accept-multiclient',
  })

  if result.success then
    log.info('dlv server started on port ' .. port)
    notify.info('Debug server ready on port ' .. port .. '. Use :DapNew to start debugging')
  else
    log.error('Failed to start dlv server: ' .. (result.stderr or ''))
  end
end

function M._get_container_config(container_id)
  local devcontainer_path = vim.fn.getcwd() .. '/.devcontainer/devcontainer.json'
  if vim.fn.filereadable(devcontainer_path) == 0 then
    devcontainer_path = vim.fn.getcwd() .. '/.devcontainer.json'
  end

  if vim.fn.filereadable(devcontainer_path) == 0 then
    return nil
  end

  local ok, parser = pcall(require, 'container.parser')
  if not ok then
    return nil
  end

  local container_config = parser.parse(devcontainer_path)
  return container_config
end

function M._detect_language(container_id)
  local files = vim.fn.glob('**/*', false, true)

  local language_patterns = {
    python = { '%.py$', 'requirements%.txt', 'setup%.py', 'pyproject%.toml' },
    javascript = { '%.js$', 'package%.json', '%.jsx$' },
    typescript = { '%.ts$', '%.tsx$', 'tsconfig%.json' },
    go = { '%.go$', 'go%.mod', 'go%.sum' },
    rust = { '%.rs$', 'Cargo%.toml', 'Cargo%.lock' },
    cpp = { '%.cpp$', '%.cc$', '%.cxx$', '%.hpp$', '%.h$', 'CMakeLists%.txt' },
    java = { '%.java$', 'pom%.xml', 'build%.gradle' },
  }

  for lang, patterns in pairs(language_patterns) do
    for _, pattern in ipairs(patterns) do
      for _, file in ipairs(files) do
        if file:match(pattern) then
          return lang
        end
      end
    end
  end

  return nil
end

function M._detect_workspace_path(container_id)
  -- Try to detect the actual workspace path from the container

  -- Method 1: Check devcontainer.json workspaceFolder setting
  local container_config = M._get_container_config(container_id)
  if container_config and container_config.workspaceFolder then
    log.debug('Using workspaceFolder from devcontainer.json: ' .. container_config.workspaceFolder)
    return container_config.workspaceFolder
  end

  -- Method 2: Check container's working directory
  local pwd_result = docker.run_docker_command({ 'exec', container_id, 'pwd' })
  if pwd_result.success and pwd_result.stdout then
    local current_dir = vim.trim(pwd_result.stdout)
    if current_dir ~= '/' and current_dir ~= '' then
      log.debug('Using container working directory: ' .. current_dir)
      return current_dir
    end
  end

  -- Method 3: Look for common workspace patterns
  local common_paths = { '/workspace', '/workspaces/' .. vim.fn.fnamemodify(vim.fn.getcwd(), ':t'), '/app', '/src' }
  for _, path in ipairs(common_paths) do
    local test_result = docker.run_docker_command({ 'exec', container_id, 'test', '-d', path })
    if test_result.success then
      log.debug('Found workspace at: ' .. path)
      return path
    end
  end

  log.debug('Could not detect workspace path, using configured default')
  return nil
end

function M._get_adapter_config(language, container_id)
  local dap_config = config.get().dap

  local adapters = {
    python = {
      type = 'executable',
      command = 'docker',
      args = {
        'exec',
        '-i',
        container_id,
        'python',
        '-m',
        'debugpy.adapter',
      },
    },
    go = function()
      -- Go adapter configuration for attach mode (more stable approach)
      return {
        type = 'server',
        host = '127.0.0.1',
        port = dap_config.ports.go,
      }
    end,
    -- For JavaScript/TypeScript, we'll need special handling
    javascript = nil,
    typescript = nil,
    rust = {
      type = 'executable',
      command = 'docker',
      args = {
        'exec',
        '-i',
        container_id,
        'rust-gdb',
        '--interpreter=dap',
      },
    },
  }

  return adapters[language]
end

function M._register_adapter(language, adapter_config)
  local ok, dap = pcall(require, 'dap')
  if not ok then
    return
  end

  local adapter_name = 'container_' .. language

  -- Special handling for Go language
  if language == 'go' then
    -- Set adapter directly (not as function)
    if type(adapter_config) == 'function' then
      dap.adapters[adapter_name] = adapter_config()
    else
      dap.adapters[adapter_name] = adapter_config
    end
  else
    dap.adapters[adapter_name] = adapter_config
  end

  M._state.adapters[language] = adapter_name

  -- For server-type adapters (like Go/dlv), set up port forwarding
  -- Handle both direct config and function-based config
  local config_to_check = adapter_config
  if type(adapter_config) == 'function' then
    config_to_check = adapter_config()
  end

  if config_to_check.type == 'server' and config_to_check.port then
    M._setup_port_forwarding(config_to_check.port)
  end

  log.debug('Registered DAP adapter for ' .. language)
end

function M._register_configuration(language, container_id)
  local ok, dap = pcall(require, 'dap')
  if not ok then
    return
  end

  local dap_config = config.get().dap

  -- Get workspace path from configuration
  local workspace_path = dap_config.path_mappings.container_workspace
  if dap_config.path_mappings.auto_detect_workspace then
    -- Try to detect workspace path from devcontainer configuration
    local detected_path = M._detect_workspace_path(container_id)
    if detected_path then
      workspace_path = detected_path
    end
    -- If detection fails, use the configured default path
  end

  local configurations = {
    python = {
      {
        type = 'container_python',
        request = 'launch',
        name = 'Container: Launch Python',
        program = '${file}',
        console = 'integratedTerminal',
        justMyCode = false,
        cwd = workspace_path,
        env = M._get_container_env(container_id),
        pathMappings = {
          {
            localRoot = '${workspaceFolder}',
            remoteRoot = workspace_path,
          },
        },
      },
    },
    go = {
      {
        type = 'container_go',
        request = 'attach',
        name = 'Container: Attach to dlv',
        mode = 'remote',
        port = dap_config.ports.go,
        host = '127.0.0.1',
        substitutePath = {
          {
            from = vim.fn.getcwd(), -- Host path
            to = workspace_path, -- Container path from config
          },
        },
        remotePath = workspace_path,
        localPath = vim.fn.getcwd(),
      },
      {
        type = 'container_go',
        request = 'launch',
        name = 'Container: Debug Test',
        mode = 'test',
        program = '${file}',
        cwd = workspace_path,
        env = M._get_container_env(container_id),
        args = {},
      },
    },
    rust = {
      {
        type = 'container_rust',
        request = 'launch',
        name = 'Container: Launch Rust',
        program = function()
          -- Find the compiled binary
          local cargo_target = vim.fn.system(
            'docker exec ' .. container_id .. ' find target/debug -maxdepth 1 -type f -executable | head -1'
          )
          return vim.trim(cargo_target)
        end,
        cwd = workspace_path,
        stopOnEntry = false,
        args = {},
        env = M._get_container_env(container_id),
      },
    },
  }

  if configurations[language] then
    dap.configurations[language] = dap.configurations[language] or {}
    for _, config in ipairs(configurations[language]) do
      table.insert(dap.configurations[language], 1, config)
    end
    M._state.configurations[language] = true
    log.debug('Registered DAP configurations for ' .. language)
  end
end

function M._get_container_env(container_id)
  local env = {}

  -- Use synchronous version for immediate results
  local result = docker.run_docker_command({ 'exec', container_id, 'env' })

  if result.success then
    for line in result.stdout:gmatch('[^\r\n]+') do
      local key, value = line:match('^([^=]+)=(.*)$')
      if key and value then
        env[key] = value
      end
    end
  end

  return env
end

function M._setup_port_forwarding(port)
  local container_main = require('container')
  local container_id = container_main.get_container_id()
  if not container_id then
    log.error('No active container for port forwarding')
    return false
  end

  -- Check if port forwarding is already active
  if M._state.forwarded_ports[port] then
    log.debug('Port %d forwarding already active', port)
    return true
  end

  log.debug('Setting up dynamic port forwarding for port %d', port)

  -- Method 1: Try to start a socat forwarder container
  local socat_cmd = {
    'run',
    '-d',
    '--rm',
    '--name',
    'dap-forwarder-' .. port,
    '--network',
    'container:' .. container_id,
    '-p',
    port .. ':' .. port,
    'alpine/socat',
    'TCP-LISTEN:' .. port .. ',fork,reuseaddr',
    'TCP-CONNECT:localhost:' .. port,
  }

  local result = docker.run_docker_command(socat_cmd)
  if result.success then
    M._state.forwarded_ports[port] = true
    log.info('Dynamic port forwarding started for port %d', port)
    return true
  else
    log.warn('Failed to set up dynamic port forwarding for port %d: %s', port, result.stderr or '')

    -- Method 2: Fallback - notify user to restart container
    log.warn('Port forwarding requires container restart. Please run :ContainerStop and :ContainerStart')
    notify.warn('DAP port forwarding requires container restart. Run :ContainerStop and :ContainerStart')
    return false
  end
end

function M._cleanup_container_config(container_name)
  log.debug('Cleaning up DAP config for container: ' .. container_name)

  -- Cleanup any session-specific data
  for session_id, session_info in pairs(M._state.active_sessions) do
    if session_info.container_name == container_name then
      M._state.active_sessions[session_id] = nil
    end
  end
end

function M.start_debugging(opts)
  opts = opts or {}

  -- Get current container from main module
  local container_main = require('container')
  local container_id = container_main.get_container_id()
  if not container_id then
    log.error('No active container found')
    return false
  end

  local ok, dap = pcall(require, 'dap')
  if not ok then
    log.error('nvim-dap is not installed')
    return false
  end

  local language = opts.language or M._detect_language(container_id)
  if not language then
    log.error('Could not detect language for debugging')
    return false
  end

  log.debug('Starting debug with language: ' .. language)

  if not M._state.configurations[language] then
    M._configure_for_container(container_id)
  end

  -- Start debugging - explicitly use go configuration
  if language == 'go' then
    -- Find Container: Attach to dlv configuration
    local go_configs = dap.configurations.go or {}
    local container_config = nil

    for _, config in ipairs(go_configs) do
      if config.name == 'Container: Attach to dlv' then
        container_config = config
        break
      end
    end

    if container_config then
      log.debug('Using Container: Attach to dlv configuration')
      dap.run(container_config)
    else
      log.error('Container: Attach to dlv configuration not found')
      return false
    end
  else
    dap.continue()
  end

  return true
end

function M.stop_debugging()
  local ok, dap = pcall(require, 'dap')
  if not ok then
    return
  end

  dap.terminate()
  dap.close()
end

function M.list_debug_sessions()
  local sessions = {}
  for session_id, session_info in pairs(M._state.active_sessions) do
    table.insert(sessions, {
      id = session_id,
      container = session_info.container_name,
      language = session_info.language,
      started_at = session_info.started_at,
    })
  end
  return sessions
end

function M.get_debug_status()
  local ok, dap = pcall(require, 'dap')
  if not ok then
    return 'nvim-dap not installed'
  end

  local session = dap.session()
  if session then
    return 'debugging'
  else
    return 'ready'
  end
end

return M
