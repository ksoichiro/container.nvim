-- lua/devcontainer/utils/async_fixed.lua
-- Fixed asynchronous processing utilities

local M = {}
local uv = vim.loop

-- Process execution result
local function create_result(code, stdout, stderr)
  return {
    code = code,
    stdout = stdout or "",
    stderr = stderr or "",
    success = code == 0,
  }
end

-- Execute command asynchronously
function M.run_command(cmd, args, opts, callback)
  opts = opts or {}
  args = args or {}

  local stdout_chunks = {}
  local stderr_chunks = {}

  -- stdout handle
  local stdout = uv.new_pipe(false)
  -- stderr handle
  local stderr = uv.new_pipe(false)

  local handle
  local function on_exit(code, signal)
    -- Clean up pipes and handles
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

    -- Always call callback
    if callback then
      vim.schedule(function()
        callback(result)
      end)
    end
  end

  -- Read stdout data
  local function on_stdout_read(err, data)
    if err then
      -- Continue processing even on error
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

  -- Read stderr data
  local function on_stderr_read(err, data)
    if err then
      -- Continue processing even on error
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

  -- Start process
  handle = uv.spawn(cmd, {
    args = args,
    cwd = opts.cwd,
    env = opts.env,
    stdio = { nil, stdout, stderr },
  }, on_exit)

  if not handle then
    -- If spawn failed
    if stdout then stdout:close() end
    if stderr then stderr:close() end

    if callback then
      vim.schedule(function()
        callback(create_result(-1, "", "Failed to spawn process: " .. cmd))
      end)
    end
    return nil
  end

  -- Start reading stdout
  stdout:read_start(on_stdout_read)
  -- Start reading stderr
  stderr:read_start(on_stderr_read)

  return handle
end

-- Execute command synchronously (internally async)
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

-- Timer
function M.delay(ms, callback)
  local timer = uv.new_timer()
  timer:start(ms, 0, function()
    timer:close()
    vim.schedule(callback)
  end)
  return timer
end

return M

