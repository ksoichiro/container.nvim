package main

import (
	"fmt"
)

func main() {
	fmt.Println("Go Test Integration Example")
	fmt.Println("===========================")
	fmt.Println()
	fmt.Println("This example demonstrates test execution in devcontainers.")
	fmt.Println()

	// Calculator demo
	calc := NewCalculator()
	fmt.Println("Calculator Demo:")
	fmt.Printf("  5 + 3 = %.2f\n", calc.Add(5, 3))
	fmt.Printf("  10 - 4 = %.2f\n", calc.Subtract(10, 4))
	fmt.Printf("  6 * 7 = %.2f\n", calc.Multiply(6, 7))

	if result, err := calc.Divide(20, 4); err == nil {
		fmt.Printf("  20 / 4 = %.2f\n", result)
	}

	fmt.Printf("  Memory: %.2f\n", calc.Memory())
	fmt.Println()

	// String utils demo
	fmt.Println("String Utils Demo:")
	fmt.Printf("  Reverse('hello') = %s\n", Reverse("hello"))
	fmt.Printf("  IsPalindrome('level') = %v\n", IsPalindrome("level"))
	fmt.Printf("  CountWords('Hello world') = %d\n", CountWords("Hello world"))
	fmt.Printf("  TitleCase('hello world') = %s\n", TitleCase("hello world"))
	fmt.Printf("  Contains('Hello World', 'world') = %v\n", Contains("Hello World", "world"))
}
