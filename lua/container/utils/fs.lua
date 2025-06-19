-- lua/devcontainer/utils/fs.lua
-- File system utilities

local M = {}

-- Path normalization
function M.normalize_path(path)
  if not path then
    return nil
  end

  -- Convert Windows path separators to Unix format
  path = path:gsub('\\', '/')

  -- Remove leading ./
  path = path:gsub('^%./', '')

  -- Remove trailing slash (except for root directory)
  if path ~= '/' then
    path = path:gsub('/$', '')
  end

  return path
end

-- Path joining
function M.join_path(...)
  local parts = {}
  for _, part in ipairs({ ... }) do
    if part and part ~= '' then
      table.insert(parts, M.normalize_path(part))
    end
  end
  return table.concat(parts, '/')
end

-- Check if path is absolute
function M.is_absolute_path(path)
  if not path then
    return false
  end
  return path:match('^/') ~= nil or path:match('^%a:') ~= nil
end

-- Convert relative path to absolute path
function M.resolve_path(path, base_path)
  if M.is_absolute_path(path) then
    return M.normalize_path(path)
  end

  base_path = base_path or vim.fn.getcwd()
  return M.normalize_path(M.join_path(base_path, path))
end

-- File existence check (sync)
function M.exists(path)
  if not path then
    return false
  end
  return vim.fn.filereadable(path) == 1 or vim.fn.isdirectory(path) == 1
end

-- Check if it's a file
function M.is_file(path)
  if not path then
    return false
  end
  return vim.fn.filereadable(path) == 1
end

-- Check if it's a directory
function M.is_directory(path)
  if not path then
    return false
  end
  return vim.fn.isdirectory(path) == 1
end

-- File reading (sync)
function M.read_file(path)
  if not M.is_file(path) then
    return nil, 'File does not exist: ' .. path
  end

  local file = io.open(path, 'r')
  if not file then
    return nil, 'Failed to open file: ' .. path
  end

  local content = file:read('*all')
  file:close()
  return content
end

-- Ensure directory exists (create if needed)
function M.ensure_directory(path)
  if not path then
    return false, 'No path provided'
  end

  if M.is_directory(path) then
    return true
  end

  local success = vim.fn.mkdir(path, 'p')
  if success == 0 then
    return false, 'Failed to create directory: ' .. path
  end

  return true
end

-- File writing (sync)
function M.write_file(path, content)
  -- Create directory if it doesn't exist
  local dir = vim.fn.fnamemodify(path, ':h')
  if not M.is_directory(dir) then
    vim.fn.mkdir(dir, 'p')
  end

  local file = io.open(path, 'w')
  if not file then
    return false, 'Failed to open file for writing: ' .. path
  end

  file:write(content)
  file:close()
  return true
end

-- Search upward directories to find file
function M.find_file_upward(start_path, filename)
  local current_path = M.resolve_path(start_path)

  while current_path and current_path ~= '/' do
    local target_path = M.join_path(current_path, filename)
    if M.exists(target_path) then
      return target_path
    end

    local parent = vim.fn.fnamemodify(current_path, ':h')
    if parent == current_path then
      break
    end
    current_path = parent
  end

  return nil
end

-- List files in directory
function M.list_directory(path, pattern)
  if not M.is_directory(path) then
    return {}
  end

  local files = {}
  local handle = vim.loop.fs_scandir(path)
  if handle then
    while true do
      local name, type = vim.loop.fs_scandir_next(handle)
      if not name then
        break
      end

      if not pattern or name:match(pattern) then
        table.insert(files, {
          name = name,
          path = M.join_path(path, name),
          type = type,
        })
      end
    end
  end

  return files
end

-- Recursively search files in directory
function M.find_files(path, pattern, max_depth)
  max_depth = max_depth or 10
  local results = {}

  local function search_recursive(current_path, depth)
    if depth > max_depth then
      return
    end

    local files = M.list_directory(current_path)
    for _, file in ipairs(files) do
      if file.type == 'file' and (not pattern or file.name:match(pattern)) then
        table.insert(results, file.path)
      elseif file.type == 'directory' then
        search_recursive(file.path, depth + 1)
      end
    end
  end

  if M.is_directory(path) then
    search_recursive(path, 1)
  end

  return results
end

-- Get file size
function M.get_file_size(path)
  if not M.is_file(path) then
    return nil
  end

  local stat = vim.loop.fs_stat(path)
  return stat and stat.size or nil
end

-- Get file modification time
function M.get_mtime(path)
  if not M.exists(path) then
    return nil
  end

  local stat = vim.loop.fs_stat(path)
  return stat and stat.mtime.sec or nil
end

-- Get filename from path
function M.basename(path)
  if not path then
    return nil
  end
  return vim.fn.fnamemodify(path, ':t')
end

-- Get directory name from path
function M.dirname(path)
  if not path then
    return nil
  end
  return vim.fn.fnamemodify(path, ':h')
end

-- Get file extension
function M.extension(path)
  if not path then
    return nil
  end
  return vim.fn.fnamemodify(path, ':e')
end

-- Get filename without extension
function M.stem(path)
  if not path then
    return nil
  end
  return vim.fn.fnamemodify(path, ':t:r')
end

-- Calculate relative path
function M.relative_path(path, base)
  base = base or vim.fn.getcwd()
  path = M.resolve_path(path)
  base = M.resolve_path(base)

  -- Same path case
  if path == base then
    return '.'
  end

  -- Simple case: base is parent directory of path
  if path:sub(1, #base + 1) == base .. '/' then
    return path:sub(#base + 2)
  end

  -- More complex case: find common ancestor
  local path_parts = vim.split(path, '/')
  local base_parts = vim.split(base, '/')

  local common_length = 0
  for i = 1, math.min(#path_parts, #base_parts) do
    if path_parts[i] == base_parts[i] then
      common_length = i
    else
      break
    end
  end

  local relative_parts = {}

  -- Go back from base to common ancestor
  for i = common_length + 1, #base_parts do
    table.insert(relative_parts, '..')
  end

  -- Go forward from common ancestor to path
  for i = common_length + 1, #path_parts do
    table.insert(relative_parts, path_parts[i])
  end

  if #relative_parts == 0 then
    return '.'
  end

  return table.concat(relative_parts, '/')
end

-- Get temporary directory
function M.get_temp_dir()
  return vim.fn.tempname():match('(.*)/[^/]*$') or '/tmp'
end

-- Generate temporary file path
function M.temp_file(prefix, suffix)
  prefix = prefix or 'container'
  suffix = suffix or ''
  return M.join_path(M.get_temp_dir(), prefix .. '_' .. os.time() .. suffix)
end

return M
