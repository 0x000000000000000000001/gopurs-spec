package Node_ChildProcess_Types

import (
	"gopurs/output/gopurs_runtime"
	"math"
)

// These helpers support Spec's node-child-process test dependency, not its
// complete API. Keep the number/string dispatch of upstream Types.js.
func FromKillSignalImpl(fromInt, fromString, signal gopurs_runtime.Value) gopurs_runtime.Value {
	switch signal.Type {
	case gopurs_runtime.TypeInt:
		return gopurs_runtime.Apply(fromInt, gopurs_runtime.Int(int64(int32(signal.IntVal))))
	case gopurs_runtime.TypeFloat:
		n := signal.FloatVal()
		if math.IsNaN(n) || math.IsInf(n, 0) {
			n = 0
		}
		n = math.Mod(math.Trunc(n), 4294967296)
		if n >= 2147483648 {
			n -= 4294967296
		}
		if n < -2147483648 {
			n += 4294967296
		}
		return gopurs_runtime.Apply(fromInt, gopurs_runtime.Int(int64(n)))
	case gopurs_runtime.TypeString:
		return gopurs_runtime.Apply(fromString, signal)
	default:
		panic("Impossible. Got kill signal that was neither int nor string")
	}
}
