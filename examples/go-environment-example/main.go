package main

import (
	"fmt"
	"os"
)

func main() {
	fmt.Println("Go Environment Example")
	fmt.Println("======================")

	// Print environment variables set by container.nvim
	fmt.Printf("GOPATH: %s\n", os.Getenv("GOPATH"))
	fmt.Printf("GOROOT: %s\n", os.Getenv("GOROOT"))
	fmt.Printf("GO111MODULE: %s\n", os.Getenv("GO111MODULE"))
	fmt.Printf("PATH: %s\n", os.Getenv("PATH"))

	fmt.Println("\nThis demonstrates custom environment configuration")
	fmt.Println("for Go projects using container.nvim customizations.")
}
