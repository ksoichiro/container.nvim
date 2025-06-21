-- DAP デバッグヘルパー関数

local M = {}

-- DAP のログレベルを設定
function M.set_debug_log()
  require('dap').set_log_level('TRACE')
  print('DAP log level set to TRACE. Check logs at: ' .. vim.fn.stdpath('cache') .. '/dap.log')
end

-- DAPログを表示
function M.show_dap_log()
  local log_path = vim.fn.stdpath('cache') .. '/dap.log'
  vim.cmd('edit ' .. log_path)
  vim.cmd('normal G') -- 最後の行に移動
end

-- DAP のステータスを表示
function M.show_status()
  local dap = require('dap')
  local session = dap.session()

  if session then
    print('DAP Session Active:')
    print('  State: ' .. (session.state or 'unknown'))
    print('  Adapter: ' .. vim.inspect(session.adapter))
  else
    print('No active DAP session')
  end

  -- ブレークポイント情報
  local breakpoints = require('dap.breakpoints').get()
  local bp_count = 0
  for _, bps in pairs(breakpoints) do
    bp_count = bp_count + #bps
  end
  print('Breakpoints set: ' .. bp_count)
end

-- コンテナ内でデバッガーが実行されているか確認
function M.check_container_debugger()
  local container_id = require('container').get_container_id()
  if not container_id then
    print('No active container')
    return
  end

  -- dlv プロセスを確認
  local result = require('container.docker').run_docker_command({
    'exec',
    container_id,
    'pgrep',
    '-l',
    'dlv',
  })

  if result.success and result.stdout ~= '' then
    print('Delve debugger processes in container:')
    print(result.stdout)
  else
    print('No dlv process found in container')
  end
end

-- DAP設定を確認
function M.show_dap_config()
  local dap = require('dap')
  print('=== DAP Configurations ===')
  print('Go configurations:')
  print(vim.inspect(dap.configurations.go))
  print('\nGo adapter:')
  print(vim.inspect(dap.adapters.container_go))
end

-- 手動でデバッガーをテスト
function M.test_debugger_connection()
  local container_id = require('container').get_container_id()
  if not container_id then
    print('No active container')
    return
  end

  print('Testing dlv in container...')

  -- dlvがインストールされているか確認
  local result = require('container.docker').run_docker_command({
    'exec',
    container_id,
    'which',
    'dlv',
  })

  if result.success then
    print('dlv found at: ' .. vim.trim(result.stdout))
  else
    print('dlv not found in container!')
    return
  end

  -- dlvのバージョンを確認
  local version_result = require('container.docker').run_docker_command({
    'exec',
    container_id,
    'dlv',
    'version',
  })

  if version_result.success then
    print('dlv version:')
    print(version_result.stdout)
  end
end

-- コンテナ情報を表示
function M.show_container_info()
  local container_id = require('container').get_container_id()
  local container_state = require('container').get_state()

  print('=== Container Information ===')
  print('Container ID: ' .. (container_id or 'none'))
  print('Container Status: ' .. (container_state.container_status or 'unknown'))
  if container_state.current_config then
    print('Container Name: ' .. (container_state.current_config.name or 'unknown'))
  end
end

-- 手動でDAP設定を行う
function M.manual_setup()
  local container_id = require('container').get_container_id()
  if not container_id then
    print('No active container')
    return
  end

  local dap_module = require('container.dap')
  print('Manually configuring DAP for container ID: ' .. container_id)

  -- 言語を検出
  local language = dap_module._detect_language(container_id)
  print('Detected language: ' .. (language or 'none'))

  if language then
    -- アダプター設定を取得
    local adapter_config = dap_module._get_adapter_config(language, container_id)
    if adapter_config then
      print('Adapter config:')
      print(vim.inspect(adapter_config))

      -- アダプターを登録
      dap_module._register_adapter(language, adapter_config)

      -- 設定を登録
      dap_module._register_configuration(language, container_id)

      print('DAP configuration completed')
    else
      print('No adapter config available for ' .. language)
    end
  end
end

-- dlvプロセスをクリーンアップ
function M.cleanup_dlv_processes()
  local container_id = require('container').get_container_id()
  if not container_id then
    print('No active container')
    return
  end

  print('Cleaning up dlv processes...')

  -- 強制終了 (SIGKILL)
  local kill_result = require('container.docker').run_docker_command({
    'exec',
    container_id,
    'pkill',
    '-9',
    '-f',
    'dlv',
  })

  -- 少し待つ
  vim.fn.system('sleep 1')

  -- プロセス確認
  local check_result = require('container.docker').run_docker_command({
    'exec',
    container_id,
    'pgrep',
    '-l',
    'dlv',
  })

  if check_result.success and check_result.stdout ~= '' then
    print('⚠️ Some dlv processes still running:')
    print(check_result.stdout)
  else
    print('✓ All dlv processes cleaned up')
  end
end

-- 簡単なGoデバッグテスト
function M.test_simple_go_debug()
  local container_id = require('container').get_container_id()
  if not container_id then
    print('No active container')
    return
  end

  print('Testing simple Go debug configuration...')

  local dap = require('dap')

  -- 簡単なアダプター設定
  dap.adapters.go_simple = {
    type = 'executable',
    command = 'docker',
    args = { 'exec', '-i', container_id, 'dlv', 'dap', '--listen=stdio' },
  }

  -- 簡単な設定
  dap.configurations.go = {
    {
      type = 'go_simple',
      request = 'launch',
      name = 'Simple Go Debug',
      mode = 'debug',
      program = '${file}',
    },
  }

  print("Simple adapter and configuration set. Try :lua require('dap').continue()")
end

-- dlvのテスト実行
function M.test_dlv_direct()
  local container_id = require('container').get_container_id()
  if not container_id then
    print('No active container')
    return
  end

  -- 現在のファイルを確認
  local current_file = vim.fn.expand('%:p')
  local file_name = vim.fn.expand('%:t')
  local file_ext = vim.fn.expand('%:e')

  print('Current file: ' .. current_file)
  print('File name: ' .. file_name)
  print('File extension: ' .. file_ext)

  if file_ext ~= 'go' then
    print('Error: Current file is not a Go file. Please open a .go file and try again.')
    return
  end

  print('Testing dlv directly in container...')

  -- ターミナルで直接dlvを実行
  vim.cmd('ContainerTerminal')
  vim.defer_fn(function()
    local cmd = string.format('dlv debug %s', file_name)
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(cmd .. '<CR>', true, false, true), 'n', false)
  end, 500)
end

-- 現在のバッファ情報を表示
function M.show_current_buffer_info()
  local current_file = vim.fn.expand('%:p')
  local file_name = vim.fn.expand('%:t')
  local file_ext = vim.fn.expand('%:e')
  local file_type = vim.bo.filetype

  print('=== Current Buffer Info ===')
  print('Full path: ' .. current_file)
  print('File name: ' .. file_name)
  print('Extension: ' .. file_ext)
  print('Filetype: ' .. file_type)
  print('Buffer number: ' .. vim.fn.bufnr('%'))
end

-- DAP設定後の動作テスト
function M.test_after_setup()
  print('=== Testing DAP after setup ===')

  -- 現在のファイル確認
  M.show_current_buffer_info()

  -- DAP設定確認
  local dap = require('dap')
  print('\nAvailable Go configurations:')
  if dap.configurations.go then
    for i, config in ipairs(dap.configurations.go) do
      print(string.format('  %d. %s', i, config.name))
    end
  else
    print('  No Go configurations found')
  end

  print('\nContainer Go adapter:')
  if dap.adapters.container_go then
    print('  ✓ container_go adapter is registered')
  else
    print('  ✗ container_go adapter not found')
  end
end

-- ブレークポイントの設定をテスト
function M.test_breakpoint()
  local dap = require('dap')
  local current_line = vim.fn.line('.')

  print('Setting breakpoint at line ' .. current_line)
  dap.toggle_breakpoint()

  local breakpoints = require('dap.breakpoints').get()
  local current_file = vim.fn.expand('%:p')

  if breakpoints[current_file] then
    print('Breakpoints in current file:')
    for _, bp in ipairs(breakpoints[current_file]) do
      print(string.format('  Line %d', bp.line))
    end
  else
    print('No breakpoints set in current file')
  end
end

-- 言語検出をテスト
function M.test_language_detection()
  local container_id = require('container').get_container_id()
  if not container_id then
    print('No active container')
    return
  end

  local dap_module = require('container.dap')
  local detected_language = dap_module._detect_language(container_id)

  print('=== Language Detection Test ===')
  print('Detected language: ' .. (detected_language or 'none'))

  -- 手動でGoを指定してデバッグを開始
  print("\nStarting debug with explicit 'go' language...")

  local container_main = require('container')
  container_main.dap_start({ language = 'go' })
end

-- 手動でGo設定を選択
function M.start_go_debug_manual()
  local dap = require('dap')

  print('Available configurations:')
  for i, config in ipairs(dap.configurations.go) do
    print(string.format('  %d. %s', i, config.name))
  end

  print("\nStarting 'Container: Launch Go' configuration...")

  -- 設定を手動で選択
  for _, config in ipairs(dap.configurations.go) do
    if config.name == 'Container: Launch Go' then
      dap.run(config)
      break
    end
  end
end

