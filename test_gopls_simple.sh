#!/bin/bash

echo "=== PHASE 0: SIMPLE GOPLS BEHAVIOR TEST ==="

CONTAINER_ID="68ea7ef3dfa8"

echo
echo "=== TEST 1: GOPLS WITH /workspace PATH ==="
echo "Running gopls in container with workspace path..."

# Create test file with workspace path
docker exec $CONTAINER_ID bash -c "
cd /workspace
echo 'Testing gopls with /workspace path...'

# Test if gopls can find modules from /workspace
timeout 5 /go/bin/gopls check /workspace/main.go 2>&1 | head -10
echo 'Exit status:' \$?
"

echo
echo "=== TEST 2: GOPLS WITH HOST PATH (should fail) ==="
echo "Running gopls in container with host path..."

# Test with non-existent host path
docker exec $CONTAINER_ID bash -c "
cd /workspace
echo 'Testing gopls with host path...'

# Test if gopls can find modules from host path
timeout 5 /go/bin/gopls check /Users/ksoichiro/src/github.com/ksoichiro/container.nvim/main.go 2>&1 | head -10
echo 'Exit status:' \$?
"

echo
echo "=== TEST 3: MODULE RESOLUTION ==="
echo "Checking go module resolution..."

docker exec $CONTAINER_ID bash -c "
cd /workspace
echo 'From /workspace:'
go list -m all 2>&1 | head -5

echo
echo 'Testing import resolution:'
go build -v ./... 2>&1 | head -10
"

echo
echo "=== ANALYSIS ==="
echo "Expected results:"
echo "- Test 1 (/workspace): Should work or show meaningful Go errors"
echo "- Test 2 (host path): Should fail with 'no such file' errors"
echo "- Test 3: Should show proper module resolution from /workspace"
