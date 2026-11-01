package protocol

import "testing"

func TestEndpoint(t *testing.T) {
	for _, s := range []string{"http://127.0.0.1:8790", "http://[::1]:8790", "http://100.64.0.1:8790", "https://server.tail.ts.net:8790"} {
		if _, e := Endpoint(s); e != nil {
			t.Fatal(s, e)
		}
	}
	for _, s := range []string{"http://192.168.1.1", "http://example.com", "https://user:password@example.com", "https://example.com/path", "https://example.com?token=secret"} {
		if _, e := Endpoint(s); e == nil {
			t.Fatal(s)
		}
	}
}
func TestInvalidCounterOverflow(t *testing.T) {
	if (Counts{Input: 100, CacheRead: 9223372036854775807, CacheWrite: 1}).Valid() {
		t.Fatal("overflow accepted")
	}
}
