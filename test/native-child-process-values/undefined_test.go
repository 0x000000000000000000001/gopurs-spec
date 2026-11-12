package Node_ChildProcess

import (
	rt "gopurs/output/gopurs_runtime"
	"testing"
)

func TestUndefinedIsNotNull(t *testing.T) {
	marker := rt.ForeignValue(Undefined)
	if marker == nil || !rt.IsForeignUndefined(marker) {
		t.Fatal("undefined lost its distinct marker")
	}
	if rt.IsForeignUndefined(rt.ForeignValue(rt.Any(nil))) {
		t.Fatal("native nil became undefined")
	}
	if rt.Box(marker).Type != 0 {
		t.Fatal("undefined marker did not round-trip")
	}
}
