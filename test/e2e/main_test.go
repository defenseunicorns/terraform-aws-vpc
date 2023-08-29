package e2e_test

import (
	"context"
	"e2e_test/test/e2e/utils"
	"os"
	"testing"
	"time"
)

// TestMain is the entry point for all tests. We are using a custom one so that we can log a message to the console every few seconds. Without this there is a risk of GitHub Actions killing the test run if it believes it is hung.
func TestMain(m *testing.M) {
	ctx, cancel := context.WithCancel(context.Background())
	go func() {
		for {
			select {
			case <-ctx.Done():
				return
			default:
				utils.DoLog("The test is still running! Don't kill me!")
			}
			time.Sleep(10 * time.Second)
		}
	}()
	exitVal := m.Run()
	cancel()
	os.Exit(exitVal)
}
