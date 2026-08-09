package Test_Spec_Assertions

import (
	"encoding/json"
)

func UnsafeStringify(x interface{}) string {
	bytes, err := json.MarshalIndent(x, "", "  ")
	if err != nil {
		return ""
	}
	return string(bytes)
}
