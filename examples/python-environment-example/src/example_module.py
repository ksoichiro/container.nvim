"""
Example module to demonstrate PYTHONPATH configuration.

This module should be importable when PYTHONPATH includes /workspace/src.
"""

def greet(name: str) -> str:
    """Return a greeting message."""
    return f"Hello, {name}! Environment customization is working."
