#!/usr/bin/env lua

-- Calculate coverage for a specific lua file from luacov.stats.out

local function calculate_coverage(target_file)
  target_file = target_file or "lua/container/init.lua"

  local file = io.open("luacov.stats.out", "r")
  if not file then
    print("Error: luacov.stats.out not found")
    return
  end

  local content = file:read("*all")
  file:close()

  -- Escape special characters in target_file for pattern matching
  local escaped_file = target_file:gsub("[%.%-]", "%%%1")

  -- Find the line for the target file
  local pattern = "(%d+):" .. escaped_file .. "\n([^\n]+)"
  local total_lines, coverage_data = content:match(pattern)

  if not total_lines or not coverage_data then
    print("Error: Could not find coverage data for " .. target_file)
    return
  end

  total_lines = tonumber(total_lines)
  print("Total lines in " .. target_file .. ": " .. total_lines)

  -- Split coverage data into individual numbers
  local executed_lines = 0
  local executable_lines = 0

  for count in coverage_data:gmatch("(%d+)") do
    local num = tonumber(count)
    if num > 0 then
      executed_lines = executed_lines + 1
      executable_lines = executable_lines + 1
    elseif num == 0 then
      executable_lines = executable_lines + 1
    end
    -- Numbers that are not 0 or positive integers are non-executable lines
  end

  print("Executable lines: " .. executable_lines)
  print("Executed lines: " .. executed_lines)

  if executable_lines > 0 then
    local coverage_percentage = (executed_lines / executable_lines) * 100
    print(string.format("Coverage: %.2f%%", coverage_percentage))
    return coverage_percentage
  else
    print("No executable lines found")
    return 0
  end
end

-- Get target file from command line argument or use default
local target_file = arg and arg[1] or "lua/container/init.lua"
calculate_coverage(target_file)
