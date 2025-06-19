#!/usr/bin/env python3

import os
import sys

def main():
    print("Python Environment Example")
    print("==========================")

    # Print environment variables set by container.nvim
    print(f"PYTHONPATH: {os.getenv('PYTHONPATH', 'Not set')}")
    print(f"DEBUG: {os.getenv('DEBUG', 'Not set')}")
    print(f"PATH: {os.getenv('PATH', 'Not set')}")
    print(f"Python version: {sys.version}")
    print(f"Python executable: {sys.executable}")

    print("\nThis demonstrates language preset configuration")
    print("for Python projects using container.nvim customizations.")

    # Test PYTHONPATH
    if '/workspace/src' in sys.path:
        print("✓ PYTHONPATH is correctly configured")
    else:
        print("ℹ PYTHONPATH configuration not detected in sys.path")

if __name__ == "__main__":
    main()
