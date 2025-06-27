#!/usr/bin/env python3
"""
Phase 0: gopls workspace recognition test
Send different workspace paths to gopls and observe behavior
"""

import json
import subprocess
import sys
import threading
import time

def create_lsp_message(method, params, id=None):
    """Create LSP JSON-RPC message"""
    msg = {
        "jsonrpc": "2.0",
        "method": method,
        "params": params
    }
    if id is not None:
        msg["id"] = id

    content = json.dumps(msg)
    return f"Content-Length: {len(content)}\r\n\r\n{content}"

def test_workspace_recognition(workspace_uri, description):
    """Test gopls workspace recognition with different URIs"""
    print(f"\n=== TESTING: {description} ===")
    print(f"Workspace URI: {workspace_uri}")

    # Initialize message
    init_msg = create_lsp_message("initialize", {
        "processId": None,
        "rootUri": workspace_uri,
        "workspaceFolders": [{
            "uri": workspace_uri,
            "name": "test"
        }],
        "capabilities": {}
    }, id=1)

    # didOpen message for main.go
    didopen_msg = create_lsp_message("textDocument/didOpen", {
        "textDocument": {
            "uri": f"{workspace_uri}/main.go",
            "languageId": "go",
            "version": 1,
            "text": 'package main\n\nimport "./calculator"\n\nfunc main() {\n\tcalc := calculator.NewCalculator()\n\tresult := calc.Add(1, 2)\n\tprintln(result)\n}'
        }
    })

    try:
        # Start gopls in container
        cmd = ["docker", "exec", "-i", "68ea7ef3dfa8", "/go/bin/gopls", "serve"]
        process = subprocess.Popen(
            cmd,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True
        )

        # Send initialize
        process.stdin.write(init_msg)
        process.stdin.flush()

        # Wait a bit
        time.sleep(0.5)

        # Send initialized
        initialized_msg = create_lsp_message("initialized", {})
        process.stdin.write(initialized_msg)
        process.stdin.flush()

        # Send didOpen
        process.stdin.write(didopen_msg)
        process.stdin.flush()

        # Wait for responses
        time.sleep(1)

        # Close stdin to signal end
        process.stdin.close()

        # Get output
        stdout, stderr = process.communicate(timeout=5)

        print(f"STDOUT: {stdout[:500]}...")
        print(f"STDERR: {stderr[:500]}...")

        # Check for typical success/failure patterns
        if "go.mod" in stderr.lower():
            print("✅ gopls found go.mod - workspace recognized")
        elif "no go.mod" in stderr.lower() or "not found" in stderr.lower():
            print("❌ gopls could not find go.mod - workspace NOT recognized")
        else:
            print("? Unclear result - manual analysis needed")

    except Exception as e:
        print(f"Error: {e}")
    finally:
        if process.poll() is None:
            process.terminate()

if __name__ == "__main__":
    print("=== PHASE 0: GOPLS WORKSPACE RECOGNITION TEST ===")

    # Test 1: Host path (current broken behavior)
    test_workspace_recognition(
        "file:///Users/ksoichiro/src/github.com/ksoichiro/container.nvim",
        "Host path (current behavior - should FAIL)"
    )

    # Test 2: Container path (Strategy B - should work)
    test_workspace_recognition(
        "file:///workspace",
        "Container path (Strategy B - should SUCCEED)"
    )

    print("\n=== ANALYSIS COMPLETE ===")
    print("Check the results above to confirm our hypothesis:")
    print("- Host paths should fail to find go.mod")
    print("- Container paths should successfully find go.mod")
