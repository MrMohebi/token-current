package tailnet

import "testing"

func TestURLUsesPrivateIPWithoutMagicDNS(t *testing.T) {
	for _, test := range []struct {
		ips  []string
		want string
	}{
		{[]string{"100.72.15.20"}, "http://100.72.15.20:8791"},
		{[]string{"fd7a:115c:a1e0::1"}, "http://[fd7a:115c:a1e0::1]:8791"},
		{[]string{"192.168.1.2"}, ""},
	} {
		if got := (Peer{TailscaleIPs: test.ips}).URL(); got != test.want {
			t.Fatalf("%v: %s", test.ips, got)
		}
	}
}
