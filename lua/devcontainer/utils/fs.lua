-- lua/devcontainer/utils/fs.lua
-- ファイルシステムユーティリティ

local M = {}

-- パスの正規化
function M.normalize_path(path)
  if not path then
    return nil
  end
  
  -- Windows パスセパレータを Unix 形式に変換
  path = path:gsub("\\", "/")
  
  -- 先頭の ./ を削除
  path = path:gsub("^%./", "")
  
  -- 末尾のスラッシュを削除（ルートディレクトリ以外）
  if path ~= "/" then
    path = path:gsub("/$", "")
  end
  
  return path
end

-- パスの結合
function M.join_path(...)
  local parts = {}
  for _, part in ipairs({...}) do
    if part and part ~= "" then
      table.insert(parts, M.normalize_path(part))
    end
  end
  return table.concat(parts, "/")
end

-- 絶対パスかどうかを判定
function M.is_absolute_path(path)
  if not path then
    return false
  end
  return path:match("^/") ~= nil or path:match("^%a:") ~= nil
end

-- 相対パスを絶対パスに変換
function M.resolve_path(path, base_path)
  if M.is_absolute_path(path) then
    return M.normalize_path(path)
  end
  
  base_path = base_path or vim.fn.getcwd()
  return M.normalize_path(M.join_path(base_path, path))
end

-- ファイルの存在確認（同期）
function M.exists(path)
  if not path then
    return false
  end
  return vim.fn.filereadable(path) == 1 or vim.fn.isdirectory(path) == 1
end

-- ファイルかどうかを判定
function M.is_file(path)
  if not path then
    return false
  end
  return vim.fn.filereadable(path) == 1
end

-- ディレクトリかどうかを判定
function M.is_directory(path)
  if not path then
    return false
  end
  return vim.fn.isdirectory(path) == 1
end

-- ファイル読み取り（同期）
function M.read_file(path)
  if not M.is_file(path) then
    return nil, "File does not exist: " .. path
  end
  
  local file = io.open(path, "r")
  if not file then
    return nil, "Failed to open file: " .. path
  end
  
  local content = file:read("*all")
  file:close()
  return content
end

-- ファイル書き込み（同期）
function M.write_file(path, content)
  -- ディレクトリが存在しない場合は作成
  local dir = vim.fn.fnamemodify(path, ":h")
  if not M.is_directory(dir) then
    vim.fn.mkdir(dir, "p")
  end
  
  local file = io.open(path, "w")
  if not file then
    return false, "Failed to open file for writing: " .. path
  end
  
  file:write(content)
  file:close()
  return true
end

-- 上位ディレクトリを検索してファイルを見つける
function M.find_file_upward(start_path, filename)
  local current_path = M.resolve_path(start_path)
  
  while current_path and current_path ~= "/" do
    local target_path = M.join_path(current_path, filename)
    if M.exists(target_path) then
      return target_path
    end
    
    local parent = vim.fn.fnamemodify(current_path, ":h")
    if parent == current_path then
      break
    end
    current_path = parent
  end
  
  return nil
end

-- ディレクトリ内のファイルをリスト
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

-- 再帰的にディレクトリ内のファイルを検索
function M.find_files(path, pattern, max_depth)
  max_depth = max_depth or 10
  local results = {}
  
  local function search_recursive(current_path, depth)
    if depth > max_depth then
      return
    end
    
    local files = M.list_directory(current_path)
    for _, file in ipairs(files) do
      if file.type == "file" and (not pattern or file.name:match(pattern)) then
        table.insert(results, file.path)
      elseif file.type == "directory" then
        search_recursive(file.path, depth + 1)
      end
    end
  end
  
  if M.is_directory(path) then
    search_recursive(path, 1)
  end
  
  return results
end

-- ファイルサイズを取得
function M.get_file_size(path)
  if not M.is_file(path) then
    return nil
  end
  
  local stat = vim.loop.fs_stat(path)
  return stat and stat.size or nil
end

-- ファイルの更新時刻を取得
function M.get_mtime(path)
  if not M.exists(path) then
    return nil
  end
  
  local stat = vim.loop.fs_stat(path)
  return stat and stat.mtime.sec or nil
end

-- パスからファイル名を取得
function M.basename(path)
  if not path then
    return nil
  end
  return vim.fn.fnamemodify(path, ":t")
end

-- パスからディレクトリ名を取得
function M.dirname(path)
  if not path then
    return nil
  end
  return vim.fn.fnamemodify(path, ":h")
end

-- ファイル拡張子を取得
function M.extension(path)
  if not path then
    return nil
  end
  return vim.fn.fnamemodify(path, ":e")
end

-- ファイル名（拡張子なし）を取得
function M.stem(path)
  if not path then
    return nil
  end
  return vim.fn.fnamemodify(path, ":t:r")
end

-- 相対パスを計算
function M.relative_path(path, base)
  base = base or vim.fn.getcwd()
  path = M.resolve_path(path)
  base = M.resolve_path(base)
  
  -- 同じパスの場合
  if path == base then
    return "."
  end
  
  -- 単純なケース: baseがpathの親ディレクトリ
  if path:sub(1, #base + 1) == base .. "/" then
    return path:sub(#base + 2)
  end
  
  -- より複雑なケース: 共通の祖先を見つける
  local path_parts = vim.split(path, "/")
  local base_parts = vim.split(base, "/")
  
  local common_length = 0
  for i = 1, math.min(#path_parts, #base_parts) do
    if path_parts[i] == base_parts[i] then
      common_length = i
    else
      break
    end
  end
  
  local relative_parts = {}
  
  -- baseから共通祖先まで戻る
  for i = common_length + 1, #base_parts do
    table.insert(relative_parts, "..")
  end
  
  -- 共通祖先からpathまで進む
  for i = common_length + 1, #path_parts do
    table.insert(relative_parts, path_parts[i])
  end
  
  if #relative_parts == 0 then
    return "."
  end
  
  return table.concat(relative_parts, "/")
end

-- テンポラリディレクトリを取得
function M.get_temp_dir()
  return vim.fn.tempname():match("(.*)/[^/]*$") or "/tmp"
end

-- テンポラリファイルパスを生成
function M.temp_file(prefix, suffix)
  prefix = prefix or "devcontainer"
  suffix = suffix or ""
  return M.join_path(M.get_temp_dir(), prefix .. "_" .. os.time() .. suffix)
end

return M

