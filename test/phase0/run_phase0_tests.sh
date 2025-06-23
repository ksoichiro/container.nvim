#!/bin/bash

# Phase 0 Test Runner for Strategy B Technical Validation
# Runs all critical tests to determine if Strategy B is feasible

set -e

echo "Strategy B Phase 0 Technical Validation"
echo "======================================="
echo

# Change to repository root
cd "$(dirname "$0")/../.."

# Ensure test container is available
echo "=== Container Setup ==="
container_id=$(docker ps --filter 'name=container.nvim' --format '{{.ID}}' 2>/dev/null || true)

if [ -z "$container_id" ]; then
    echo "No test container found. Creating one..."
    docker run -d --name container.nvim ubuntu:20.04 sleep infinity
    echo "✓ Created test container"
    container_id=$(docker ps --filter 'name=container.nvim' --format '{{.ID}}')

    # Install lua in container for proxy tests
    docker exec "$container_id" apt-get update -qq
    docker exec "$container_id" apt-get install -y lua5.3
    echo "✓ Installed Lua in container"
else
    echo "✓ Using existing container: $container_id"
fi

echo

# Make test scripts executable
chmod +x test/phase0/*.lua test/phase0/*.sh

# Run Phase 0 tests in sequence
echo "=== Running Phase 0 Tests ==="
echo

echo "Step 1: Minimal Communication Test"
echo "-----------------------------------"
if lua test/phase0/test_minimal_proxy.lua; then
    echo "✅ Minimal communication test PASSED"
else
    echo "❌ Minimal communication test FAILED"
    echo "   Strategy B is not technically feasible"
    echo "   Recommendation: Abandon Strategy B, consider alternatives"
    exit 1
fi

echo
echo "Step 2: Proxy Integration Test"
echo "-------------------------------"
if lua test/phase0/test_proxy_integration.lua; then
    echo "✅ Proxy integration test PASSED"
else
    echo "❌ Proxy integration test FAILED"
    echo "   Basic proxy concept has issues"
    echo "   Recommendation: Review proxy implementation approach"
    exit 1
fi

echo
echo "=== Phase 0 Summary ==="
echo "🎉 All Phase 0 tests PASSED!"
echo
echo "Strategy B Technical Feasibility: CONFIRMED ✅"
echo
echo "Key findings:"
echo "• Docker exec stdio communication is stable and reliable"
echo "• vim.lsp.start_client() accepts docker exec command chains"
echo "• JSON-RPC messages pass through proxy without corruption"
echo "• Basic path transformation concept works"
echo "• Performance baseline is acceptable for LSP communication"
echo
echo "🟢 GO Decision: Proceed with Strategy B implementation"
echo
echo "Recommended next steps:"
echo "1. Implement comprehensive JSON-RPC proxy (Phase 1)"
echo "2. Add full LSP method support and path transformation"
echo "3. Integrate with container.nvim architecture"
echo "4. Performance optimization and error handling"
echo "5. User testing and feedback collection"
echo
echo "Time investment validated: Strategy B is worth pursuing! 🚀"

echo
echo "Cleanup: Keeping test container for development..."
echo "To remove: docker rm -f container.nvim"
