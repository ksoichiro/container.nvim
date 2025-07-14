-- Common test helpers for container.nvim unit tests
-- Provides comprehensive vim API mocks and utility functions

local M = {}

-- Comprehensive vim mock setup
function M.setup_vim_mock()
  _G.vim = _G.vim or {}

  -- Table utilities
  vim.tbl_contains = vim.tbl_contains
    or function(tbl, val)
      for _, v in ipairs(tbl) do
        if v == val then
          return true
        end
      end
      return false
    end

  vim.tbl_deep_extend = vim.tbl_deep_extend
    or function(behavior, ...)
      local tables = { ... }
      local result = {}
      for _, tbl in ipairs(tables) do
        if type(tbl) == 'table' then
          for k, v in pairs(tbl) do
            if type(v) == 'table' and type(result[k]) == 'table' then
              result[k] = vim.tbl_deep_extend(behavior, result[k], v)
            else
              result[k] = v
            end
          end
        end
      end
      return result
    end

  vim.tbl_count = vim.tbl_count
    or function(t)
      local count = 0
      for _ in pairs(t) do
        count = count + 1
      end
      return count
    end

  vim.list_extend = vim.list_extend
    or function(dst, src)
      for _, item in ipairs(src) do
        table.insert(dst, item)
      end
      return dst
    end

  -- Function namespace
  vim.fn = vim.fn or {}

  vim.fn.fnamemodify = vim.fn.fnamemodify
    or function(path, modifier)
      if modifier == ':p' then
        return path
      elseif modifier == ':h' then
        return path:gsub('/[^/]*$', '')
      elseif modifier == ':t' then
        return path:match('[^/]*$')
      end
      return path
    end

  vim.fn.isdirectory = vim.fn.isdirectory or function(path)
    return path:match('/$') and 1 or 0
  end

  vim.fn.mkdir = vim.fn.mkdir or function(path, mode)
    return 1
  end

  vim.fn.getcwd = vim.fn.getcwd or function()
    return '/test/workspace'
  end

  vim.fn.filereadable = vim.fn.filereadable or function(path)
    return 0
  end

  vim.fn.stdpath = vim.fn.stdpath
    or function(what)
      if what == 'data' then
        return '/test/data'
      end
      return '/test/' .. what
    end

  vim.fn.has = vim.fn.has or function(feature)
    return feature == 'nvim-0.10' and 1 or 0
  end

  vim.fn.argc = vim.fn.argc or function()
    return 0
  end

  vim.fn.wait = vim.fn.wait or function(timeout, condition, interval)
    return condition() and 0 or -1
  end

  vim.fn.system = vim.fn.system or function(cmd)
    return ''
  end

  vim.fn.shellescape = vim.fn.shellescape or function(str)
    return "'" .. str .. "'"
  end

  vim.fn.expand = vim.fn.expand or function(path)
    return path
  end

  vim.fn.jobstart = vim.fn.jobstart or function(cmd, opts)
    return 1
  end

  vim.fn.jobstop = vim.fn.jobstop or function(job_id)
    return 1
  end

  vim.fn.chanclose = vim.fn.chanclose or function(id)
    return 0
  end

  vim.fn.chansend = vim.fn.chansend or function(id, data)
    return 0
  end

  vim.fn.getftime = vim.fn.getftime or function(file)
    return os.time()
  end

  vim.fn.tempname = vim.fn.tempname or function()
    return '/tmp/test_temp_' .. math.random(10000)
  end

  -- Timing functions
  vim.uv = vim.uv or {}
  vim.uv.hrtime = vim.uv.hrtime or function()
    return os.clock() * 1000000000
  end

  vim.loop = vim.loop or vim.uv

  -- API namespace
  vim.api = vim.api or {}

  vim.api.nvim_create_augroup = vim.api.nvim_create_augroup or function(name, opts)
    return math.random(1000)
  end

  vim.api.nvim_create_autocmd = vim.api.nvim_create_autocmd or function(events, opts)
    return math.random(1000)
  end

  vim.api.nvim_get_current_buf = vim.api.nvim_get_current_buf or function()
    return 1
  end

  vim.api.nvim_list_bufs = vim.api.nvim_list_bufs or function()
    return { 1, 2, 3 }
  end

  vim.api.nvim_buf_is_loaded = vim.api.nvim_buf_is_loaded or function(buf)
    return true
  end

  vim.api.nvim_buf_is_valid = vim.api.nvim_buf_is_valid or function(buf)
    return buf and buf > 0
  end

  vim.api.nvim_buf_get_name = vim.api.nvim_buf_get_name
    or function(buf)
      return '/test/workspace/file' .. buf .. '.go'
    end

  vim.api.nvim_buf_get_option = vim.api.nvim_buf_get_option
    or function(buf, option)
      if option == 'filetype' then
        return 'go'
      end
      return nil
    end

  -- Schedule function
  vim.schedule = vim.schedule or function(fn)
    fn()
  end

  vim.defer_fn = vim.defer_fn or function(fn, delay)
    fn()
  end

  -- LSP utilities
  vim.lsp = vim.lsp or {}
  vim.lsp.util = vim.lsp.util or {}
  vim.lsp.util.is_stopped = vim.lsp.util.is_stopped
    or function(client)
      return client and client.is_stopped and client.is_stopped()
    end

  vim.lsp.get_clients = vim.lsp.get_clients or function(opts)
    return {}
  end

  vim.lsp.start = vim.lsp.start
    or function(config, opts)
      return {
        id = math.random(1000),
        is_stopped = function()
          return false
        end,
      }
    end

  vim.lsp.buf_attach_client = vim.lsp.buf_attach_client or function(bufnr, client_id)
    return true
  end

  vim.lsp.buf = vim.lsp.buf or {}
  vim.lsp.buf.hover = vim.lsp.buf.hover or function() end
  vim.lsp.buf.definition = vim.lsp.buf.definition or function() end
  vim.lsp.buf.references = vim.lsp.buf.references or function() end

  vim.lsp.handlers = vim.lsp.handlers or {}

  -- Diagnostic utilities
  vim.diagnostic = vim.diagnostic or {}
  vim.diagnostic.config = vim.diagnostic.config or function() end
  vim.diagnostic.get = vim.diagnostic.get or function()
    return {}
  end

  -- Other utilities
  vim.v = vim.v or { shell_error = 0 }
  vim.bo = vim.bo or {}
  vim.env = vim.env or {}
  vim.log = vim.log or { levels = { DEBUG = 1, INFO = 2, WARN = 3, ERROR = 4 } }
  vim.notify = vim.notify or function(msg, level) end
  vim.inspect = vim.inspect or function(obj)
    return tostring(obj)
  end

  -- JSON utilities
  vim.json = vim.json or {}
  vim.json.decode = vim.json.decode
    or function(str)
      -- Simple mock - just return empty table for now
      return {}
    end

  vim.json.encode = vim.json.encode or function(obj)
    return '{}'
  end
end

-- Setup lua path for tests
function M.setup_lua_path()
  package.path = './lua/?.lua;./lua/?/init.lua;../lua/?.lua;../lua/?/init.lua;' .. package.path
end

-- Simple assertion helpers
function M.assert_equals(actual, expected, message)
  if actual ~= expected then
    error(
      string.format('%s\nExpected: %s\nActual: %s', message or 'Assertion failed', tostring(expected), tostring(actual))
    )
  end
end

function M.assert_not_nil(value, message)
  if value == nil then
    error(message or 'Expected non-nil value')
  end
end

function M.assert_type(value, expected_type, message)
  if type(value) ~= expected_type then
    error(
      string.format(
        '%s\nExpected type: %s\nActual type: %s',
        message or 'Type assertion failed',
        expected_type,
        type(value)
      )
    )
  end
end

return M
