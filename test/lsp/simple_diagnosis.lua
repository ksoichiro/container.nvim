-- Simple diagnosis without using docker.exec

print('=== Simple Diagnosis ===')

-- 1. Check container status using system command
local container = require('container')
local state = container.get_state()
local container_id = state.current_container

if container_id then
  print('\n1. Container:', container_id)

  -- Check if gopls is running in container
  print('\n2. Checking gopls in container...')
  local cmd = string.format('docker exec %s ps aux | grep gopls', container_id)
  local result = vim.fn.system(cmd)
  print('Gopls processes:')
  print(result)

  -- Check workspace contents
  print('\n3. Checking /workspace in container...')
  local ls_cmd = string.format('docker exec %s ls -la /workspace/', container_id)
  local ls_result = vim.fn.system(ls_cmd)
  print(ls_result:sub(1, 300))

  -- Check if main.go exists
  print('\n4. Checking main.go in container...')
  local file_cmd = string.format('docker exec %s cat /workspace/main.go | head -5', container_id)
  local file_result = vim.fn.system(file_cmd)
  if file_result:match('package main') then
    print('✅ main.go exists and is readable')
  else
    print('❌ main.go not found or not readable')
    print(file_result)
  end
end

-- 2. Check current LSP client
print('\n5. Current LSP client check:')
local clients = vim.lsp.get_clients()
local container_client = nil

for _, client in ipairs(clients) do
  if client.name == 'container_gopls' then
    container_client = client
    print('✅ Found container_gopls')
    print('  ID:', client.id)
    print('  Initialized:', client.initialized)
    print('  Command:', vim.inspect(client.config.cmd))
    break
  end
end

-- 3. Test with direct container path
if container_client and container_client.initialized then
  print('\n6. Testing with direct container path...')

  -- First, send didOpen with container path
  local didopen_params = {
    textDocument = {
      uri = 'file:///workspace/main.go',
      languageId = 'go',
      version = 0,
      text = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n'),
    },
  }

  print('Sending didOpen with container URI:', didopen_params.textDocument.uri)
  container_client.notify('textDocument/didOpen', didopen_params)

  -- Wait then test hover
  vim.defer_fn(function()
    print('\n7. Testing hover with container path...')

    -- Try hover at NewCalculator function (line 11)
    local hover_params = {
      textDocument = {
        uri = 'file:///workspace/main.go',
      },
      position = {
        line = 10, -- 0-indexed
        character = 5,
      },
    }

    container_client.request('textDocument/hover', hover_params, function(err, result)
      print('\n=== Hover Test Result ===')
      if err then
        print('❌ Error:', vim.inspect(err))
      elseif result and result.contents then
        print('✅ SUCCESS! Hover works with container path')
        print('Content type:', type(result.contents))
        if type(result.contents) == 'table' and result.contents.value then
          print('Preview:', result.contents.value:sub(1, 100) .. '...')
        end
      else
        print('❌ No hover result')
        print('This suggests gopls cannot access the file')
      end

      print('\n=== Conclusion ===')
      if result and result.contents then
        print('✅ Container gopls is working correctly')
        print('❌ The issue is with path transformation')
        print('Solution: Fix the interceptor to transform paths correctly')
      else
        print('❌ Container gopls cannot access files')
        print('Possible causes:')
        print('1. File not mounted in container')
        print('2. Gopls not configured correctly')
        print('3. Permission issues')
      end
    end, 0)

    -- Also test diagnostics
    print('\n8. Testing diagnostics...')
    container_client.request('textDocument/diagnostic', {
      textDocument = { uri = 'file:///workspace/main.go' },
    }, function(err, result)
      if err then
        print('Diagnostic error:', vim.inspect(err))
      elseif result then
        print('Diagnostic result:', vim.inspect(result))
      end
    end, 0)
  end, 1000)
else
  print('❌ No container_gopls client available')
end

print('\n=== Manual Commands to Try ===')
print('1. Check container gopls:')
print('   :!docker exec ' .. (container_id or 'CONTAINER_ID') .. ' which gopls')
print('2. Test gopls directly:')
print('   :!docker exec ' .. (container_id or 'CONTAINER_ID') .. ' gopls version')