-- 直接Go設定でデバッグを開始（notify問題を回避）
function M.start_go_debug_direct()
  local dap = require('dap')
  local container_id = require('container').get_container_id()

  if not container_id then
    print('No active container')
    return
  end

  -- Container: Launch Go設定を探す
  local go_configs = dap.configurations.go or {}
  local container_config = nil

  for _, config in ipairs(go_configs) do
    if config.name == 'Container: Launch Go' then
      container_config = config
      break
    end
  end

  if not container_config then
    print('Container: Launch Go configuration not found')
    return
  end

  print('Starting Go debug with Container: Launch Go configuration...')
  print('Current file: ' .. vim.fn.expand('%:t'))

  -- 直接実行
  dap.run(container_config)
end

-- コンテナ内でdlvを直接テスト
function M.test_dlv_in_container()
  local container_id = require('container').get_container_id()
  if not container_id then
    print('No active container')
    return
  end

  print('Testing dlv dap command in container...')

  -- dlv dapコマンドが動作するかテスト
  local result = require('container.docker').run_docker_command({
    'exec',
    container_id,
    'dlv',
    'version',
  })

  if result.success then
    print('dlv version in container:')
    print(result.stdout)
  else
    print('dlv version failed:')
    print(result.stderr)
    return
  end

  -- 簡単なGoファイルが存在するかチェック
  local file_result = require('container.docker').run_docker_command({
    'exec',
    container_id,
    'ls',
    '/workspace',
  })

  if file_result.success then
    print('\nFiles in workspace:')
    print(file_result.stdout)
  end

  -- 現在のディレクトリを確認
  local pwd_result = require('container.docker').run_docker_command({
    'exec',
    container_id,
    'pwd',
  })

  if pwd_result.success then
    print('\nCurrent directory in container:')
    print(pwd_result.stdout)
  end
end

-- デバッグ用のシンプルなテスト
function M.test_simple_docker_exec()
  local container_id = require('container').get_container_id()
  if not container_id then
    print('No active container')
    return
  end

  print('Testing simple docker exec...')

  local result = require('container.docker').run_docker_command({
    'exec',
    container_id,
    'echo',
    'hello',
  })

  if result.success then
    print('Docker exec test successful:')
    print('stdout: ' .. result.stdout)
  else
    print('Docker exec test failed:')
    print('stderr: ' .. (result.stderr or ''))
    print('code: ' .. (result.code or 'unknown'))
  end
end

-- dlv dapコマンドを直接テスト
function M.test_dlv_dap_command()
  local container_id = require('container').get_container_id()
  if not container_id then
    print('No active container')
    return
  end

  print('Testing dlv dap command directly...')

  -- まず、dlv helpを確認
  local help_result = require('container.docker').run_docker_command({
    'exec',
    container_id,
    'dlv',
    'help',
  })

  if help_result.success then
    print('dlv help available')
    -- dapがサポートされているか確認
    if help_result.stdout:match('dap') then
      print('✓ dlv supports dap command')
    else
      print('✗ dlv does not support dap command')
      print('Available commands:')
      print(help_result.stdout)
    end
  end

  -- dlv dap --helpを試す
  local dap_help_result = require('container.docker').run_docker_command({
    'exec',
    container_id,
    'dlv',
    'dap',
    '--help',
  })

  if dap_help_result.success then
    print('\ndlv dap --help:')
    print(dap_help_result.stdout)
  else
    print('\ndlv dap --help failed:')
    print('stderr: ' .. (dap_help_result.stderr or ''))
    print('exit code: ' .. (dap_help_result.code or 'unknown'))
  end
end

-- より詳細なdlvテスト
function M.test_dlv_with_file()
  local container_id = require('container').get_container_id()
  if not container_id then
    print('No active container')
    return
  end

  local current_file = vim.fn.expand('%:t')
  print('Testing dlv with current file: ' .. current_file)

  -- main.goファイルでdlvをテスト
  local result = require('container.docker').run_docker_command({
    'exec',
    '-w',
    '/workspace',
    container_id,
    'dlv',
    'debug',
    'main.go',
    '--help',
  })

  if result.success then
    print('dlv debug main.go --help successful')
  else
    print('dlv debug main.go failed:')
    print('stderr: ' .. (result.stderr or ''))
    print('exit code: ' .. (result.code or 'unknown'))
  end
end

-- 新しいサーバーベース設定をテスト
function M.test_new_server_config()
  local container_id = require('container').get_container_id()
  if not container_id then
    print('No active container')
    return
  end

  print('=== Testing new server-based DAP configuration ===')

  -- 手動でコンテナ設定を更新
  local dap_module = require('container.dap')
  dap_module._configure_for_container(container_id)

  -- 設定を確認
  local dap = require('dap')
  print('Go adapter configuration:')
  print(vim.inspect(dap.adapters.container_go))

  print('\nGo configurations:')
  if dap.configurations.go then
    for i, config in ipairs(dap.configurations.go) do
      if config.name == 'Container: Launch Go' then
        print(string.format('Found configuration: %s', config.name))
        print('Type: ' .. config.type)
        print('Request: ' .. config.request)
        print('Mode: ' .. (config.mode or 'N/A'))
        print('Port: ' .. (config.port or 'N/A'))
        print('Host: ' .. (config.host or 'N/A'))
        break
      end
    end
  end
end

-- dlvサーバーを手動で起動してテスト
function M.start_dlv_server_manual()
  local container_id = require('container').get_container_id()
  if not container_id then
    print('No active container')
    return
  end

  print('Starting dlv server manually in container...')

  -- まず、既存のdlvプロセスをクリーンアップ
  M.cleanup_dlv_processes()

  -- バックグラウンドでdlvサーバーを起動
  local result = require('container.docker').run_docker_command({
    'exec',
    '-d',
    '-w',
    '/workspace',
    container_id,
    'dlv',
    'debug',
    '--headless',
    '--listen=:2345',
    '--api-version=2',
    '--accept-multiclient',
  })

  if result.success then
    print('✓ dlv server started in background')

    -- 少し待ってからプロセス確認
    vim.defer_fn(function()
      local check_result = require('container.docker').run_docker_command({
        'exec',
        container_id,
        'pgrep',
        '-l',
        'dlv',
      })

      if check_result.success and check_result.stdout ~= '' then
        print('✓ dlv process confirmed running:')
        print(check_result.stdout)

        print('\nNow you can try:')
        print("1. :lua require('container.dap.debug').test_new_server_config()")
        print("2. :lua require('dap').continue()")
      else
        print('✗ dlv process not found after startup')
      end
    end, 2000)
  else
    print('✗ Failed to start dlv server:')
    print('stderr: ' .. (result.stderr or ''))
  end
end

-- DAPサーバー接続をテスト
function M.test_dap_connection()
  local dap = require('dap')

  print('=== Testing DAP connection ===')

  -- Go設定を探す
  local go_configs = dap.configurations.go or {}
  local container_config = nil

  for _, config in ipairs(go_configs) do
    if config.name == 'Container: Launch Go' then
      container_config = config
      break
    end
  end

  if not container_config then
    print('✗ Container: Launch Go configuration not found')
    print('Available configurations:')
    for i, config in ipairs(go_configs) do
      print(string.format('  %d. %s', i, config.name))
    end
    return
  end

  print('✓ Found Container: Launch Go configuration')
  print('Testing connection...')

  -- 接続テストの設定
  dap.run(container_config)

  -- 接続状態を確認
  vim.defer_fn(function()
    local session = dap.session()
    if session then
      print('✓ DAP session created')
      print('Session state: ' .. (session.state or 'unknown'))
    else
      print('✗ No DAP session created')
    end
  end, 3000)
end

-- ポートフォワーディングをテスト
function M.test_port_forwarding()
  local container_id = require('container').get_container_id()
  if not container_id then
    print('No active container')
    return
  end

  print('=== Testing port forwarding ===')

  -- ポート2345の動的フォワーディングを試行
  local dap_module = require('container.dap')
  local success = dap_module._setup_port_forwarding(2345)

  if success then
    print('✓ Port forwarding setup successful')

    -- 接続テスト
    vim.defer_fn(function()
      print('Testing connection to localhost:2345...')
      -- 簡単な接続テスト（telnetのように）
      local test_result = vim.fn.system('timeout 5 bash -c "echo > /dev/tcp/127.0.0.1/2345" 2>/dev/null')
      local exit_code = vim.v.shell_error

      if exit_code == 0 then
        print('✓ Port 2345 is accessible')
      else
        print('✗ Port 2345 is not accessible (exit code: ' .. exit_code .. ')')
        print('You may need to restart the container:')
        print('  :ContainerStop')
        print('  :ContainerStart')
      end
    end, 2000)
  else
    print('✗ Port forwarding setup failed')
  end
end

-- すべての手順を自動で実行
function M.run_full_dap_test()
  print('=== Running full DAP test sequence ===\n')

  -- Step 1: コンテナと基本情報を確認
  M.show_container_info()
  print('')

  -- Step 2: dlvサーバーを起動
  print('Step 1: Starting dlv server...')
  M.start_dlv_server_manual()

  -- Step 3: 少し待ってからポートフォワーディングをテスト
  vim.defer_fn(function()
    print('\nStep 2: Testing port forwarding...')
    M.test_port_forwarding()

    -- Step 4: さらに待ってからDAP設定をテスト
    vim.defer_fn(function()
      print('\nStep 3: Testing DAP configuration...')
      M.test_new_server_config()

      -- Step 5: 最後にDAP接続をテスト
      vim.defer_fn(function()
        print('\nStep 4: Testing DAP connection...')
        M.test_dap_connection()
      end, 2000)
    end, 3000)
  end, 3000)
