package Node_UnsafeChildProcess_Unsafe

import (
	"bytes"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"testing"
	"time"
)

func await(t *testing.T, ch <-chan struct{}, what string) {
	t.Helper()
	select {
	case <-ch:
	case <-time.After(3 * time.Second):
		t.Fatalf("timed out waiting for %s", what)
	}
}
func terminator(t *testing.T, cp any) interface{ TerminateAndWait() error } {
	t.Helper()
	process, ok := cp.(interface{ TerminateAndWait() error })
	if !ok {
		t.Fatal("child process has no TerminateAndWait method")
	}
	return process
}
func TestCloseAfterDraining(t *testing.T) {
	p := newProbe()
	p.blockData = true
	gate := filepath.Join(t.TempDir(), "exit")
	cp := SpawnOptsImpl("/bin/sh", []string{"-c", `printf payload; while [ ! -e "$1" ]; do sleep 0.01; done`, "probe", gate}, nil)
	await(t, p.entered, "blocked stdout callback")
	if err := os.WriteFile(gate, nil, 0600); err != nil {
		t.Fatal(err)
	}
	await(t, p.exited, "process exit")
	select {
	case <-p.closed:
		t.Error("close preceded stdout data callback completion")
	default:
	}
	close(p.release)
	await(t, p.closed, "close after stream drain")
	if process, ok := cp.(interface{ TerminateAndWait() error }); ok {
		if err := process.TerminateAndWait(); err != nil {
			t.Fatal(err)
		}
	}
	p.Lock()
	defer p.Unlock()
	t.Logf("event order: %v", p.events)
	index := func(event string) int {
		for i, e := range p.events {
			if e == event {
				return i
			}
		}
		return -1
	}
	closeIndex := index("process:close")
	for _, event := range []string{"stdout:data", "stdout:end", "stderr:end", "process:exit"} {
		if i := index(event); i < 0 || i >= closeIndex {
			t.Errorf("%s must precede close", event)
		}
	}
	if string(p.stdout) != "payload" {
		t.Errorf("stdout = %q", p.stdout)
	}
}
func TestLargeOutputIsExact(t *testing.T) {
	p := newProbe()
	cp := SpawnOptsImpl("/bin/sh", []string{"-c", `dd if=/dev/zero bs=4096 count=64 2>/dev/null; dd if=/dev/zero bs=4096 count=64 1>&2 2>/dev/null; printf stdout-tail; printf stderr-tail >&2`}, nil)
	await(t, p.closed, "large output close")
	if err := terminator(t, cp).TerminateAndWait(); err != nil {
		t.Fatal(err)
	}
	p.Lock()
	defer p.Unlock()
	if !bytes.Equal(p.stdout, append(make([]byte, 256*1024), []byte("stdout-tail")...)) {
		t.Errorf("stdout incomplete: %d bytes", len(p.stdout))
	}
	if !bytes.Equal(p.stderr, append(make([]byte, 256*1024), []byte("stderr-tail")...)) {
		t.Errorf("stderr incomplete: %d bytes", len(p.stderr))
	}
}
func TestTerminateWaitsForDescendantsAndClose(t *testing.T) {
	p := newProbe()
	p.blockData = true
	p.blockClose = true
	pidFile := filepath.Join(t.TempDir(), "descendant.pid")
	cp := SpawnOptsImpl("/bin/sh", []string{"-c", `sleep 60 & echo $! > "$1"; printf ready; wait`, "probe", pidFile}, nil)
	process := terminator(t, cp)
	await(t, p.entered, "descendant creation")
	contents, err := os.ReadFile(pidFile)
	if err != nil {
		t.Fatal(err)
	}
	pid, err := strconv.Atoi(strings.TrimSpace(string(contents)))
	if err != nil {
		t.Fatal(err)
	}
	defer syscall.Kill(pid, syscall.SIGKILL)
	done := make(chan struct{})
	var terminateErr error
	go func() { terminateErr = process.TerminateAndWait(); close(done) }()
	concurrentDone := make(chan struct{})
	var concurrentErr error
	go func() { concurrentErr = process.TerminateAndWait(); close(concurrentDone) }()
	await(t, p.exited, "termination of parent")
	select {
	case <-done:
		t.Error("termination returned before blocked output drained")
	default:
	}
	close(p.release)
	await(t, p.closeEntered, "close callback")
	select {
	case <-done:
		t.Error("termination returned before close callback completed")
	default:
	}
	close(p.allowClose)
	await(t, done, "termination cleanup")
	if terminateErr != nil {
		t.Fatal(terminateErr)
	}
	await(t, concurrentDone, "concurrent termination cleanup")
	if concurrentErr != nil {
		t.Fatal(concurrentErr)
	}
	// Orphaned descendants can briefly remain as zombies; they cannot run or
	// hold output descriptors. Check absence or zombie state on Linux/macOS.
	state, err := exec.Command("ps", "-o", "stat=", "-p", strconv.Itoa(pid)).Output()
	if err == nil && !strings.HasPrefix(strings.TrimSpace(string(state)), "Z") {
		t.Fatalf("descendant still running after cancellation: pid=%d state=%s", pid, state)
	}
	if err := process.TerminateAndWait(); err != nil {
		t.Fatalf("second termination: %v", err)
	}
	p.Lock()
	defer p.Unlock()
	if len(p.events) == 0 || p.events[len(p.events)-1] != "process:close" {
		t.Fatalf("cleanup returned without close: %v", p.events)
	}
}
func TestFailedStartCanBeTerminated(t *testing.T) {
	newProbe()
	cp := SpawnOptsImpl(filepath.Join(t.TempDir(), "missing-command"), nil, nil)
	if err := terminator(t, cp).TerminateAndWait(); err != nil {
		t.Fatal(err)
	}
}
