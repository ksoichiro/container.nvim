package main

import (
	"fmt"
	"log"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
)

// User represents a user in our application
type User struct {
	ID    int    `json:"id"`
	Name  string `json:"name"`
	Email string `json:"email"`
}

// Calculator provides basic math operations
type Calculator struct {
	history []string
}

// NewCalculator creates a new calculator instance
func NewCalculator() *Calculator {
	return &Calculator{
		history: make([]string, 0),
	}
}

// Add performs addition and records the operation
func (c *Calculator) Add(a, b int) int {
	result := a + b
	c.history = append(c.history, fmt.Sprintf("%d + %d = %d", a, b, result))
	return result
}

// Multiply performs multiplication and records the operation
func (c *Calculator) Multiply(a, b int) int {
	result := a * b
	c.history = append(c.history, fmt.Sprintf("%d * %d = %d", a, b, result))
	return result
}

// GetHistory returns the calculation history
func (c *Calculator) GetHistory() []string {
	return append([]string{}, c.history...)
}

// CreateGreeting creates a personalized greeting message
func CreateGreeting(name string) string {
	if name == "" {
		name = "World"
	}
	return fmt.Sprintf("Hello, %s!", name)
}

// CalculateSum calculates the sum of a slice of integers
func CalculateSum(numbers []int) int {
	sum := 0
	for _, num := range numbers {
		sum += num
	}
	return sum
}

func main() {
	// Initialize Gin router
	r := gin.Default()

	// Create calculator instance
	calc := NewCalculator()

	// Routes
	r.GET("/", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{
			"message":   CreateGreeting("devcontainer.nvim"),
			"timestamp": time.Now().Format(time.RFC3339),
		})
	})

	r.POST("/calculate/sum", func(c *gin.Context) {
		var request struct {
			Numbers []int `json:"numbers"`
		}

		if err := c.ShouldBindJSON(&request); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
			return
		}

		sum := CalculateSum(request.Numbers)
		c.JSON(http.StatusOK, gin.H{
			"numbers": request.Numbers,
			"sum":     sum,
		})
	})

	r.POST("/calculate/:operation", func(c *gin.Context) {
		operation := c.Param("operation")

		var request struct {
			A int `json:"a"`
			B int `json:"b"`
		}

		if err := c.ShouldBindJSON(&request); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
			return
		}

		var result int
		switch operation {
		case "add":
			result = calc.Add(request.A, request.B)
		case "multiply":
			result = calc.Multiply(request.A, request.B)
		default:
			c.JSON(http.StatusBadRequest, gin.H{"error": "Unsupported operation"})
			return
		}

		c.JSON(http.StatusOK, gin.H{
			"operation": operation,
			"a":         request.A,
			"b":         request.B,
			"result":    result,
			"history":   calc.GetHistory(),
		})
	})

	r.GET("/users/:id", func(c *gin.Context) {
		// Demo endpoint for testing
		user := User{
			ID:    1,
			Name:  "Test User",
			Email: "test@example.com",
		}
		c.JSON(http.StatusOK, user)
	})

	// Start server
	port := ":8080"
	log.Printf("Server starting on port %s", port)
	log.Printf("Greeting: %s", CreateGreeting("Go devcontainer"))

	if err := r.Run(port); err != nil {
		log.Fatal("Failed to start server:", err)
	}
}