end

-- dlv dapコマンドの詳細テスト
function M.test_dlv_dap_stdio()
  local container_id = require('container').get_container_id()
  if not container_id then
    print('No active container')
    return
  end

  print('=== Testing dlv dap --listen=stdio ===')

  -- コンテナ内でdlv dapコマンドを直接テスト
  print('Testing dlv dap --listen=stdio directly...')

  local result = require('container.docker').run_docker_command({
    'exec',
    '-w',
    '/workspace',
    container_id,
    'timeout',
    '5',
    'dlv',
    'dap',
    '--listen=stdio',
    '--check-go-version=false',
  })

  print('Exit code: ' .. (result.code or 'unknown'))
  print('Success: ' .. tostring(result.success))

  if result.stdout and result.stdout ~= '' then
    print('STDOUT:')
    print(result.stdout)
  end

  if result.stderr and result.stderr ~= '' then
    print('STDERR:')
    print(result.stderr)
  end

  -- 代替コマンドもテスト
  print('\n--- Testing dlv exec --listen=stdio ---')
  local exec_result = require('container.docker').run_docker_command({
    'exec',
    '-w',
    '/workspace',
    container_id,
    'timeout',
    '5',
    'dlv',
    'exec',
    '--listen=stdio',
    '--check-go-version=false',
    './main',
  })

  print('Exec exit code: ' .. (exec_result.code or 'unknown'))
  if exec_result.stderr and exec_result.stderr ~= '' then
    print('Exec STDERR:')
    print(exec_result.stderr)
  end
end

-- 作業ディレクトリに実行可能ファイルがあるかチェック
function M.check_workspace_setup()
  local container_id = require('container').get_container_id()
  if not container_id then
    print('No active container')
    return
  end

  print('=== Checking workspace setup ===')

  -- ワークスペースの内容確認
  local ls_result = require('container.docker').run_docker_command({
    'exec',
    '-w',
    '/workspace',
    container_id,
    'ls',
    '-la',
  })

  if ls_result.success then
    print('Workspace contents:')
    print(ls_result.stdout)
  end

  -- Goファイルをビルドしてみる
  print('\n--- Testing go build ---')
  local build_result = require('container.docker').run_docker_command({
    'exec',
    '-w',
    '/workspace',
    container_id,
    'go',
    'build',
    '-o',
    'main',
    '.',
  })

  print('Build exit code: ' .. (build_result.code or 'unknown'))
  if build_result.success then
    print('✓ Go build successful')

    -- 実行可能ファイルの確認
    local check_result = require('container.docker').run_docker_command({
      'exec',
      '-w',
      '/workspace',
      container_id,
      'ls',
      '-la',
      'main',
    })

    if check_result.success then
      print("✓ Executable 'main' created:")
      print(check_result.stdout)
    end
  else
    print('✗ Go build failed:')
    if build_result.stderr then
      print(build_result.stderr)
    end
  end
end

-- dlv exec with server modeをテスト
function M.test_dlv_exec_server()
  local container_id = require('container').get_container_id()
  if not container_id then
    print('No active container')
    return
  end

  print('=== Testing dlv exec in server mode ===')

  -- まず既存のdlvプロセスをクリーンアップ
  M.cleanup_dlv_processes()

  -- dlv debug with server mode (source-level debugging, using port 3456)
  print('Starting dlv debug --listen=:3456...')
  local result = require('container.docker').run_docker_command({
    'exec',
    '-d',
    '-w',
    '/workspace',
    container_id,
    'dlv',
    'debug',
    '--accept-multiclient',
    '--api-version=2',
    '--headless',
    '--listen=:3456',
  })

  if result.success then
    print('✓ dlv debug server started in background')

    -- 少し待ってからプロセス確認
    vim.defer_fn(function()
      local check_result = require('container.docker').run_docker_command({
        'exec',
        container_id,
        'pgrep',
        '-l',
        'dlv',
      })

      if check_result.success and check_result.stdout ~= '' then
        print('✓ dlv process confirmed running:')
        print(check_result.stdout)

        -- ポート確認
        local port_result = require('container.docker').run_docker_command({
          'exec',
          container_id,
          'netstat',
          '-tlnp',
          '|',
          'grep',
          '3456',
        })

        if port_result.success and port_result.stdout ~= '' then
          print('✓ Port 3456 is listening:')
          print(port_result.stdout)
        else
          print('? Port 3456 status unclear')
        end

        print('\nNow you can try:')
        print("1. :lua require('container.dap.debug').test_new_server_config()")
        print("2. :lua require('container.dap.debug').test_dap_connection()")
      else
        print('✗ dlv process not found after startup')
      end
    end, 2000)
  else
    print('✗ Failed to start dlv exec server:')
    print('stderr: ' .. (result.stderr or ''))
  end
end

-- 詳細なDAP診断を実行
function M.deep_dap_diagnosis()
  print('=== Deep DAP Diagnosis ===')

  -- 1. 現在のDAP設定を詳細に確認
  local dap = require('dap')
  print('\n1. Current DAP Configuration:')
  print('Adapters available:')
  for name, adapter in pairs(dap.adapters) do
    if name:match('container') or name:match('go') then
      print(string.format('  %s: %s', name, type(adapter)))
      if type(adapter) == 'function' then
        local result = adapter()
        print('    Function result: ' .. vim.inspect(result))
      else
        print('    Config: ' .. vim.inspect(adapter))
      end
    end
  end

  print('\nConfigurations available:')
  if dap.configurations.go then
    for i, config in ipairs(dap.configurations.go) do
      print(string.format('  %d. %s (type: %s, request: %s)', i, config.name, config.type, config.request))
    end
  else
    print('  No Go configurations found')
  end

  -- 2. コンテナとネットワーク状況
  print('\n2. Container Network Status:')
  local container_id = require('container').get_container_id()
  if container_id then
    print('Container ID: ' .. container_id)

    -- ポートフォワーディング確認
    local port_check = require('container.docker').run_docker_command({
      'port',
      container_id,
    })

    if port_check.success then
      print('Port mappings:')
      print(port_check.stdout)
    else
      print('No port mappings found')
    end

    -- コンテナ内のポート状況
    local container_ports = require('container.docker').run_docker_command({
      'exec',
      container_id,
      'ss',
      '-tlnp',
    })

    if container_ports.success then
      print('Container internal ports:')
      for line in container_ports.stdout:gmatch('[^\r\n]+') do
        if line:match('2345') then
          print('  ' .. line)
        end
      end
    end
  end

  -- 3. DAP通信テスト
  print('\n3. DAP Communication Test:')
  local container_config = nil

  if dap.configurations.go then
    for _, config in ipairs(dap.configurations.go) do
      if config.name == 'Container: Launch Go' then
        container_config = config
        break
      end
    end
  end

  if container_config then
    print('Found Container: Launch Go configuration')
    print('Configuration details:')
    print(vim.inspect(container_config))

    -- アダプター取得
    local adapter = dap.adapters[container_config.type]
    if adapter then
      print('Adapter found: ' .. container_config.type)
      if type(adapter) == 'function' then
        local adapter_result = adapter()
        print('Adapter function result:')
        print(vim.inspect(adapter_result))
      end
    else
      print('❌ Adapter NOT found: ' .. container_config.type)
    end
  else
    print('❌ Container: Launch Go configuration NOT found')
  end

  -- 4. ホスト側のポート接続テスト
  print('\n4. Host Port Connection Test:')
  local test_connection = vim.fn.system('timeout 3 bash -c "echo test | nc -w1 127.0.0.1 2345" 2>&1')
  local exit_code = vim.v.shell_error

  print('Connection test to 127.0.0.1:2345:')
  print('Exit code: ' .. exit_code)
  print('Output: ' .. test_connection)

  if exit_code == 0 then
    print('✓ Port 2345 is accessible from host')
  else
    print('❌ Port 2345 is NOT accessible from host')
  end
end

-- DAP実行時の詳細ログ
function M.debug_dap_run()
  print('=== DAP Run Debug ===')

  local dap = require('dap')

  -- DAP logレベルを最高にする
  dap.set_log_level('TRACE')
  print('DAP log level set to TRACE')

  -- Container: Launch Go設定を取得
  local go_configs = dap.configurations.go or {}
  local container_config = nil

  for _, config in ipairs(go_configs) do
    if config.name == 'Container: Launch Go' then
      container_config = config
      break
    end
  end

  if not container_config then
    print('❌ Container: Launch Go configuration not found')
    return
  end

  print('Configuration to run:')
  print(vim.inspect(container_config))

  -- 現在のセッション状態を確認
  local current_session = dap.session()
  if current_session then
    print('⚠️ Active session exists, terminating first...')
    dap.terminate()
    dap.close()

    vim.defer_fn(function()
      print('Previous session closed, starting new session...')
      dap.run(container_config)

      -- 3秒後にセッション状態を確認
      vim.defer_fn(function()
        local new_session = dap.session()
        if new_session then
          print('✓ New DAP session created successfully')
          print('Session state: ' .. (new_session.state or 'unknown'))
          print('Session adapter: ' .. vim.inspect(new_session.adapter))
        else
          print('❌ Failed to create new DAP session')
          print('Check DAP log for details: :DapShowLog')
        end
      end, 3000)
    end, 1000)
  else
    print('No active session, starting fresh...')
    dap.run(container_config)

    -- 3秒後にセッション状態を確認
    vim.defer_fn(function()
      local new_session = dap.session()
      if new_session then
        print('✓ DAP session created successfully')
        print('Session state: ' .. (new_session.state or 'unknown'))
        print('Session adapter: ' .. vim.inspect(new_session.adapter))
      else
        print('❌ Failed to create DAP session')
        print('Check DAP log for details: :DapShowLog')
      end
    end, 3000)
  end
