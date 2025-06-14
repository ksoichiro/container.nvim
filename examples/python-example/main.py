#!/usr/bin/env python3
"""
Example Python file to test LSP integration with devcontainer.nvim
"""

def hello_world(name: str = "World") -> str:
    """Return a greeting message."""
    return f"Hello, {name}!"


def calculate_sum(numbers: list[int]) -> int:
    """Calculate the sum of a list of numbers."""
    return sum(numbers)


class Calculator:
    """A simple calculator class."""
    
    def __init__(self):
        self.history = []
    
    def add(self, a: float, b: float) -> float:
        """Add two numbers."""
        result = a + b
        self.history.append(f"{a} + {b} = {result}")
        return result
    
    def multiply(self, a: float, b: float) -> float:
        """Multiply two numbers."""
        result = a * b
        self.history.append(f"{a} * {b} = {result}")
        return result
    
    def get_history(self) -> list[str]:
        """Get calculation history."""
        return self.history.copy()


def main():
    """Main function for testing."""
    print(hello_world("devcontainer.nvim"))
    
    numbers = [1, 2, 3, 4, 5]
    total = calculate_sum(numbers)
    print(f"Sum of {numbers} is {total}")
    
    calc = Calculator()
    result1 = calc.add(10, 5)
    result2 = calc.multiply(3, 7)
    
    print(f"Results: {result1}, {result2}")
    print(f"History: {calc.get_history()}")


if __name__ == "__main__":
    main()
