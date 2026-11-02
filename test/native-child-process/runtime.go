package gopurs_runtime

import "unsafe"

const (
	TypeAny = iota
	TypeString
)

type Value struct {
	Type      int
	UnsafePtr unsafe.Pointer
}

func Box(x any) Value {
	if v, ok := x.(Value); ok {
		return v
	}
	p := new(any)
	*p = x
	return Value{TypeAny, unsafe.Pointer(p)}
}
func Any(x any) Value { return Box(x) }
func (v Value) PtrVal() any {
	if v.UnsafePtr == nil {
		return nil
	}
	return *(*any)(v.UnsafePtr)
}
func Unbox[T any](x any) T {
	if v, ok := x.(Value); ok {
		x = v.PtrVal()
	}
	if r, ok := x.(T); ok {
		return r
	}
	var zero T
	return zero
}
func RecordGet(Value, string) Value { return Value{} }