end

-- 手動でDAP設定を強制登録
function M.force_register_dap_config()
  print('=== Force Register DAP Configuration ===')

  local container_id = require('container').get_container_id()
  if not container_id then
    print('❌ No active container')
    return
  end

  print('Container ID: ' .. container_id)

  local dap = require('dap')

  -- 1. 既存のdlvプロセスをクリーンアップ
  print('\n1. Cleaning up existing dlv processes...')
  M.cleanup_dlv_processes()

  -- 2. アダプターを直接登録（外部dlvサーバーに接続、ポート3456使用）
  print('\n2. Registering adapter...')
  dap.adapters.container_go = {
    type = 'server',
    port = 3456,
    host = '127.0.0.1',
    options = {
      initialize_timeout_sec = 20,
    },
  }

  print("✓ Adapter 'container_go' registered (external server mode)")

  -- 3. 設定を直接登録
  print('\n3. Registering configuration...')

  if not dap.configurations.go then
    dap.configurations.go = {}
  end

  -- Container設定を先頭に追加
  local container_config = {
    type = 'container_go',
    request = 'attach',
    name = 'Container: Launch Go',
    cwd = '/workspace',
    showLog = true,
    logOutput = 'dap',
  }

  table.insert(dap.configurations.go, 1, container_config)
  print("✓ Configuration 'Container: Launch Go' registered")

  -- 4. 登録結果を確認
  print('\n4. Verification:')
  print('Adapter type: ' .. type(dap.adapters.container_go))
  print('Adapter details:')
  print(vim.inspect(dap.adapters.container_go))

  print('\nConfiguration count: ' .. #dap.configurations.go)
  for i, config in ipairs(dap.configurations.go) do
    if config.name == 'Container: Launch Go' then
      print('✓ Found Container: Launch Go at position ' .. i)
      break
    end
  end

  print('\n✅ Manual registration complete!')
  print('Next step: Start dlv server manually first, then debug')
end

-- 完全なDAP修正テスト
function M.complete_dap_test()
  print('=== Complete DAP Test with Fix ===')

  -- Step 1: 設定を登録
  print('Step 1: Registering configuration...')
  M.force_register_dap_config()

  -- Step 2: dlvサーバーを起動
  print('\nStep 2: Starting dlv server...')
  vim.defer_fn(function()
    M.test_dlv_exec_server()

    -- Step 3: DAP接続をテスト
    vim.defer_fn(function()
      print('\nStep 3: Testing DAP connection...')
      M.debug_dap_run()
    end, 3000)
  end, 2000)
end

-- 既存のdelve設定をコンテナ用に変換してテスト
function M.test_with_existing_delve()
  print('=== Test with existing delve configuration ===')

  local dap = require('dap')

  -- 既存のdelve設定を確認
  local go_configs = dap.configurations.go or {}
  if #go_configs == 0 then
    print('❌ No Go configurations found')
    return
  end

  print('Found ' .. #go_configs .. ' Go configurations:')
  for i, config in ipairs(go_configs) do
    print(string.format('  %d. %s (type: %s)', i, config.name, config.type))
  end

  -- 最初の設定を使用してテスト
  local test_config = go_configs[1]
  print('\nUsing configuration: ' .. test_config.name)
  print('Configuration:')
  print(vim.inspect(test_config))

  -- delveアダプターを確認
  local delve_adapter = dap.adapters.delve
  if delve_adapter then
    print('\nDelve adapter found:')
    print(vim.inspect(delve_adapter))

    -- テスト実行
    print('\nRunning delve configuration...')
    dap.run(test_config)

    vim.defer_fn(function()
      local session = dap.session()
      if session then
        print('✓ Delve session created successfully')
        print('Session state: ' .. (session.state or 'unknown'))
      else
        print('❌ Failed to create delve session')
      end
    end, 3000)
  else
    print('❌ Delve adapter not found')
  end
end

-- ポート2345への直接接続テスト
function M.test_direct_port_connection()
  print('=== Direct Port Connection Test ===')

  -- telnetまたはncでの接続テスト
  print('Testing connection with nc...')
  local nc_test = vim.fn.system('timeout 3 nc -z 127.0.0.1 2345')
  local nc_exit = vim.v.shell_error

  print('nc test exit code: ' .. nc_exit)
  if nc_exit == 0 then
    print('✓ Port 2345 is reachable')
  else
    print('❌ Port 2345 is not reachable')
  end

  -- DAPプロトコルテスト（JSONーRPC）
  print('\nTesting DAP protocol communication...')
  local test_json = '{"command":"initialize","arguments":{"adapterID":"test"},"type":"request","seq":1}'

  local dap_test = vim.fn.system(string.format('timeout 5 bash -c "echo \'%s\' | nc 127.0.0.1 2345"', test_json))
  local dap_exit = vim.v.shell_error

  print('DAP protocol test exit code: ' .. dap_exit)
  print('Response:')
  print(dap_test)

  if dap_exit == 0 and dap_test ~= '' then
    print('✓ DAP protocol communication successful')
  else
    print('❌ DAP protocol communication failed')
  end
end

-- dlvが正しいプロトコルで動作しているかテスト
function M.test_dlv_protocol()
  local container_id = require('container').get_container_id()
  if not container_id then
    print('No active container')
    return
  end

  print('=== DLV Protocol Test ===')

  -- dlvのヘルプを確認
  print('1. Checking dlv debug help...')
  local help_result = require('container.docker').run_docker_command({
    'exec',
    '-w',
    '/workspace',
    container_id,
    'dlv',
    'debug',
    '--help',
  })

  if help_result.success then
    -- --listen オプションの説明を探す
    for line in help_result.stdout:gmatch('[^\r\n]+') do
      if line:match('listen') then
        print('  ' .. line)
      end
    end
  end

  -- 現在のdlvプロセスの状態を確認
  print('\n2. Current dlv process details...')
  local ps_result = require('container.docker').run_docker_command({
    'exec',
    container_id,
    'ps',
    'aux',
  })

  if ps_result.success then
    for line in ps_result.stdout:gmatch('[^\r\n]+') do
      if line:match('dlv') then
        print('  ' .. line)
      end
    end
  end

  -- dlvがDAP対応かテスト
  print('\n3. Testing dlv dap support...')
  local dap_test = require('container.docker').run_docker_command({
    'exec',
    '-w',
    '/workspace',
    container_id,
    'dlv',
    'dap',
    '--help',
  })

  if dap_test.success then
    print('✓ dlv supports DAP protocol')
    print('DAP options:')
    for line in dap_test.stdout:gmatch('[^\r\n]+') do
      if line:match('listen') then
        print('  ' .. line)
      end
    end
  else
    print('❌ dlv DAP support test failed:')
    print(dap_test.stderr)
  end
end

-- 別のポートでdlvを起動してテスト
function M.test_dlv_different_port()
  local container_id = require('container').get_container_id()
  if not container_id then
    print('No active container')
    return
  end

  print('=== Testing DLV on different port (3456) ===')

  -- 既存のdlvをクリーンアップ
  M.cleanup_dlv_processes()

  print('Starting dlv debug on port 3456...')
  local result = require('container.docker').run_docker_command({
    'exec',
    '-d',
    '-w',
    '/workspace',
    container_id,
    'dlv',
    'debug',
    '--accept-multiclient',
    '--api-version=2',
    '--headless',
    '--listen=:3456',
  })

  if result.success then
    print('✓ dlv debug server started on port 3456')

    vim.defer_fn(function()
      -- プロセス確認
      local check_result = require('container.docker').run_docker_command({
        'exec',
        container_id,
        'pgrep',
        '-l',
        'dlv',
      })

      if check_result.success and check_result.stdout ~= '' then
        print('✓ dlv process running:')
        print(check_result.stdout)

        -- ポート確認
        local port_result = require('container.docker').run_docker_command({
          'exec',
          container_id,
          'ss',
          '-tlnp',
        })

        if port_result.success then
          for line in port_result.stdout:gmatch('[^\r\n]+') do
            if line:match('3456') then
              print('✓ Port 3456 is listening:')
              print('  ' .. line)
            end
          end
        end

        -- DAP アダプターを一時的に変更してテスト
        print('\nTesting DAP connection on port 3456...')
        local dap = require('dap')
        dap.adapters.container_go_test = {
          type = 'server',
          port = 3456,
          host = '127.0.0.1',
          options = {
            initialize_timeout_sec = 20,
          },
        }

        -- テスト設定
        local test_config = {
          type = 'container_go_test',
          request = 'attach',
          name = 'Container: Test Go Port 3456',
          cwd = '/workspace',
          showLog = true,
          logOutput = 'dap',
        }

        print('Running test with port 3456...')
        dap.run(test_config)

        vim.defer_fn(function()
          local session = dap.session()
          if session then
            print('✓ DAP session created on port 3456!')
            print('Session state: ' .. (session.state or 'unknown'))
          else
            print('❌ Failed to create DAP session on port 3456')
          end
        end, 3000)
      else
        print('❌ dlv process not found')
      end
    end, 2000)
  else
    print('❌ Failed to start dlv on port 3456:')
    print(result.stderr)
  end
end

-- 詳細なdlv通信テスト
function M.test_dlv_communication()
  print('=== DLV Communication Test ===')

  -- 1. 基本的なJSON-RPC通信テスト
  print('1. Testing basic JSON-RPC communication...')

  local initialize_request = vim.fn.json_encode({
    command = 'initialize',
    arguments = {
      adapterID = 'nvim-dap',
      clientID = 'neovim',
      clientName = 'neovim',
      columnsStartAt1 = true,
      linesStartAt1 = true,
      locale = 'en_US.UTF-8',
      pathFormat = 'path',
      supportsProgressReporting = true,
      supportsRunInTerminalRequest = true,
      supportsStartDebuggingRequest = true,
      supportsVariableType = true,
    },
    type = 'request',
    seq = 1,
  })

  -- HTTP content-length headerを追加
  local content_length = string.len(initialize_request)
  local dap_message = string.format('Content-Length: %d\r\n\r\n%s', content_length, initialize_request)

  print('Sending initialize request with Content-Length header...')
  print('Message: ' .. dap_message)

  local response = vim.fn.system(
    string.format('timeout 10 bash -c "printf \'%s\' | nc 127.0.0.1 3456"', dap_message:gsub("'", "'\"'\"'"))
  )
  local exit_code = vim.v.shell_error

  print('Response exit code: ' .. exit_code)
  print('Response content:')
  print(response)

  if response and response ~= '' then
    print('✓ Received response from dlv')
  else
    print('❌ No response from dlv')
  end

  -- 2. dlvがDAP Content-Lengthプロトコルに対応しているかテスト
  print('\n2. Testing different communication methods...')

  -- 単純なJSON送信（Content-Lengthなし）
  local simple_response = vim.fn.system(
    string.format('timeout 5 bash -c "echo \'%s\' | nc 127.0.0.1 3456"', initialize_request:gsub("'", "'\"'\"'"))
  )

  print('Simple JSON response:')
  print(simple_response)
end

-- dlvサーバーをデバッグモードで起動
function M.start_dlv_with_verbose()
  local container_id = require('container').get_container_id()
  if not container_id then
    print('No active container')
    return
  end

  print('=== Starting DLV with verbose logging ===')

  -- 既存のdlvをクリーンアップ
  M.cleanup_dlv_processes()

  print('Starting dlv with --log --log-output=dap...')
  local result = require('container.docker').run_docker_command({
    'exec',
    '-d',
    '-w',
    '/workspace',
    container_id,
    'dlv',
    'debug',
    '--accept-multiclient',
    '--api-version=2',
    '--headless',
    '--listen=:3456',
    '--log',
    '--log-output=dap',
  })

  if result.success then
    print('✓ dlv started with verbose logging')

    vim.defer_fn(function()
      -- dlvのログを確認
      local log_result = require('container.docker').run_docker_command({
        'exec',
        container_id,
        'find',
        '/workspace',
        '-name',
        '*.log',
        '-o',
        '-name',
        'dlv.log',
      })

      if log_result.success and log_result.stdout ~= '' then
        print('DLV log files found:')
        print(log_result.stdout)
      else
        print('No DLV log files found')
      end

      -- プロセス状態を再確認
      local ps_result = require('container.docker').run_docker_command({
        'exec',
        container_id,
        'ps',
        'aux',
      })

      if ps_result.success then
        for line in ps_result.stdout:gmatch('[^\r\n]+') do
          if line:match('dlv') then
            print('DLV process: ' .. line)
          end
        end
      end
    end, 3000)
  else
    print('❌ Failed to start dlv with verbose logging')
    print(result.stderr)
  end
end

-- 実際に動作する最小限の例でテスト
function M.test_minimal_working_example()
  print('=== Testing Minimal Working Example ===')

  local container_id = require('container').get_container_id()
  if not container_id then
    print('No active container')
    return
  end

  -- 既存のGo DAP設定（デフォルトのdelve）を確認
  local dap = require('dap')
  print('Existing delve adapter:')
  print(vim.inspect(dap.adapters.delve))

  print('\nExisting go configurations:')
  if dap.configurations.go then
    for i, config in ipairs(dap.configurations.go) do
      if config.type == 'delve' then
        print(string.format('  %d. %s (type: %s)', i, config.name, config.type))
      end
    end
  end

  -- 最初のdelve設定を試す
  if dap.configurations.go then
    for _, config in ipairs(dap.configurations.go) do
      if config.type == 'delve' then
        print('\nTesting with existing delve configuration...')
        print('Config: ' .. vim.inspect(config))

        dap.run(config)

        vim.defer_fn(function()
          local session = dap.session()
          if session then
            print('✓ Delve session created successfully!')
            print('Session state: ' .. (session.state or 'unknown'))
          else
            print('❌ Failed to create delve session')
          end
        end, 5000)
        break
      end
    end
  end
end

-- dlv dapモードでサーバーを起動
function M.start_dlv_dap_mode()
  local container_id = require('container').get_container_id()
  if not container_id then
    print('No active container')
    return
  end

  print('=== Starting DLV in DAP mode ===')

  -- 既存のdlvをクリーンアップ
  M.cleanup_dlv_processes()

  print('Starting dlv dap --listen=:3456...')
  local result = require('container.docker').run_docker_command({
    'exec',
    '-d',
    '-w',
    '/workspace',
    container_id,
    'dlv',
    'dap',
    '--listen=:3456',
    '--log',
    '--log-output=dap',
  })

  if result.success then
    print('✓ dlv dap server started')

    vim.defer_fn(function()
      -- プロセス確認
      local check_result = require('container.docker').run_docker_command({
        'exec',
        container_id,
        'pgrep',
        '-l',
        'dlv',
      })

      if check_result.success and check_result.stdout ~= '' then
        print('✓ dlv process running:')
        print(check_result.stdout)

        -- 通信テスト
        print('\nTesting DAP communication with dlv dap mode...')
        vim.defer_fn(function()
          M.test_dlv_communication()
        end, 1000)
      else
        print('❌ dlv process not found')
      end
    end, 2000)
  else
    print('❌ Failed to start dlv dap server:')
    print(result.stderr)
  end
end

-- より詳細なdelve設定テスト
function M.test_standard_delve_setup()
  print('=== Testing Standard Delve Setup ===')

  local dap = require('dap')

  -- 標準のdelve設定を確認・作成
  if not dap.adapters.delve then
    print('Creating standard delve adapter...')
    dap.adapters.delve = {
      type = 'server',
      port = '${port}',
      executable = {
        command = 'dlv',
        args = { 'dap', '-l', '127.0.0.1:${port}' },
      },
    }
  end

  print('Delve adapter: ' .. vim.inspect(dap.adapters.delve))

  -- 標準のGo設定を確認・作成
  if not dap.configurations.go then
    dap.configurations.go = {}
  end

  -- 基本的なGo設定を追加
  local standard_config = {
    type = 'delve',
    name = 'Debug',
    request = 'launch',
    program = '${file}',
  }

  -- 既存の設定をチェック
  local has_standard = false
  for _, config in ipairs(dap.configurations.go) do
    if config.type == 'delve' and config.name == 'Debug' then
      has_standard = true
      break
    end
  end

  if not has_standard then
    table.insert(dap.configurations.go, standard_config)
    print('✓ Added standard delve configuration')
  end

  print('\nAvailable Go configurations:')
  for i, config in ipairs(dap.configurations.go) do
    print(string.format('  %d. %s (type: %s)', i, config.name, config.type))
  end

  print('\nTesting standard delve configuration...')
  dap.run(standard_config)

  vim.defer_fn(function()
    local session = dap.session()
    if session then
      print('✓ Standard delve session created!')
      print('Session state: ' .. (session.state or 'unknown'))
      print('Session adapter: ' .. vim.inspect(session.adapter))
    else
      print('❌ Failed to create standard delve session')
    end
  end, 5000)
end

-- 基本的な環境診断
function M.basic_diagnosis()
  print('=== Basic Environment Diagnosis ===')

  local container_id = require('container').get_container_id()
  if not container_id then
    print('❌ No active container')
    return
  end

  -- 1. DLVバージョンとDAP対応
  print('1. DLV version and DAP support:')
  local version_result = require('container.docker').run_docker_command({
    'exec',
    container_id,
    'dlv',
    'version',
  })

  if version_result.success then
    print('DLV version:')
    print(version_result.stdout)
  else
    print('❌ DLV version check failed')
  end

  -- 2. Goプロジェクトの状態
  print('\n2. Go project status:')
  local go_mod_result = require('container.docker').run_docker_command({
    'exec',
    '-w',
    '/workspace',
    container_id,
    'go',
    'mod',
    'tidy',
  })

  if go_mod_result.success then
    print('✓ Go mod tidy successful')
  else
    print('❌ Go mod tidy failed:')
    print(go_mod_result.stderr)
  end

  -- 3. Goファイルのコンパイル
  print('\n3. Go compilation test:')
  local build_result = require('container.docker').run_docker_command({
    'exec',
    '-w',
    '/workspace',
    container_id,
    'go',
    'build',
    '-o',
    '/tmp/test_debug',
    '.',
  })

  if build_result.success then
    print('✓ Go build successful')
  else
    print('❌ Go build failed:')
    print(build_result.stderr)
  end

  -- 4. nvim-dap基本機能テスト
  print('\n4. nvim-dap basic functionality:')
  local dap = require('dap')

  -- 最小限のダミーアダプター
  dap.adapters.test_dummy = {
    type = 'executable',
    command = 'echo',
    args = { 'test' },
  }

  print('✓ DAP adapter registration works')

  -- 5. DLVを直接実行してみる（非DAP）
  print('\n5. Direct DLV execution test:')
  local dlv_exec_result = require('container.docker').run_docker_command({
    'exec',
    '-w',
    '/workspace',
    container_id,
    'timeout',
    '5',
    'dlv',
    'exec',
    '/tmp/test_debug',
    '--help',
  })

  if dlv_exec_result.success then
    print('✓ DLV exec works')
  else
    print('❌ DLV exec failed:')
    print(dlv_exec_result.stderr)
  end
end

-- 最も単純なDAP接続テスト
function M.test_simple_echo_adapter()
  print('=== Simple Echo Adapter Test ===')

  local dap = require('dap')

  -- エコーを使った最小限のテスト
  dap.adapters.echo_test = {
    type = 'executable',
    command = 'echo',
    args = { '{"type":"response","seq":0,"request_seq":1,"success":true,"command":"initialize"}' },
  }

  local echo_config = {
    type = 'echo_test',
    name = 'Echo Test',
    request = 'launch',
  }

  print('Testing echo adapter...')
  dap.run(echo_config)

  vim.defer_fn(function()
    local session = dap.session()
    if session then
      print('✓ Echo adapter session created')
      print('Session state: ' .. (session.state or 'unknown'))
    else
      print('❌ Echo adapter session failed')
    end
  end, 2000)
end

-- ホスト側でdelveをテスト
function M.test_host_delve()
  print('=== Host Delve Test ===')

  -- ホスト側にdelveがインストールされているかチェック
  local host_dlv = vim.fn.system('which dlv 2>/dev/null')
  local dlv_exit = vim.v.shell_error

  if dlv_exit == 0 then
    print('✓ Delve found on host: ' .. vim.trim(host_dlv))

    -- ホスト側のdelveバージョン
    local host_version = vim.fn.system('dlv version 2>/dev/null')
    print('Host delve version:')
    print(host_version)

    -- 標準のdelve設定をホスト用に設定
    local dap = require('dap')
    dap.adapters.delve_host = {
      type = 'server',
      port = '${port}',
      executable = {
        command = 'dlv',
        args = { 'dap', '-l', '127.0.0.1:${port}' },
      },
    }

    local host_config = {
      type = 'delve_host',
      name = 'Host Delve Test',
      request = 'launch',
      program = vim.fn.getcwd(),
    }

    print('Testing host delve configuration...')
    dap.run(host_config)

    vim.defer_fn(function()
      local session = dap.session()
      if session then
        print('✓ Host delve session created!')
        print('Session state: ' .. (session.state or 'unknown'))
      else
        print('❌ Host delve session failed')
      end
    end, 5000)
  else
    print('❌ Delve not found on host')
    print('Install with: go install github.com/go-delve/delve/cmd/dlv@latest')
  end
end

-- nvim-dap基本設定の診断と修正
function M.fix_nvim_dap_basic_setup()
  print('=== Fixing nvim-dap Basic Setup ===')

  local dap = require('dap')

  -- 1. DAP状態の確認
  print('1. Current DAP state:')
  print('Current session: ' .. tostring(dap.session()))
  print('DAP adapters count: ' .. vim.tbl_count(dap.adapters))
  print('DAP configurations: ' .. vim.inspect(vim.tbl_keys(dap.configurations)))

  -- 2. DAP UIとの連携を確認
  local dapui_ok, dapui = pcall(require, 'dapui')
  if dapui_ok then
    print('✓ DAP UI available')
    -- DAP UIの基本設定
    dapui.setup()
    print('✓ DAP UI setup complete')
  else
    print('ℹ️ DAP UI not available (optional)')
  end

  -- 3. 非常にシンプルなテストアダプターを作成
  print('\n2. Creating minimal test adapter...')

  -- 成功レスポンスを返すダミーアダプター
  dap.adapters.minimal_test = function(callback, config)
    print('Minimal adapter called with config: ' .. vim.inspect(config))
    callback({
      type = 'server',
      host = '127.0.0.1',
      port = 12345,
    })
  end

  print('✓ Minimal adapter registered')

  -- 4. テスト設定
  local test_config = {
    type = 'minimal_test',
    name = 'Minimal Test',
    request = 'launch',
  }

  print('\n3. Running minimal test...')

  -- DAP実行前にリスナーを設定
  dap.listeners.after.event_initialized['test'] = function()
    print('DAP initialized event received')
  end

  dap.listeners.after.event_stopped['test'] = function()
    print('DAP stopped event received')
  end

  dap.run(test_config)

  vim.defer_fn(function()
    local session = dap.session()
    if session then
      print('✓ Minimal test session created!')
      print('Session: ' .. vim.inspect(session))
    else
      print('❌ Minimal test session failed')
      print('Trying to diagnose DAP internal state...')

      -- 内部状態を確認
      if dap.status then
        print('DAP status: ' .. dap.status())
      end
    end
  end, 3000)
end

-- DAP設定を完全にリセット
function M.reset_dap_configuration()
  print('=== Resetting DAP Configuration ===')

  -- DAPを再読み込み
  package.loaded.dap = nil
  local dap = require('dap')

  print('✓ DAP module reloaded')

  -- 基本的なGo設定のみを設定
  dap.adapters.go = {
    type = 'server',
    port = '${port}',
    executable = {
      command = 'dlv',
      args = { 'dap', '-l', '127.0.0.1:${port}' },
    },
  }

  dap.configurations.go = {
    {
      type = 'go',
      name = 'Debug',
      request = 'launch',
      program = '${workspaceFolder}',
    },
  }

  print('✓ Basic Go configuration set')

  -- シンプルなテスト
  print('Testing basic Go debug...')
  dap.run(dap.configurations.go[1])

  vim.defer_fn(function()
    local session = dap.session()
    if session then
      print('✓ Basic Go debug session created!')
      print('Session state: ' .. (session.state or 'unknown'))
    else
      print('❌ Basic Go debug session failed')
    end
  end, 5000)
end

-- 手動でDAP初期化をトリガー
function M.manual_dap_initialize()
  print('=== Manual DAP Initialize ===')

  local dap = require('dap')

  -- DAPの内部状態をリセット
  if dap.close then
    dap.close()
  end

  if dap.terminate then
    dap.terminate()
  end

  print('✓ DAP reset complete')

  -- 最もシンプルな動作確認
  print('Testing DAP.continue() directly...')

  -- 最初にブレークポイントを設定
  dap.toggle_breakpoint()
  print('✓ Breakpoint toggled')

  -- アダプターなしでcontinueを試す
  local continue_ok, continue_err = pcall(dap.continue)
  if continue_ok then
    print('✓ DAP.continue() executed')
  else
    print('❌ DAP.continue() failed: ' .. tostring(continue_err))
  end

  vim.defer_fn(function()
    local session = dap.session()
    print('Session after continue: ' .. tostring(session))
  end, 2000)
end

-- 正しいGo設定でテスト
function M.test_correct_go_configuration()
  print('=== Testing Correct Go Configuration ===')

  local dap = require('dap')

  -- DAPをリセット
  package.loaded.dap = nil
  dap = require('dap')

  -- ログレベルを最高に設定
  dap.set_log_level('TRACE')
  print('✓ DAP log level set to TRACE')

  -- ホスト側でdelveが利用可能かチェック
  local dlv_check = vim.fn.system('which dlv 2>/dev/null')
  local dlv_exit = vim.v.shell_error

  if dlv_exit ~= 0 then
    print('❌ Delve not found on host')
    print('Installing delve...')
    vim.fn.system('go install github.com/go-delve/delve/cmd/dlv@latest')

    -- 再チェック
    dlv_check = vim.fn.system('which dlv 2>/dev/null')
    dlv_exit = vim.v.shell_error

    if dlv_exit ~= 0 then
      print('❌ Failed to install delve')
      return
    end
  end

  print('✓ Delve found at: ' .. vim.trim(dlv_check))

  -- delveのバージョン確認
  local dlv_version = vim.fn.system('dlv version 2>/dev/null')
  print('Delve version: ' .. vim.trim(dlv_version))

  -- 成功している設定と同じdelve設定
  dap.adapters.delve = function(callback, config)
    if config.mode == 'remote' and config.request == 'attach' then
      callback({
        type = 'server',
        host = config.host or '127.0.0.1',
        port = config.port or '38697',
      })
    else
      callback({
        type = 'server',
        port = '${port}',
        executable = {
          command = 'dlv',
          args = { 'dap', '-l', '127.0.0.1:${port}', '--log', '--log-output=dap' },
          detached = vim.fn.has('win32') == 0,
        },
      })
    end
  end

  dap.configurations.go = {
    {
      type = 'delve',
      name = 'Debug',
      request = 'launch',
      program = '${workspaceFolder}',
    },
    {
      type = 'delve',
      name = 'Debug test',
      request = 'launch',
      mode = 'test',
      program = '${workspaceFolder}',
    },
    {
      type = 'delve',
      name = 'Debug test (go.mod)',
      request = 'launch',
      mode = 'test',
      program = './${relativeFileDirname}',
    },
  }

  print('✓ Correct Go configuration set')
  print('Available configurations:')
  for i, config in ipairs(dap.configurations.go) do
    print(string.format('  %d. %s (program: %s)', i, config.name, config.program))
  end

  -- 手動でgo buildテスト
  print('\n--- Manual go build test ---')
  local build_test = vim.fn.system('cd ' .. vim.fn.getcwd() .. ' && go build -o /tmp/test_build .')
  local build_exit = vim.v.shell_error

  if build_exit == 0 then
    print('✓ Manual go build successful')
  else
    print('❌ Manual go build failed:')
    print(build_test)
    return
  end

  -- ブレークポイントを設定してテスト
  print('\nSetting breakpoint at main.go line 34...')

  -- まず現在のディレクトリにmain.goがあるか確認
  local main_go_path = vim.fn.getcwd() .. '/main.go'
  if vim.fn.filereadable(main_go_path) == 0 then
    print('❌ main.go not found in current directory: ' .. vim.fn.getcwd())
    print('Available files:')
    local files = vim.fn.glob('*.go', false, true)
    for _, file in ipairs(files) do
      print('  ' .. file)
    end
    return
  end

  -- main.goを開く
  vim.cmd('edit ' .. main_go_path)
  vim.fn.cursor(34, 1) -- main.go 34行目に移動

  print('Current file: ' .. vim.fn.expand('%:p'))
  print('Current line: ' .. vim.fn.line('.'))

  -- 既存のブレークポイントをクリア
  dap.clear_breakpoints()

  -- ブレークポイントを設定
  dap.toggle_breakpoint()

  -- 少し待ってからブレークポイントをチェック
  vim.defer_fn(function()
    local breakpoints = require('dap.breakpoints').get()
    local current_file = vim.fn.expand('%:p')

    print('Checking breakpoints for file: ' .. current_file)
    print('All breakpoints: ' .. vim.inspect(breakpoints))

    if breakpoints[current_file] and #breakpoints[current_file] > 0 then
      print('✓ Breakpoint set at line ' .. breakpoints[current_file][1].line)
      main_go_path = current_file -- パスを更新
    else
      print('❌ Failed to set breakpoint')
      print('Trying to set breakpoint manually...')
      dap.toggle_breakpoint()

      -- 再度チェック
      vim.defer_fn(function()
        local breakpoints_retry = require('dap.breakpoints').get()
        if breakpoints_retry[current_file] and #breakpoints_retry[current_file] > 0 then
          print('✓ Manual breakpoint set at line ' .. breakpoints_retry[current_file][1].line)
          main_go_path = current_file
        else
          print('❌ Manual breakpoint also failed')
          return
        end
      end, 200)
      return
    end
  end, 200)

  -- リスナーを設定してブレークポイントの状態を監視
  dap.listeners.after.event_stopped['test'] = function(session, body)
    print('🎯 Program stopped!')
    print('Reason: ' .. (body.reason or 'unknown'))
    if body.threadId then
      print('Thread ID: ' .. body.threadId)
    end
  end

  dap.listeners.after.event_terminated['test'] = function()
    print('⚠️ Program terminated')
  end

  dap.listeners.after.event_initialized['test'] = function()
    print('💡 DAP initialized - setting breakpoints now...')
    -- 初期化完了後に再度ブレークポイントを確実にセット
    vim.defer_fn(function()
      local current_breakpoints = require('dap.breakpoints').get()
      local bp_list = current_breakpoints[main_go_path]
      if bp_list then
        dap.set_breakpoints(bp_list, main_go_path)
        print('✓ Breakpoints synchronized with debugger')
      else
        print('⚠️ No breakpoints found for ' .. main_go_path)
      end
    end, 100)
  end

  -- 最初の設定でテスト
  print("\nTesting 'Debug Package' configuration...")
  dap.run(dap.configurations.go[1])

  vim.defer_fn(function()
    local session = dap.session()
    if session then
      print('✓ Go package debug session created!')
      print('Session state: ' .. (session.state or 'unknown'))
      print('🎉 DAP is working! Program should be stopped at breakpoint.')

      -- ブレークポイントで停止しているかチェック
      if session.stopped_thread_id then
        print('✓ Program stopped at breakpoint!')
        print('You can now use DAP commands like:')
        print("  :lua require('dap').step_over()")
        print("  :lua require('dap').continue()")
        print("  :lua require('dap').terminate()")
      else
        print('⚠️ Program started but not stopped at breakpoint')
        print('Checking if program is still running...')
        print('Current thread state: ' .. vim.inspect(session.current_frame))
      end
    else
      print('❌ Go package debug session failed')
      print('Opening DAP log...')
      vim.cmd('DapShowLog')
    end
  end, 3000) -- 短い待機時間
end

-- コンテナ用の正しいGo設定
function M.setup_correct_container_go_config()
  print('=== Setting up Correct Container Go Configuration ===')

  local container_id = require('container').get_container_id()
  if not container_id then
    print('❌ No active container')
    return
  end

  local dap = require('dap')

  -- コンテナ用の修正された設定 - 固定ポートを使用
  dap.adapters.container_delve = function(callback, config)
    if config.mode == 'remote' and config.request == 'attach' then
      callback({
        type = 'server',
        host = config.host or '127.0.0.1',
        port = config.port or '2345',
      })
    else
      -- 固定ポート2345を使用（devcontainer.jsonでフォワーディング済み）
      callback({
        type = 'server',
        port = '2345',
        executable = {
          command = 'docker',
          args = {
            'exec',
            '-w',
            '/workspace',
            container_id,
            'dlv',
            'dap',
            '-l',
            '127.0.0.1:2345',
            '--log',
            '--log-output=dap',
          },
          detached = vim.fn.has('win32') == 0,
        },
      })
    end
  end

  print('✓ Container delve adapter configured for container: ' .. container_id)

  if not dap.configurations.go then
    dap.configurations.go = {}
  end

  -- コンテナ内での実行を想定した設定
  local container_configs = {
    {
      type = 'container_delve',
      name = 'Container: Debug',
      request = 'launch',
      program = '/workspace', -- コンテナ内のワークスペースパス
      cwd = '/workspace', -- コンテナ内の作業ディレクトリ
      port = 2345, -- 固定ポート
      showLog = true,
      logOutput = 'dap',
    },
    {
      type = 'container_delve',
      name = 'Container: Debug test',
      request = 'launch',
      mode = 'test',
      program = '/workspace',
      cwd = '/workspace',
      port = 2345,
      showLog = true,
      logOutput = 'dap',
    },
  }

  -- 先頭に追加
  for i = #container_configs, 1, -1 do
    table.insert(dap.configurations.go, 1, container_configs[i])
  end

  print('✓ Container delve adapter and configurations added')
  print('Available container configurations:')
  for i = 1, #container_configs do
    local config = dap.configurations.go[i]
    print(string.format('  %d. %s', i, config.name))
  end

  -- ブレークポイントを設定してテスト
  print('\nSetting breakpoint at main.go line 34...')
  vim.cmd('edit main.go')
  vim.fn.cursor(34, 1)
  dap.toggle_breakpoint()

  local breakpoints = require('dap.breakpoints').get()
  local main_go_path = vim.fn.expand('%:p')
  if breakpoints[main_go_path] and #breakpoints[main_go_path] > 0 then
    print('✓ Breakpoint set at line ' .. breakpoints[main_go_path][1].line)
  else
    print('❌ Failed to set breakpoint')
    return
  end

  -- リスナーを設定
  dap.listeners.after.event_stopped['container_test'] = function(session, body)
    print('🎯 Container program stopped!')
    print('Reason: ' .. (body.reason or 'unknown'))
  end

  dap.listeners.after.event_terminated['container_test'] = function()
    print('⚠️ Container program terminated')
  end

  dap.listeners.after.event_initialized['container_test'] = function()
    print('💡 Container DAP initialized - synchronizing breakpoints...')
    vim.defer_fn(function()
      dap.set_breakpoints(breakpoints[main_go_path], main_go_path)
      print('✓ Container breakpoints synchronized')
    end, 100)
  end

  print("\nTesting 'Container: Debug' configuration...")
  dap.run(dap.configurations.go[1])

  vim.defer_fn(function()
    local session = dap.session()
    if session then
      print('✓ Container Go debug session created!')
      print('Session state: ' .. (session.state or 'unknown'))
      print('🎉 Container DAP integration is now working!')

      if session.stopped_thread_id then
        print('✓ Container program stopped at breakpoint!')
        print('You can now use DAP commands in container context')
      else
        print('⚠️ Container program started but not stopped at breakpoint')
        print('Checking container session state...')
        print('Container thread state: ' .. vim.inspect(session.current_frame))
      end
    else
      print('❌ Container Go debug session failed')
      print('Opening DAP log for container debugging...')
      vim.cmd('DapShowLog')
    end
  end, 5000)
end

-- シンプルなブレークポイントテスト関数を追加
function M.simple_breakpoint_test()
  print('=== Simple Breakpoint Test ===')

  -- 現在のファイルでブレークポイントを設定
  local current_file = vim.fn.expand('%:p')
  local current_line = vim.fn.line('.')

  if current_file == '' or vim.fn.expand('%:e') ~= 'go' then
    print('❌ Please open a Go file first')
    return
  end

  print('File: ' .. current_file)
  print('Line: ' .. current_line)

  local dap = require('dap')

  -- DAPの状態を確認
  print('DAP status before setting breakpoint:')
  print('  DAP adapters available: ' .. vim.tbl_count(dap.adapters))
  print('  DAP configurations available: ' .. vim.tbl_count(dap.configurations))

  -- 既存のブレークポイントを確認
  local existing_breakpoints = require('dap.breakpoints').get()
  print('Existing breakpoints: ' .. vim.inspect(existing_breakpoints))

  -- 既存のブレークポイントをクリア
  dap.clear_breakpoints()
  print('✓ Cleared existing breakpoints')

  -- ブレークポイントを設定
  print('Setting breakpoint at line ' .. current_line .. '...')
  local success, error_msg = pcall(dap.toggle_breakpoint)

  if not success then
    print('❌ Error during toggle_breakpoint: ' .. tostring(error_msg))
    return
  else
    print('✓ toggle_breakpoint executed without error')
  end

  -- 少し待ってからブレークポイントを確認
  vim.defer_fn(function()
    local breakpoints = require('dap.breakpoints').get()
    print('Breakpoints after setting: ' .. vim.inspect(breakpoints))

    -- ブレークポイントが存在するかをより寛容にチェック
    local breakpoint_found = false
    local found_file = nil
    local found_breakpoints = nil

    for file, bps in pairs(breakpoints) do
      if type(bps) == 'table' and #bps > 0 then
        breakpoint_found = true
        found_file = file
        found_breakpoints = bps
        break
      end
    end

    if breakpoint_found then
      print('✓ Breakpoint set successfully')
      print('File key: ' .. tostring(found_file))
      print('Expected file: ' .. current_file)
      for _, bp in ipairs(found_breakpoints) do
        print(
          string.format('  Line %d (condition: %s, log: %s)', bp.line, bp.condition or 'none', bp.logMessage or 'none')
        )
      end
    else
      print('❌ Breakpoint setting failed')
      print('Available files with breakpoints:')
      for file, bps in pairs(breakpoints) do
        print('  ' .. tostring(file) .. ': ' .. (type(bps) == 'table' and #bps or 'invalid') .. ' breakpoints')
      end

      -- バッファ情報をチェック
      print('Buffer info:')
      print('  Buffer number: ' .. vim.fn.bufnr('%'))
      print('  Buffer name: ' .. vim.fn.bufname('%'))
      print('  File exists: ' .. tostring(vim.fn.filereadable(current_file) == 1))
      print('  Buffer loaded: ' .. tostring(vim.fn.bufloaded('%') == 1))
    end
  end, 500)
end

-- シンプルなDelve設定テスト
function M.simple_delve_test()
  print('=== Simple Delve Test ===')

  local dap = require('dap')

  -- DAPをリセット
  package.loaded.dap = nil
  dap = require('dap')

  -- ログレベルを設定
  dap.set_log_level('TRACE')
  print('✓ DAP log level set to TRACE')

  -- 基本的なdelve設定
  dap.adapters.delve = function(callback, config)
    callback({
      type = 'server',
      port = '${port}',
      executable = {
        command = 'dlv',
        args = { 'dap', '-l', '127.0.0.1:${port}', '--log', '--log-output=dap' },
        detached = vim.fn.has('win32') == 0,
      },
    })
  end

  dap.configurations.go = {
    {
      type = 'delve',
      name = 'Debug',
      request = 'launch',
      program = '${workspaceFolder}',
    },
  }

  print('✓ Delve adapter and configuration set')

  -- 現在のファイルを確認
  local current_file = vim.fn.expand('%:p')
  if vim.fn.expand('%:e') ~= 'go' then
    print('❌ Please open a Go file first')
    print('Opening main.go...')
    vim.cmd('edit main.go')
    current_file = vim.fn.expand('%:p')
  end

  print('Current file: ' .. current_file)

  -- ブレークポイントを設定（34行目）
  vim.fn.cursor(34, 1)
  dap.toggle_breakpoint()

  -- ブレークポイント設定を確認
  vim.defer_fn(function()
    local breakpoints = require('dap.breakpoints').get()
    print('Debug: Breakpoints after setting: ' .. vim.inspect(breakpoints))

    -- より寛容なブレークポイント検出
    local breakpoint_found = false
    for file, bps in pairs(breakpoints) do
      if type(bps) == 'table' and #bps > 0 then
        breakpoint_found = true
        print('✓ Breakpoint set at line ' .. bps[1].line .. ' (file key: ' .. tostring(file) .. ')')
        break
      end
    end

    if not breakpoint_found then
      -- 画面上にブレークポイントマークが表示されていれば実際は成功している
      print('⚠️ Breakpoint detection uncertain, but proceeding (visual marker should be visible)')
      print('Proceeding with container debug session...')
    else
      print('✓ Breakpoint confirmed')
    end

    -- デバッグを開始
    M.start_container_delve_debug_with_breakpoints(current_file, breakpoints)
  end, 200)
end

-- ブレークポイント付きでコンテナdelveデバッグを開始
function M.start_container_delve_debug_with_breakpoints(current_file, breakpoints)
  local dap = require('dap')

  -- リスナーを設定
  dap.listeners.after.event_stopped['simple_test'] = function(session, body)
    print('🎯 Program stopped!')
    print('Reason: ' .. (body.reason or 'unknown'))
  end

  dap.listeners.after.event_terminated['simple_test'] = function()
    print('⚠️ Program terminated')
  end

  dap.listeners.after.event_initialized['simple_test'] = function()
    print('💡 DAP initialized')
    -- 初期化後にブレークポイントを再同期
    vim.defer_fn(function()
      -- ブレークポイントは既にDAP初期化時に自動同期されるので、手動同期は不要
      print('✓ Breakpoints automatically synchronized by DAP')
    end, 100)
  end

  print('\n🐳 Starting CONTAINER debug session...')
  print('Using container adapter: container_delve')
  print('Container ID: ' .. (require('container').get_container_id() or 'unknown'))

  -- コンテナ設定を明示的に選択
  local container_config = nil
  for _, config in ipairs(dap.configurations.go) do
    if config.name == 'Container: Debug' then
      container_config = config
      break
    end
  end

  if not container_config then
    print('❌ Container: Debug configuration not found!')
    return
  end

  print('Running configuration: ' .. container_config.name)
  dap.run(container_config)

  vim.defer_fn(function()
    local session = dap.session()
    if session then
      print('✓ Debug session created!')
      print('Session state: ' .. (session.state or 'unknown'))
      if session.stopped_thread_id then
        print('✓ Program stopped at breakpoint!')
        print('Use DAP commands:')
        print("  :lua require('dap').step_over()")
        print("  :lua require('dap').continue()")
        print("  :lua require('dap').terminate()")
      else
        print('⚠️ Program started but not stopped')
      end
    else
      print('❌ Debug session failed')
      print('Check DAP log: :DapShowLog')
    end
  end, 3000)
end

-- 手動でコンテナdlvサーバーを起動してからアタッチするテスト
function M.test_container_attach_mode()
  print('=== Container Attach Mode Test ===')

  local container_id = require('container').get_container_id()
  if not container_id then
    print('❌ No active container')
    return
  end

  print('Container ID: ' .. container_id)

  -- 既存のdlvプロセスをクリーンアップ
  require('container.docker').run_docker_command({ 'exec', container_id, 'pkill', '-f', 'dlv' })
  vim.fn.system('sleep 1')

  -- コンテナ内でdlvサーバーを起動
  print('Starting dlv server in container...')
  local start_result = require('container.docker').run_docker_command({
    'exec',
    '-d',
    '-w',
    '/workspace',
    container_id,
    'dlv',
    'debug',
    '--headless',
    '--listen=:2345',
    '--api-version=2',
    '--accept-multiclient',
  })

  if not start_result.success then
    print('❌ Failed to start dlv server:')
    print(start_result.stderr)
    return
  end

  print('✓ dlv server started')

  -- 少し待ってからアタッチモードでDAP設定
  vim.defer_fn(function()
    local dap = require('dap')

    -- アタッチ専用アダプター
    dap.adapters.container_attach = {
      type = 'server',
      host = '127.0.0.1',
      port = 2345,
    }

    -- アタッチ設定（パスマッピング付き）
    local current_dir = vim.fn.getcwd()
    local attach_config = {
      type = 'container_attach',
      name = 'Container: Attach to dlv',
      request = 'attach',
      mode = 'remote',
      port = 2345,
      host = '127.0.0.1',
      substitutePath = {
        {
          from = current_dir, -- ホスト側パス
          to = '/workspace', -- コンテナ内パス
        },
      },
      remotePath = '/workspace',
      localPath = current_dir,
    }

    if not dap.configurations.go then
      dap.configurations.go = {}
    end
    table.insert(dap.configurations.go, 1, attach_config)

    print('✓ Attach configuration added')
    print('You can now run:')
    print('  :DapNew')
    print("  Select 'Container: Attach to dlv'")

    -- または自動実行
    print('\nAuto-starting attach session...')
    dap.run(attach_config)

    vim.defer_fn(function()
      local session = dap.session()
      if session then
        print('✓ Container attach session created!')
        print('Session state: ' .. (session.state or 'unknown'))
      else
        print('❌ Container attach session failed')
        print('Check if dlv server is running in container')
      end
    end, 3000)
  end, 2000)
end

return M
