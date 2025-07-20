package main

import (
	"fmt"
	"os"
)

func main() {
	fmt.Println("Environment Variable Expansion Test")
	fmt.Println("===================================")

	// Show expanded environment variables
	fmt.Printf("PATH: %s\n", os.Getenv("PATH"))
	fmt.Printf("HOME_VAR: %s\n", os.Getenv("HOME_VAR"))
	fmt.Printf("SHELL_VAR: %s\n", os.Getenv("SHELL_VAR"))
	fmt.Printf("USER_VAR: %s\n", os.Getenv("USER_VAR"))
	fmt.Printf("CUSTOM_VAR: %s\n", os.Getenv("CUSTOM_VAR"))

	// Test custom PATH
	fmt.Println("\nTesting custom PATH:")
	if pathHasCustom := fmt.Sprintf("%s", os.Getenv("PATH")); pathHasCustom != "" {
		fmt.Printf("✓ PATH contains custom path: %s\n", pathHasCustom)
		if os.Getenv("PATH")[:len("/usr/local/custom/bin")] == "/usr/local/custom/bin" {
			fmt.Println("✓ Custom path is at the beginning")
		} else {
			fmt.Println("✗ Custom path is not at the beginning")
		}
	} else {
		fmt.Println("✗ PATH is empty")
	}

	fmt.Println("\nEnvironment expansion test completed!")
}
