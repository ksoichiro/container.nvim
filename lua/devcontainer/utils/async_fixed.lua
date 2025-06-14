-- lua/devcontainer/utils/async_fixed.lua
-- 修正された非同期処理ユーティリティ

local M = {}
local uv = vim.loop

-- プロセス実行の結果
local function create_result(code, stdout, stderr)
  return {
    code = code,
    stdout = stdout or "",
    stderr = stderr or "",
    success = code == 0,
  }
end

-- 非同期でコマンドを実行
function M.run_command(cmd, args, opts, callback)
  opts = opts or {}
  args = args or {}
  
  local stdout_chunks = {}
  local stderr_chunks = {}
  
  -- stdoutハンドル
  local stdout = uv.new_pipe(false)
  -- stderrハンドル  
  local stderr = uv.new_pipe(false)
  
  local handle
  local function on_exit(code, signal)
    -- パイプとハンドルをクリーンアップ
    if stdout and not stdout:is_closing() then
      stdout:close()
    end
    if stderr and not stderr:is_closing() then
      stderr:close()
    end
    if handle and not handle:is_closing() then
      handle:close()
    end
    
    local stdout_str = table.concat(stdout_chunks)
    local stderr_str = table.concat(stderr_chunks)
    local result = create_result(code, stdout_str, stderr_str)
    
    -- コールバックを必ず呼び出す
    if callback then
      vim.schedule(function()
        callback(result)
      end)
    end
  end
  
  -- stdoutデータ読み取り
  local function on_stdout_read(err, data)
    if err then
      -- エラー時も処理を継続
      return
    end
    if data then
      table.insert(stdout_chunks, data)
      if opts.on_stdout then
        vim.schedule(function()
          opts.on_stdout(data)
        end)
      end
    end
  end
  
  -- stderrデータ読み取り
  local function on_stderr_read(err, data)
    if err then
      -- エラー時も処理を継続
      return
    end
    if data then
      table.insert(stderr_chunks, data)
      if opts.on_stderr then
        vim.schedule(function()
          opts.on_stderr(data)
        end)
      end
    end
  end
  
  -- プロセス開始
  handle = uv.spawn(cmd, {
    args = args,
    cwd = opts.cwd,
    env = opts.env,
    stdio = { nil, stdout, stderr },
  }, on_exit)
  
  if not handle then
    -- スポーンに失敗した場合
    if stdout then stdout:close() end
    if stderr then stderr:close() end
    
    if callback then
      vim.schedule(function()
        callback(create_result(-1, "", "Failed to spawn process: " .. cmd))
      end)
    end
    return nil
  end
  
  -- stdout読み取り開始
  stdout:read_start(on_stdout_read)
  -- stderr読み取り開始
  stderr:read_start(on_stderr_read)
  
  return handle
end

-- 同期的にコマンドを実行（内部では非同期）
function M.run_command_sync(cmd, args, opts)
  local co = coroutine.running()
  if not co then
    error("run_command_sync must be called from within a coroutine")
  end
  
  local result = nil
  M.run_command(cmd, args, opts, function(res)
    result = res
    coroutine.resume(co)
  end)
  
  coroutine.yield()
  return result
end

-- タイマー
function M.delay(ms, callback)
  local timer = uv.new_timer()
  timer:start(ms, 0, function()
    timer:close()
    vim.schedule(callback)
  end)
  return timer
end

return M

