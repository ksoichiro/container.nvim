-- lua/devcontainer/terminal/display.lua
-- Terminal display and positioning logic

local M = {}
local log = require('container.utils.log')

-- Create terminal buffer with specified positioning
function M.create_terminal_buffer(session, position, opts)
  opts = opts or {}

  local config = session.config
  local buf_id = nil
  local win_id = nil

  -- Determine positioning
  position = position or config.default_position or 'split'

  if position == 'split' then
    buf_id, win_id = M._create_split_terminal(session, opts)
  elseif position == 'tab' then
    buf_id, win_id = M._create_tab_terminal(session, opts)
  elseif position == 'float' then
    buf_id, win_id = M._create_float_terminal(session, opts)
  else
    return nil, nil, string.format('Unknown position: %s', position)
  end

  if not buf_id then
    return nil, nil, 'Failed to create terminal buffer'
  end

  -- Configure terminal buffer
  M._configure_terminal_buffer(buf_id, session)

  -- Set up keymaps
  M._setup_terminal_keymaps(buf_id, session)

  log.debug('Created terminal buffer for session %s (position: %s)', session.name, position)
  return buf_id, win_id, nil
end

-- Create split terminal (handles both horizontal and vertical)
function M._create_split_terminal(session, opts)
  local config = session.config

  -- Create buffer first
  local buf_id = vim.api.nvim_create_buf(false, true)

  -- Use split_command directly or fallback to default
  local cmd = config.split_command or 'belowright 15'

  -- If split_command doesn't include 'new', add it
  if not cmd:match('new$') then
    cmd = cmd .. ' new'
  end

  -- Execute split command
  vim.cmd(cmd)
  local win_id = vim.api.nvim_get_current_win()

  -- Set buffer to the new window
  vim.api.nvim_win_set_buf(win_id, buf_id)

  return buf_id, win_id
end

-- Create tab terminal
function M._create_tab_terminal(session, opts)
  -- Create new tab
  vim.cmd('tabnew')
  local win_id = vim.api.nvim_get_current_win()

  -- Create a new buffer for the terminal (unlisted, scratch buffer)
  local buf_id = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(win_id, buf_id)

  return buf_id, win_id
end

-- Create floating terminal
function M._create_float_terminal(session, opts)
  local config = session.config.float or {}

  -- Get editor dimensions
  local editor_width = vim.o.columns
  local editor_height = vim.o.lines

  -- Calculate window size
  local width = opts.width or config.width or 0.8
  local height = opts.height or config.height or 0.6

  if width <= 1 then
    width = math.floor(editor_width * width)
  end
  if height <= 1 then
    height = math.floor(editor_height * height)
  end

  -- Calculate position (center)
  local col = math.floor((editor_width - width) / 2)
  local row = math.floor((editor_height - height) / 2)

  -- Create buffer
  local buf_id = vim.api.nvim_create_buf(false, true)

  -- Window configuration
  local win_config = {
    relative = 'editor',
    width = width,
    height = height,
    col = col,
    row = row,
    border = config.border or 'rounded',
    title = config.title and string.format('%s: %s', config.title, session.name) or session.name,
    title_pos = config.title_pos or 'center',
    style = 'minimal',
  }

  -- Create floating window
  local win_id = vim.api.nvim_open_win(buf_id, true, win_config)

  return buf_id, win_id
end

-- Configure terminal buffer settings
function M._configure_terminal_buffer(buf_id, session)
  -- Clear any existing content from the buffer
  vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, {})

  -- Set buffer options (but not buftype, as it will be set by termopen)
  vim.api.nvim_buf_set_option(buf_id, 'buflisted', true)
  vim.api.nvim_buf_set_option(buf_id, 'swapfile', false)
  vim.api.nvim_buf_set_option(buf_id, 'modified', false)

  -- Set buffer name
  local buf_name = string.format('DevContainer:%s', session.name)
  vim.api.nvim_buf_set_name(buf_id, buf_name)

  -- Set up autocmds for this buffer
  local group = vim.api.nvim_create_augroup('DevcontainerTerminal_' .. session.name, { clear = true })

  -- Update session when buffer is entered
  vim.api.nvim_create_autocmd('BufEnter', {
    buffer = buf_id,
    group = group,
    callback = function()
      local session_manager = require('container.terminal.session')
      session_manager.set_active_session(session)
    end,
  })

  -- Clean up session when buffer is deleted
  vim.api.nvim_create_autocmd('BufDelete', {
    buffer = buf_id,
    group = group,
    callback = function()
      session.buffer_id = nil
      log.debug('Terminal buffer deleted for session: %s', session.name)
    end,
  })

  -- Auto-enter insert mode if configured
  if session.config.auto_insert then
    vim.api.nvim_create_autocmd('BufEnter', {
      buffer = buf_id,
      group = group,
      callback = function()
        if vim.bo.buftype == 'terminal' then
          vim.cmd('startinsert')
        end
      end,
    })
  end
