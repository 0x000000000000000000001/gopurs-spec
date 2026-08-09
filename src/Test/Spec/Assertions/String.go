package Test_Spec_Assertions_String

import (
	"gopurs/output/gopurs_runtime"
	"strings"
)

func _StartsWith(subs string, str string) bool {
	return strings.HasPrefix(str, subs)
}

func _EndsWith(subs string, str string) bool {
	return strings.HasSuffix(str, subs)
}
