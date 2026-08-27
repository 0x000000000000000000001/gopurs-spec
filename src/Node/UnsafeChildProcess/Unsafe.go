package Node_UnsafeChildProcess_Unsafe

import (
	"os/exec"
	"gopurs/output/gopurs_runtime"
	"io"
	"reflect"
)

type ChildProcess struct {
	*Node_EventEmitter_EventEmitter
	Stdout interface{}
	Stderr interface{}
	Stdin  interface{}
	Pid    interface{}
}

func extractAny(val interface{}) any {
	if v, ok := val.(gopurs_runtime.Value); ok {
		if v.Type == gopurs_runtime.TypeAny {
			return *(*any)(v.UnsafePtr)
		}
	}
	return val
}

func pumpStream(r io.Reader, streamVal gopurs_runtime.Value) {
	buf := make([]byte, 4096)
	for {
		n, err := r.Read(buf)
		if n > 0 {
			chunk := make([]byte, n)
			copy(chunk, buf[:n])
			Node_EventEmitter_GopursUnsafeEmitFn2(streamVal, "data", gopurs_runtime.Box(chunk), nil)
		}
		if err != nil {
			break
		}
	}
	Node_EventEmitter_GopursUnsafeEmitFn1(streamVal, "end", nil)
}

func SpawnOptsImpl(command string, args []string, opts interface{}) interface{} {
	cmd := exec.Command(command, args...)
	// Set CWD if provided
	if opts != nil {
		if optsVal, ok := opts.(gopurs_runtime.Value); ok {
			cwdVal := gopurs_runtime.RecordGet(optsVal, "cwd")
			if cwdVal.Type == gopurs_runtime.TypeString {
				cwdStr := gopurs_runtime.Unbox[string](cwdVal)
				if cwdStr != "" && cwdStr != "undefined" {
					cmd.Dir = cwdStr
				}
			} else if cwdVal.Type == gopurs_runtime.TypeAny {
				if ptr := cwdVal.PtrVal(); ptr != nil {
					if str, ok := ptr.(string); ok && str != "" && str != "undefined" {
						cmd.Dir = str
					}
				}
			}
		} else {
			// fallback for standard reflection
			optsAny := extractAny(opts)
			if optsAny != nil {
				val := reflect.ValueOf(optsAny)
				if val.Kind() == reflect.Ptr {
					val = val.Elem()
				}
				if val.Kind() == reflect.Struct {
					cwdField := val.FieldByName("Cwd")
					if cwdField.IsValid() {
						cwdInter := cwdField.Interface()
						if cwdVal, ok := cwdInter.(gopurs_runtime.Value); ok {
							cwdStr := gopurs_runtime.Unbox[string](cwdVal)
							if cwdStr != "" && cwdStr != "undefined" { // rough check
								cmd.Dir = cwdStr
							}
						}
					}
				}
			}
		}
	}

	stdoutPipe, _ := cmd.StdoutPipe()
	stderrPipe, _ := cmd.StderrPipe()
	// stdinPipe, _ := cmd.StdinPipe()

	cp := &ChildProcess{
		EventEmitter: Node_EventEmitter_NewImpl(nil).(*Node_EventEmitter_EventEmitter),
	}
	
	cp.Stdout = Node_Stream_NewPassThrough()
	cp.Stderr = Node_Stream_NewPassThrough()
	
	// Start the command
	err := cmd.Start()
	if err != nil {
		// Emit error
		cpVal := gopurs_runtime.Box(cp)
		Node_EventEmitter_GopursUnsafeEmitFn2(cpVal, "error", gopurs_runtime.Box(err), nil)
		return cp
	}

	cpVal := gopurs_runtime.Box(cp)
	stdoutVal := gopurs_runtime.Box(cp.Stdout)
	stderrVal := gopurs_runtime.Box(cp.Stderr)

	go pumpStream(stdoutPipe, stdoutVal)
	go pumpStream(stderrPipe, stderrVal)

	go func() {
		err := cmd.Wait()
		code := 0
		if err != nil {
			if exitErr, ok := err.(*exec.ExitError); ok {
				code = exitErr.ExitCode()
			} else {
				code = 1
			}
		}
		Node_EventEmitter_GopursUnsafeEmitFn3(cpVal, "close", gopurs_runtime.Box(code), gopurs_runtime.Any(nil), nil)
		Node_EventEmitter_GopursUnsafeEmitFn3(cpVal, "exit", gopurs_runtime.Box(code), gopurs_runtime.Any(nil), nil)
	}()
	
	return cp
}

func UnsafeStdout(cp interface{}) interface{} {
	proc := gopurs_runtime.Unbox[*ChildProcess](cp)
	if proc != nil {
		return proc.Stdout
	}
	return nil
}

func UnsafeStderr(cp interface{}) interface{} {
	proc := gopurs_runtime.Unbox[*ChildProcess](cp)
	if proc != nil {
		return proc.Stderr
	}
	return nil
}

func UnsafeStdin(cp interface{}) interface{} {
	proc := gopurs_runtime.Unbox[*ChildProcess](cp)
	if proc != nil {
		return proc.Stdin
	}
	return nil
}

func ExecCbImpl(_ interface{}) interface{} { return nil }
func ExecFileCbImpl(_ interface{}) interface{} { return nil }
func ExecFileImpl(_ interface{}) interface{} { return nil }
func ExecFileOptsCbImpl(_ interface{}) interface{} { return nil }
func ExecFileOptsImpl(_ interface{}) interface{} { return nil }
func ExecFileSyncImpl(_ interface{}) interface{} { return nil }
func ExecFileSyncOptsImpl(_ interface{}) interface{} { return nil }
func ExecImpl(_ interface{}) interface{} { return nil }
func ExecOptsCbImpl(_ interface{}) interface{} { return nil }
func ExecOptsImpl(_ interface{}) interface{} { return nil }
func ExecSyncImpl(_ interface{}) interface{} { return nil }
func ExecSyncOptsImpl(_ interface{}) interface{} { return nil }
func ForkImpl(_ interface{}) interface{} { return nil }
func ForkOptsImpl(_ interface{}) interface{} { return nil }
func SendCbImpl(_ interface{}) interface{} { return nil }
func SendImpl(_ interface{}) interface{} { return nil }
func SendOptsCbImpl(_ interface{}) interface{} { return nil }
func SendOptsImpl(_ interface{}) interface{} { return nil }
func SpawnImpl(_ interface{}) interface{} { return nil }
func SpawnSyncImpl(_ interface{}) interface{} { return nil }
func SpawnSyncOptsImpl(_ interface{}) interface{} { return nil }
func UnsafeChannelRefImpl(_ interface{}) interface{} { return nil }
func UnsafeChannelUnrefImpl(_ interface{}) interface{} { return nil }

func (cp *ChildProcess) GetEventEmitter() *Node_EventEmitter_EventEmitter {
	return cp.EventEmitter
}
