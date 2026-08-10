package Node_OS

import "os"

func Tmpdir(_ interface{}) interface{} {
    return os.TempDir()
}

func LoadavgImpl(_ interface{}) interface{} { return nil }
func Machine(_ interface{}) interface{} { return nil }
func NetworkInterfacesImpl(_ interface{}) interface{} { return nil }
func Release(_ interface{}) interface{} { return nil }
func SetPriorityImpl(_ interface{}, _ interface{}) interface{} { return nil }
func Totalmem(_ interface{}) interface{} { return nil }
func Type_(_ interface{}) interface{} { return nil }
func Uptime(_ interface{}) interface{} { return nil }
func UserInfoImpl(_ interface{}) interface{} { return nil }
func Version(_ interface{}) interface{} { return nil }
