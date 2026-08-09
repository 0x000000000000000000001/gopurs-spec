package Test_Spec_Runner

import (
	"os"
)

func Exit(code int) func() interface{} {
	return func() interface{} {
		os.Exit(code)
		return nil
	}
}
