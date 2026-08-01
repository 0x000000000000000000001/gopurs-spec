package Test_Spec_Console

import (
	"fmt"
)

func Write(s string, _ interface{}) interface{} {
	fmt.Print(s)
	return nil
}
