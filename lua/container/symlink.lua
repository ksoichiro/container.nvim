-- lua/container/symlink.lua
-- Strategy A: Symbolic link approach for path resolution
-- Creates symbolic links in container to map host paths to container paths

local M = {}
local log = require('container.utils.log')
local docker = require('container.docker.init')

-- Cache for created symlinks to avoid duplication
local created_symlinks = {}

-- Get the host workspace path from the current working directory
local function get_host_workspace_path()
  -- Get the path that's mounted as /workspace in container
  -- This is typically the directory containing .devcontainer
  local cwd = vim.fn.getcwd()

  log.debug('Symlink: Current working directory: %s', cwd)

  -- Look for .devcontainer directory to identify workspace root
  local workspace_root = vim.fn.finddir('.devcontainer', cwd .. ';')
  if workspace_root ~= '' then
    -- Remove .devcontainer from the path
    local host_workspace = vim.fn.fnamemodify(workspace_root, ':h')
    log.debug('Symlink: Found .devcontainer, using workspace: %s', host_workspace)
    return host_workspace
  end

  -- Fallback: use current working directory
  log.debug('Symlink: No .devcontainer found, using cwd: %s', cwd)
  return cwd
end

-- Create directory structure in container
local function create_directory_structure(container_id, host_path)
  local parent_dir = vim.fn.fnamemodify(host_path, ':h')

  if parent_dir == '/' or parent_dir == '' then
    return true
  end

  log.debug('Symlink: Creating directory structure for %s', parent_dir)

  local cmd = {
    'exec',
    container_id,
    'mkdir',
    '-p',
    parent_dir,
  }

  local result = docker.run_docker_command(cmd)
  if not result or not result.success then
    log.error('Symlink: Failed to create directory %s', parent_dir)
    return false
  end

  return true
end

-- Create symbolic link in container
local function create_symlink(container_id, host_path, target_path)
  -- Check if symlink already exists
  local cache_key = container_id .. ':' .. host_path
  if created_symlinks[cache_key] then
    log.debug('Symlink: Already exists %s -> %s', host_path, target_path)
    return true
  end

  log.info('Symlink: Creating %s -> %s', host_path, target_path)

  -- Create parent directory structure first
  if not create_directory_structure(container_id, host_path) then
    return false
  end

  -- Remove existing file/link if it exists
  local remove_cmd = {
    'exec',
    container_id,
    'rm',
    '-rf',
    host_path,
  }
  docker.run_docker_command(remove_cmd) -- Ignore errors

  -- Create symbolic link
  local link_cmd = {
    'exec',
    container_id,
    'ln',
    '-s',
    target_path,
    host_path,
  }

  local result = docker.run_docker_command(link_cmd)
  if not result or not result.success then
    log.error(
      'Symlink: Failed to create symlink %s -> %s: %s',
      host_path,
      target_path,
      result and result.stderr or 'unknown error'
    )
    return false
  end

  -- Cache successful creation
  created_symlinks[cache_key] = true
  log.info('Symlink: Successfully created %s -> %s', host_path, target_path)

  return true
end

-- Setup symbolic links for LSP path resolution
-- @param container_id string: Docker container ID
-- @return boolean: true if successful, false otherwise
function M.setup_lsp_symlinks(container_id)
  if not container_id or container_id == '' then
    log.error('Symlink: Container ID is required')
    return false
  end

  local host_workspace = get_host_workspace_path()
  local container_workspace = '/workspace'

  log.info('Symlink: Setting up LSP path resolution')
  log.info('Symlink: Host workspace: %s', host_workspace)
  log.info('Symlink: Container workspace: %s', container_workspace)

  -- Validate that we have a reasonable host workspace
  if not host_workspace or host_workspace == '' then
    log.error('Symlink: Could not determine host workspace path')
    return false
  end

  -- Create symlink from host path to container workspace
  local success = create_symlink(container_id, host_workspace, container_workspace)

  if success then
    log.info('Symlink: LSP path resolution setup completed')

    -- Emit event for other modules
    vim.api.nvim_exec_autocmds('User', {
      pattern = 'ContainerSymlinkCreated',
      data = {
        container_id = container_id,
        host_path = host_workspace,
        container_path = container_workspace,
      },
    })
  else
    log.error('Symlink: Failed to setup LSP path resolution')
  end

  return success
end

-- Verify that symlinks are working correctly
function M.verify_symlinks(container_id, host_path)
  if not container_id or not host_path then
    return false
  end

  log.debug('Symlink: Verifying %s in container %s', host_path, container_id)

  -- Test if the symlink resolves correctly
  local test_cmd = {
    'exec',
    container_id,
    'test',
    '-L',
    host_path,
  }

  local result = docker.run_docker_command(test_cmd)
  if not result or not result.success then
    log.warn('Symlink: %s is not a symbolic link or does not exist', host_path)
    return false
  end

  -- Check where the symlink points to
  local readlink_cmd = {
    'exec',
    container_id,
    'readlink',
    host_path,
  }

  local link_result = docker.run_docker_command(readlink_cmd)
  if link_result and link_result.success then
    local target = vim.trim(link_result.stdout)
    log.debug('Symlink: %s -> %s', host_path, target)
    return target == '/workspace'
  end

  return false
end

-- Clean up symlinks when container is stopped
function M.cleanup_symlinks(container_id)
  if not container_id then
    return
  end

  log.debug('Symlink: Cleaning up symlinks for container %s', container_id)

  -- Clear the cache for this container
  for key, _ in pairs(created_symlinks) do
    if key:match('^' .. vim.pesc(container_id) .. ':') then
      created_symlinks[key] = nil
    end
  end

  log.debug('Symlink: Cleanup completed')
end

-- Get current symlink status
function M.get_status()
  return {
    created_symlinks = vim.tbl_keys(created_symlinks),
    cache_size = vim.tbl_count(created_symlinks),
  }
end

return M
