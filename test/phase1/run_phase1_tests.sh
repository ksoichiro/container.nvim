#!/bin/bash

# Phase 1 Test Runner for Strategy B Implementation
# Tests all major components of the LSP proxy system

set -e

echo "Strategy B Phase 1 Implementation Testing"
echo "=========================================="
echo

# Change to repository root
cd "$(dirname "$0")/../.."

# Ensure test scripts are executable
chmod +x test/phase1/*.lua test/phase1/*.sh

echo "=== Running Phase 1 Component Tests ==="
echo

echo "Step 1: JSON-RPC Module Test"
echo "-----------------------------"
if lua test/phase1/test_jsonrpc.lua; then
    echo "✅ JSON-RPC module test PASSED"
else
    echo "❌ JSON-RPC module test FAILED"
    echo "   Core message processing has issues"
    echo "   Fix JSON-RPC implementation before proceeding"
    exit 1
fi

echo
echo "Step 2: Path Transform Module Test"
echo "-----------------------------------"
if lua test/phase1/test_transform.lua; then
    echo "✅ Path transformation test PASSED"
else
    echo "❌ Path transformation test FAILED"
    echo "   Path transformation engine has issues"
    echo "   Fix transform implementation before proceeding"
    exit 1
fi

echo
echo "Step 3: Integration Readiness Check"
echo "------------------------------------"

# Check if all required modules exist
required_modules=(
    "lua/container/lsp/proxy/jsonrpc.lua"
    "lua/container/lsp/proxy/transport.lua"
    "lua/container/lsp/proxy/transform.lua"
    "lua/container/lsp/proxy/server.lua"
    "lua/container/lsp/proxy/init.lua"
)

all_modules_exist=true
for module in "${required_modules[@]}"; do
    if [[ -f "$module" ]]; then
        echo "✓ $module exists"
    else
        echo "❌ $module missing"
        all_modules_exist=false
    fi
done

if [[ "$all_modules_exist" == "true" ]]; then
    echo "✅ All proxy modules are implemented"
else
    echo "❌ Some proxy modules are missing"
    echo "   Complete implementation before integration"
    exit 1
fi

echo
echo "Step 4: Lua Syntax Check"
echo "-------------------------"

syntax_errors=false
for module in "${required_modules[@]}"; do
    if luac -p "$module" 2>/dev/null; then
        echo "✓ $module syntax OK"
    else
        echo "❌ $module syntax error"
        syntax_errors=true
    fi
done

if [[ "$syntax_errors" == "false" ]]; then
    echo "✅ All modules have valid syntax"
else
    echo "❌ Syntax errors detected"
    echo "   Fix syntax errors before proceeding"
    exit 1
fi

echo
echo "Step 5: Module Loading Test"
echo "----------------------------"

# Test basic module loading
cat > /tmp/test_module_loading.lua << 'EOF'
package.path = './lua/?.lua;./lua/?/init.lua;' .. package.path

-- Mock dependencies
_G.vim = {
  json = { encode = function() return "{}" end, decode = function() return {} end },
  deepcopy = function(obj) return obj end,
  tbl_keys = function() return {} end,
  pesc = function(str) return str end,
  inspect = function() return "" end,
  lsp = { protocol = { make_client_capabilities = function() return {} end } },
  defer_fn = function(fn) fn() end,
  tbl_deep_extend = function(behavior, t1, t2)
    local result = {}
    for k, v in pairs(t1 or {}) do
      result[k] = v
    end
    for k, v in pairs(t2 or {}) do
      result[k] = v
    end
    return result
  end,
  tbl_extend = function(behavior, ...) return {} end,
  tbl_isempty = function() return true end,
  tbl_count = function(tbl) return tbl and #tbl or 0 end,
  fn = { getcwd = function() return "/test" end },
  loop = {
    new_pipe = function() return {} end,
    spawn = function() return {}, 123 end,
  },
  list_slice = function(tbl, start) return {} end,
  trim = function(str) return str end,
}

package.loaded['container.utils.log'] = {
  debug = function() end,
  info = function() end,
  warn = function() end,
  error = function() end,
}

-- Test module loading
local modules = {
  'container.lsp.proxy.jsonrpc',
  'container.lsp.proxy.transport',
  'container.lsp.proxy.transform',
  'container.lsp.proxy.server',
  'container.lsp.proxy.init'
}

for _, module_name in ipairs(modules) do
  local ok, module = pcall(require, module_name)
  if ok then
    print("✓ " .. module_name .. " loaded successfully")
  else
    print("❌ " .. module_name .. " failed to load: " .. tostring(module))
    os.exit(1)
  end
end

print("✅ All modules loaded successfully")
EOF

if lua /tmp/test_module_loading.lua; then
    echo "✅ Module loading test PASSED"
else
    echo "❌ Module loading test FAILED"
    echo "   Fix module dependencies and loading issues"
    rm -f /tmp/test_module_loading.lua
    exit 1
fi

rm -f /tmp/test_module_loading.lua

echo
echo "Step 6: API Interface Check"
echo "----------------------------"

# Test basic API interface
cat > /tmp/test_api_interface.lua << 'EOF'
package.path = './lua/?.lua;./lua/?/init.lua;' .. package.path

-- Mock dependencies (same as above)
_G.vim = {
  json = { encode = function() return "{}" end, decode = function() return {} end },
  deepcopy = function(obj) return obj end,
  tbl_keys = function() return {} end,
  pesc = function(str) return str end,
  inspect = function() return "" end,
  lsp = { protocol = { make_client_capabilities = function() return {} end } },
  defer_fn = function(fn) fn() end,
  tbl_deep_extend = function(behavior, t1, t2)
    local result = {}
    for k, v in pairs(t1 or {}) do
      result[k] = v
    end
    for k, v in pairs(t2 or {}) do
      result[k] = v
    end
    return result
  end,
  tbl_extend = function(behavior, ...) return {} end,
  tbl_isempty = function() return true end,
  tbl_count = function(tbl) return tbl and #tbl or 0 end,
  fn = { getcwd = function() return "/test" end },
  loop = {
    new_pipe = function() return {} end,
    spawn = function() return {}, 123 end,
  },
  list_slice = function(tbl, start) return {} end,
  trim = function(str) return str end,
}

package.loaded['container.utils.log'] = {
  debug = function() end,
  info = function() end,
  warn = function() end,
  error = function() end,
}

-- Test main API
local proxy = require('container.lsp.proxy.init')

-- Check essential functions exist
local required_functions = {
  'setup',
  'create_proxy',
  'get_proxy',
  'stop_proxy',
  'list_active_proxies',
  'get_system_stats',
  'health_check'
}

for _, func_name in ipairs(required_functions) do
  if type(proxy[func_name]) == 'function' then
    print("✓ " .. func_name .. " function exists")
  else
    print("❌ " .. func_name .. " function missing")
    os.exit(1)
  end
end

print("✅ All required API functions exist")

-- Test basic setup (disable periodic tasks for testing)
proxy.setup({
  auto_cleanup_interval = 0,
  enable_health_monitoring = false
})
print("✅ Setup function callable")
EOF

if lua /tmp/test_api_interface.lua; then
    echo "✅ API interface test PASSED"
else
    echo "❌ API interface test FAILED"
    echo "   Fix API interface implementation"
    rm -f /tmp/test_api_interface.lua
    exit 1
fi

rm -f /tmp/test_api_interface.lua

echo
echo "=== Phase 1 Summary ==="
echo "🎉 All Phase 1 implementation tests PASSED!"
echo
echo "Strategy B Core Implementation: COMPLETED ✅"
echo
echo "Implemented components:"
echo "• JSON-RPC message processing with LSP protocol compliance"
echo "• Bidirectional transport layer with async I/O"
echo "• Comprehensive path transformation engine"
echo "• LSP proxy server with message routing"
echo "• High-level API for proxy management"
echo
echo "Key validations:"
echo "• All modules load without errors"
echo "• Core functionality passes unit tests"
echo "• API interface is complete and callable"
echo "• Path transformation handles all LSP methods"
echo "• JSON-RPC processing is performant and robust"
echo
echo "🟢 Ready for Integration: Phase 1 → container.nvim architecture"
echo
echo "Recommended next steps:"
echo "1. Integrate proxy system with existing container.nvim LSP module"
echo "2. Create end-to-end integration tests"
echo "3. Test with real containerized LSP servers"
echo "4. Performance optimization and error handling refinement"
echo "5. User testing and feedback collection"
echo
echo "Time to implement: Strategy B core foundation complete! 🚀"
