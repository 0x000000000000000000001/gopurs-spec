package Node_UnsafeChildProcess_Unsafe

// These stubs only provide runtime boxing and synchronous event callbacks.
// Process creation, pipes, Wait, signal delivery, and lifecycle are production code.
import (
	"gopurs/output/gopurs_runtime"
	"sync"
)

type EventEmitter struct {
	probe *eventProbe
	kind  string
}
type eventProbe struct {
	sync.Mutex
	streams                                                    int
	events                                                     []string
	stdout, stderr                                             []byte
	entered, release, exited, closed, closeEntered, allowClose chan struct{}
	blockData, blockClose                                      bool
	dataOnce                                                   sync.Once
}

var activeProbe *eventProbe

func newProbe() *eventProbe {
	p := &eventProbe{entered: make(chan struct{}), release: make(chan struct{}), exited: make(chan struct{}), closed: make(chan struct{}), closeEntered: make(chan struct{}), allowClose: make(chan struct{})}
	activeProbe = p
	return p
}
func Node_EventEmitter_NewImpl(any) any { return &EventEmitter{activeProbe, "process"} }
func Node_Stream_NewPassThrough() any {
	p := activeProbe
	p.streams++
	return &EventEmitter{p, []string{"stdout", "stderr"}[p.streams-1]}
}
func emit(v gopurs_runtime.Value, event string, arg gopurs_runtime.Value) {
	var e *EventEmitter
	switch x := v.PtrVal().(type) {
	case *EventEmitter:
		e = x
	case *ChildProcess:
		e = x.EventEmitter
	}
	p := e.probe
	if e.kind == "stdout" && event == "data" && p.blockData {
		p.dataOnce.Do(func() { close(p.entered) })
		<-p.release
	}
	if event == "close" {
		close(p.closeEntered)
		if p.blockClose {
			<-p.allowClose
		}
	}
	p.Lock()
	p.events = append(p.events, e.kind+":"+event)
	if event == "data" {
		bytes := gopurs_runtime.Unbox[[]byte](arg)
		if e.kind == "stdout" {
			p.stdout = append(p.stdout, bytes...)
		} else {
			p.stderr = append(p.stderr, bytes...)
		}
	}
	p.Unlock()
	switch event {
	case "exit":
		close(p.exited)
	case "close":
		close(p.closed)
	}
}
func Node_EventEmitter_GopursUnsafeEmitFn1(v gopurs_runtime.Value, e string, _ any) {
	emit(v, e, gopurs_runtime.Value{})
}
func Node_EventEmitter_GopursUnsafeEmitFn2(v gopurs_runtime.Value, e string, a gopurs_runtime.Value, _ any) {
	emit(v, e, a)
}
func Node_EventEmitter_GopursUnsafeEmitFn3(v gopurs_runtime.Value, e string, a, _ gopurs_runtime.Value, _ any) {
	emit(v, e, a)
}
