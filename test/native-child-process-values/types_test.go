package Node_ChildProcess_Types

import (
	"encoding/json"
	rt "gopurs/output/gopurs_runtime"
	"math"
	"os"
	"testing"
)

func TestKillSignalMatchesJavaScript(t *testing.T) {
	var cases []struct {
		Name, Kind, Special, Text, Branch string
		Number, Expected                  float64
	}
	data, err := os.ReadFile("reference.json")
	if err != nil {
		t.Fatal(err)
	}
	if err := json.Unmarshal(data, &cases); err != nil {
		t.Fatal(err)
	}
	for _, c := range cases {
		t.Run(c.Name, func(t *testing.T) {
			var signal rt.Value
			switch c.Kind {
			case "int":
				signal = rt.Int(int64(c.Number))
			case "number":
				n := c.Number
				switch c.Special {
				case "NaN":
					n = math.NaN()
				case "Infinity":
					n = math.Inf(1)
				case "-Infinity":
					n = math.Inf(-1)
				}
				signal = rt.Float(n)
			case "string":
				signal = rt.Str(c.Text)
			case "boolean":
				signal = rt.Bool(true)
			case "null":
				signal = rt.Any(nil)
			case "undefined":
				signal = rt.Value{}
			default:
				t.Fatalf("unknown case kind %q", c.Kind)
			}
			calls := 0
			token := new(int)
			callback := func(branch string) rt.Value {
				return rt.Func(func(value rt.Value) rt.Value {
					calls++
					if c.Branch != branch {
						t.Errorf("branch %q, want %q", branch, c.Branch)
					}
					if branch == "int" && (value.Type != rt.TypeInt || value.IntVal != int64(c.Expected)) {
						t.Errorf("integer callback = %+v, want %v", value, c.Expected)
					}
					if branch == "string" && (value.Type != rt.TypeString || value.StrVal() != c.Text) {
						t.Errorf("string callback = %q, want %q", value.StrVal(), c.Text)
					}
					return rt.Any(token)
				})
			}
			if c.Branch == "error" {
				defer func() {
					if recover() == nil {
						t.Error("invalid signal did not panic")
					}
					if calls != 0 {
						t.Error("invalid signal invoked callback")
					}
				}()
				FromKillSignalImpl(callback("int"), callback("string"), signal)
				return
			}
			result := FromKillSignalImpl(callback("int"), callback("string"), signal)
			if calls != 1 {
				t.Errorf("callbacks invoked %d times", calls)
			}
			if rt.Unbox[*int](result) != token {
				t.Fatal("callback's opaque result identity was lost")
			}
		})
	}
}
