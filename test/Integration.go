package Test_Integration

import (
	"fmt"
	"gopurs/output/gopurs_runtime"
	"os"
)

// The opaque ChildProcess supplies this native cleanup operation. A cleanup
// failure is fatal: Aff cancellation cannot safely continue with a live writer.
func TerminateAndWaitImpl(process interface{}) func(func() bool) func(func() interface{}) func() interface{} {
	return func(_ func() bool) func(func() interface{}) func() interface{} {
		return func(done func() interface{}) func() interface{} {
			return func() interface{} {
				child := gopurs_runtime.Unbox[interface{ TerminateAndWait() error }](process)
				if err := child.TerminateAndWait(); err != nil {
					// Aff recovers panics and discards canceler errors. Stop the
					// runner rather than allowing another case to reuse this directory.
					fmt.Fprintln(os.Stderr, "integration cancellation failed:", err)
					os.Exit(1)
				}
				return done()
			}
		}
	}
}
