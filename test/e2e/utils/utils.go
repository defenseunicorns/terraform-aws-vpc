// Package utils is a package that contains utility functions for the e2e tests.
package utils

import (
	"fmt"
	"time"
)

// DoLog logs the given arguments to the given writer, along with a timestamp.
func DoLog(args ...interface{}) {
	date := time.Now()
	prefix := fmt.Sprintf("%s:", date.Format(time.RFC3339))
	allArgs := append([]interface{}{prefix}, args...)
	fmt.Println(allArgs...) //nolint:forbidigo
}
