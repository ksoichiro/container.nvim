-- E2E Test Discovery Helper
-- Automatically discovers test files based on naming conventions

local M = {}

-- Discover test files in the e2e directory
function M.discover_test_files()
  local test_files = {}

  -- Get all test_*.lua files in the e2e directory
  local handle = io.popen('find test/e2e -name "test_*.lua" -type f 2>/dev/null | sort')
  if not handle then
    return test_files
  end

  for line in handle:lines() do
    -- Extract just the filename from the path
    local filename = line:match('test/e2e/(.+)$')
    if filename and not filename:match('helpers/') and not filename:match('run_test') then
      -- Generate test case info from filename
      local name = filename:gsub('test_', ''):gsub('_e2e%.lua$', ''):gsub('%.lua$', ''):gsub('_', ' ')
      name = name:gsub('^%l', string.upper):gsub(' %l', string.upper)

      -- Generate description based on filename patterns
      local description = M.generate_description(filename)

      table.insert(test_files, {
        file = filename,
        name = name .. ' Tests',
        description = description,
      })
    end
  end

  handle:close()
  return test_files
end

-- Generate description based on filename patterns
function M.generate_description(filename)
  if filename:match('essential') then
    return 'Core functionality verification'
  elseif filename:match('lifecycle') then
    return 'Container creation, management, and cleanup'
  elseif filename:match('workflow') then
    return 'Complete development workflow scenarios'
  elseif filename:match('integration') then
    return 'Plugin integration testing'
  elseif filename:match('performance') then
    return 'Performance and load testing'
  else
    return 'E2E functionality testing'
  end
end

-- Check if a file exists
function M.file_exists(filepath)
  local file = io.open(filepath, 'r')
  if file then
    file:close()
    return true
  end
  return false
end

return M
