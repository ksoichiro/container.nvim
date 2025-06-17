package main

import (
	"strings"
	"unicode"
)

// Reverse returns the reversed string
func Reverse(s string) string {
	runes := []rune(s)
	for i, j := 0, len(runes)-1; i < j; i, j = i+1, j-1 {
		runes[i], runes[j] = runes[j], runes[i]
	}
	return string(runes)
}

// IsPalindrome checks if a string is a palindrome
func IsPalindrome(s string) bool {
	s = strings.ToLower(s)
	// Remove non-alphanumeric characters
	var cleaned strings.Builder
	for _, r := range s {
		if unicode.IsLetter(r) || unicode.IsDigit(r) {
			cleaned.WriteRune(r)
		}
	}
	cleanedStr := cleaned.String()
	return cleanedStr == Reverse(cleanedStr)
}

// CountWords counts the number of words in a string
func CountWords(s string) int {
	if s == "" {
		return 0
	}
	words := strings.Fields(s)
	return len(words)
}

// TitleCase converts a string to title case
func TitleCase(s string) string {
	words := strings.Fields(s)
	for i, word := range words {
		if len(word) > 0 {
			words[i] = strings.ToUpper(string(word[0])) + strings.ToLower(word[1:])
		}
	}
	return strings.Join(words, " ")
}

// Contains checks if a string contains a substring (case insensitive)
func Contains(s, substr string) bool {
	return strings.Contains(strings.ToLower(s), strings.ToLower(substr))
}
