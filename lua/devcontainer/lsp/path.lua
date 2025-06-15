local M = {}
local log = require('devcontainer.utils.log')

-- Path mapping state
local path_mappings = {
  workspace_folder = nil,
  container_workspace = nil,
  mounts = {},
}

-- Initialize path mappings
function M.setup(workspace_folder, container_workspace, mounts)
  path_mappings.workspace_folder = vim.fn.fnamemodify(workspace_folder or vim.fn.getcwd(), ':p')
  path_mappings.container_workspace = container_workspace or '/workspace'
  path_mappings.mounts = mounts or {}

  log.debug(
    'Path: Initialized mappings - Local: '
      .. path_mappings.workspace_folder
      .. ', Container: '
      .. path_mappings.container_workspace
  )
end

-- Convert local path to container path
function M.to_container_path(local_path)
  if not local_path then
    return nil
  end

  local abs_path = vim.fn.fnamemodify(local_path, ':p')

  -- Check if path is within workspace
  if vim.startswith(abs_path, path_mappings.workspace_folder) then
    local relative = string.sub(abs_path, #path_mappings.workspace_folder + 1)
    local container_path = path_mappings.container_workspace .. '/' .. relative
    container_path = container_path:gsub('/+', '/')
    log.debug('Path: Local to container - ' .. abs_path .. ' -> ' .. container_path)
    return container_path
  end

  -- Check custom mount points
  for local_mount, container_mount in pairs(path_mappings.mounts) do
    if vim.startswith(abs_path, local_mount) then
      local relative = string.sub(abs_path, #local_mount + 1)
      local container_path = container_mount .. '/' .. relative
      container_path = container_path:gsub('/+', '/')
      log.debug('Path: Local to container (mount) - ' .. abs_path .. ' -> ' .. container_path)
      return container_path
    end
  end

  -- Path is outside workspace, return as-is
  log.debug('Path: Local path outside workspace - ' .. abs_path)
  return abs_path
end

-- Get container workspace folder
function M.get_container_workspace()
  return path_mappings.container_workspace or '/workspace'
end

-- Get local workspace folder
function M.get_local_workspace()
  return path_mappings.workspace_folder or vim.fn.getcwd()
end

-- Convert container path to local path
function M.to_local_path(container_path)
  if not container_path then
    return nil
  end

  -- Check if path is within container workspace
  if vim.startswith(container_path, path_mappings.container_workspace) then
    local relative = string.sub(container_path, #path_mappings.container_workspace + 1)
    local local_path = path_mappings.workspace_folder .. '/' .. relative
    local_path = local_path:gsub('/+', '/')
    log.debug('Path: Container to local - ' .. container_path .. ' -> ' .. local_path)
    return local_path
  end

  -- Check custom mount points
  for local_mount, container_mount in pairs(path_mappings.mounts) do
    if vim.startswith(container_path, container_mount) then
      local relative = string.sub(container_path, #container_mount + 1)
      local local_path = local_mount .. '/' .. relative
      local_path = local_path:gsub('/+', '/')
      log.debug('Path: Container to local (mount) - ' .. container_path .. ' -> ' .. local_path)
      return local_path
    end
  end

  -- Path is outside mapped directories
  log.debug('Path: Container path outside mappings - ' .. container_path)
  return container_path
end

-- Convert file URI between local and container
function M.transform_uri(uri, direction)
  if not uri or not vim.startswith(uri, 'file://') then
    return uri
  end

  local path = vim.uri_to_fname(uri)
  local transformed_path

  if direction == 'to_container' then
    transformed_path = M.to_container_path(path)
  elseif direction == 'to_local' then
    transformed_path = M.to_local_path(path)
  else
    log.error('Path: Invalid direction - ' .. tostring(direction))
    return uri
  end

  if transformed_path then
    local new_uri = vim.uri_from_fname(transformed_path)
    log.debug('Path: URI transform - ' .. uri .. ' -> ' .. new_uri)
    return new_uri
  end

  return uri
end

-- Transform LSP request parameters
function M.transform_lsp_params(params, direction)
  if not params then
    return params
  end

  local transformed = vim.deepcopy(params)

  -- Transform textDocument.uri
  if transformed.textDocument and transformed.textDocument.uri then
    transformed.textDocument.uri = M.transform_uri(transformed.textDocument.uri, direction)
  end

  -- Transform rootUri
  if transformed.rootUri then
    transformed.rootUri = M.transform_uri(transformed.rootUri, direction)
  end

  -- Transform workspaceFolders
  if transformed.workspaceFolders then
    for i, folder in ipairs(transformed.workspaceFolders) do
      if folder.uri then
        transformed.workspaceFolders[i].uri = M.transform_uri(folder.uri, direction)
      end
    end
  end

  -- Transform location/locations in responses
  if transformed.location then
    transformed.location.uri = M.transform_uri(transformed.location.uri, direction)
  end

  if transformed.locations then
    for i, location in ipairs(transformed.locations) do
      transformed.locations[i].uri = M.transform_uri(location.uri, direction)
    end
  end

  -- Transform diagnostics
  if transformed.diagnostics then
    for i, diagnostic in ipairs(transformed.diagnostics) do
      if diagnostic.source then
        -- Keep source as-is
      end
      if diagnostic.relatedInformation then
        for j, info in ipairs(diagnostic.relatedInformation) do
          if info.location and info.location.uri then
            transformed.diagnostics[i].relatedInformation[j].location.uri =
              M.transform_uri(info.location.uri, direction)
          end
        end
      end
    end
  end

  return transformed
end

-- Get current path mappings
function M.get_mappings()
  return vim.deepcopy(path_mappings)
end

-- Add a custom mount mapping
function M.add_mount(local_path, container_path)
  local local_abs = vim.fn.fnamemodify(local_path, ':p')
  path_mappings.mounts[local_abs] = container_path
  log.info('Path: Added mount mapping - ' .. local_abs .. ' -> ' .. container_path)
end

return M