end

-- Set up terminal-specific keymaps
function M._setup_terminal_keymaps(buf_id, session)
  local keymaps = session.config.keymaps or {}

  -- Terminal mode keymaps
  if keymaps.close then
    vim.api.nvim_buf_set_keymap(buf_id, 't', keymaps.close, '<cmd>close<CR>', {
      noremap = true,
      silent = true,
      desc = 'Close terminal',
    })
  end

  if keymaps.escape then
    vim.api.nvim_buf_set_keymap(buf_id, 't', keymaps.escape, '<C-\\><C-n>', {
      noremap = true,
      silent = true,
      desc = 'Exit terminal mode',
    })
  end

  -- Normal mode keymaps (for session navigation)
  local function setup_session_keymap(mode, key, action, desc)
    if key then
      vim.api.nvim_buf_set_keymap(
        buf_id,
        mode,
        key,
        string.format('<cmd>lua require("container.terminal").%s()<CR>', action),
        {
          noremap = true,
          silent = true,
          desc = desc,
        }
      )
    end
  end

  setup_session_keymap('n', keymaps.new_session, 'new_session', 'Create new terminal session')
  setup_session_keymap('n', keymaps.list_sessions, 'list_sessions', 'List terminal sessions')
  setup_session_keymap('n', keymaps.next_session, 'next_session', 'Next terminal session')
  setup_session_keymap('n', keymaps.prev_session, 'prev_session', 'Previous terminal session')
end

-- Switch to an existing session
function M.switch_to_session(session)
  if not session or not session:is_valid() then
    return false, 'Invalid session'
  end

  -- Find window showing this buffer
  local buf_id = session.buffer_id
  local win_id = nil

  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win) == buf_id then
      win_id = win
      break
    end
  end

  if win_id then
    -- Focus existing window
    vim.api.nvim_set_current_win(win_id)
  else
    -- Create new window for existing buffer with positioning
    local cmd = session.config.split_command or 'belowright 15'
    if not cmd:match('new$') then
      cmd = cmd .. ' new'
    end
    vim.cmd(cmd)
    vim.api.nvim_win_set_buf(vim.api.nvim_get_current_win(), buf_id)
  end

  -- Update active session
  local session_manager = require('container.terminal.session')
  session_manager.set_active_session(session)

  -- Enter insert mode if configured
  if session.config.auto_insert then
    vim.cmd('startinsert')
  end

  return true, nil
end

-- Create terminal command for container
function M.build_terminal_command(container_id, shell, environment)
  shell = shell or '/bin/sh'
  environment = environment or {}

  local cmd = { 'docker', 'exec', '-it' }

  -- Add environment variables
  for _, env in ipairs(environment) do
    table.insert(cmd, '-e')
    table.insert(cmd, env)
  end

  -- Add container and shell
  table.insert(cmd, container_id)
  table.insert(cmd, shell)

  return cmd
end

-- Display session list (for Telescope or simple list)
function M.format_session_list(sessions)
  local formatted = {}

  for _, session in ipairs(sessions) do
    local status_icon = session:is_valid() and '●' or '○'
    local time_str = os.date('%H:%M:%S', session.last_accessed)
    local container_short = session.container_id and session.container_id:sub(1, 12) or 'unknown'

    table.insert(formatted, {
      display = string.format('%s %s (%s) [%s]', status_icon, session.name, time_str, container_short),
      session = session,
    })
  end

  return formatted
end

return M
