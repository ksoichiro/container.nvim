-- リクエスト変換の動作確認
-- 使用方法: Neovim内で :lua dofile('../../test_request_transform.lua')

print("=== REQUEST TRANSFORM TEST ===")

-- 現在のカーソル位置でパラメータ作成
local params = vim.lsp.util.make_position_params()
print("Original params:", vim.inspect(params))

-- 手動でパス変換をテスト
local transformed_params = vim.deepcopy(params)
if transformed_params.textDocument and transformed_params.textDocument.uri then
  local original_uri = transformed_params.textDocument.uri
  local host_workspace = vim.fn.getcwd()

  -- ホストパスをコンテナパスに変換
  if original_uri:match('^file://' .. vim.pesc(host_workspace)) then
    transformed_params.textDocument.uri = original_uri:gsub(
      '^file://' .. vim.pesc(host_workspace),
      'file:///workspace'
    )
    print("Transformed URI:", transformed_params.textDocument.uri)
  end
end

print("\n=== TESTING WITH TRANSFORMED PARAMS ===")

-- 変換後のパラメータでリクエスト
local clients = vim.lsp.get_clients()
for _, client in ipairs(clients) do
  if client.name == 'container_gopls' then
    print("Sending request with transformed params...")

    client.request('textDocument/definition', transformed_params, function(err, result)
      print("=== RESPONSE WITH TRANSFORMED PARAMS ===")
      print("Error:", vim.inspect(err))
      if result then
        print("Result:", vim.inspect(result))
        if #result > 0 then
          print("Success! Got definition response")
          -- コンテナパスをホストパスに変換して表示
          for _, location in ipairs(result) do
            if location.uri then
              local container_uri = location.uri
              local host_uri = container_uri:gsub('^file:///workspace', 'file://' .. host_workspace)
              print("Container URI:", container_uri)
              print("Host URI:", host_uri)
            end
          end
        end
      else
        print("Result: nil")
      end
    end, 0)

    break
  end
end
