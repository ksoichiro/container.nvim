-- lua/devcontainer/utils/log.lua
-- ログシステム

local M = {}

local log_levels = {
  DEBUG = 1,
  INFO = 2,
  WARN = 3,
  ERROR = 4,
}

local log_level_names = {
  [1] = "DEBUG",
  [2] = "INFO",
  [3] = "WARN",
  [4] = "ERROR",
}

-- デフォルト設定
M.config = {
  level = log_levels.INFO,
  file = nil, -- nil の場合はファイルログを無効
  console = true,
}

-- ログレベルの設定
function M.set_level(level)
  if type(level) == "string" then
    M.config.level = log_levels[level:upper()] or log_levels.INFO
  else
    M.config.level = level
  end
end

-- ログファイルの設定
function M.set_file(filepath)
  M.config.file = filepath
end

-- 内部ログ関数
local function log(level, msg, ...)
  if level < M.config.level then
    return
  end

  local timestamp = os.date("%Y-%m-%d %H:%M:%S")
  local level_name = log_level_names[level] or "UNKNOWN"
  local formatted_msg = string.format(msg, ...)
  local log_line = string.format("[%s] [%s] %s", timestamp, level_name, formatted_msg)

  -- コンソール出力
  if M.config.console then
    if level >= log_levels.ERROR then
      vim.notify(formatted_msg, vim.log.levels.ERROR, { title = "devcontainer.nvim" })
    elseif level >= log_levels.WARN then
      vim.notify(formatted_msg, vim.log.levels.WARN, { title = "devcontainer.nvim" })
    elseif level >= log_levels.INFO then
      vim.notify(formatted_msg, vim.log.levels.INFO, { title = "devcontainer.nvim" })
    else
      print(log_line)
    end
  end

  -- ファイル出力
  if M.config.file then
    local file = io.open(M.config.file, "a")
    if file then
      file:write(log_line .. "\n")
      file:close()
    end
  end
end

-- パブリック関数
function M.debug(msg, ...)
  log(log_levels.DEBUG, msg, ...)
end

function M.info(msg, ...)
  log(log_levels.INFO, msg, ...)
end

function M.warn(msg, ...)
  log(log_levels.WARN, msg, ...)
end

function M.error(msg, ...)
  log(log_levels.ERROR, msg, ...)
end

return M

