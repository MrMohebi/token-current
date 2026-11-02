package server

import (
	"bytes"
	"encoding/json"
	"github.com/MrMohebi/token-current/network/internal/protocol"
	"net/http/httptest"
	"path/filepath"
	"testing"
	"time"
)

func call(s *Server, method, path, token string, body any) *httptest.ResponseRecorder {
	data, _ := json.Marshal(body)
	r := httptest.NewRequest(method, path, bytes.NewReader(data))
	if token != "" {
		r.Header.Set("Authorization", "Bearer "+token)
	}
	w := httptest.NewRecorder()
	s.Handler().ServeHTTP(w, r)
	return w
}
func enrollment(t *testing.T, s *Server) protocol.Enrollment {
	t.Helper()
	w := call(s, "POST", "/api/v1/instances", s.AdminToken(), map[string]string{"name": "Test machine", "platform": "linux"})
	if w.Code != 201 {
		t.Fatal(w.Code, w.Body.String())
	}
	var e protocol.Enrollment
	json.Unmarshal(w.Body.Bytes(), &e)
	return e
}
func snapshot(id string, now time.Time) protocol.Snapshot {
	return protocol.Snapshot{ID: id, Name: "Test machine", Platform: "linux", BootID: "boot-one", Sequence: 1, Day: now.UTC().Format("2006-01-02"), ObservedAt: float64(now.Unix()), Providers: map[string]protocol.Provider{"claude": {Health: "ready", Rate: 30, Totals: protocol.Counts{Input: 100, Output: 20}}, "codex": {Health: "missing"}}}
}
func TestEnrollmentAuthReplayRestartAndRevocation(t *testing.T) {
	path := filepath.Join(t.TempDir(), "relay.json")
	s, err := NewRelay(path)
	if err != nil {
		t.Fatal(err)
	}
	now := time.Now()
	s.now = func() time.Time { return now }
	if w := call(s, "GET", "/api/v1/mesh", "", nil); w.Code != 401 {
		t.Fatal(w.Code)
	}
	e := enrollment(t, s)
	sample := snapshot(e.ID, now)
	if w := call(s, "GET", "/api/v1/mesh", e.Token, nil); w.Code != 401 {
		t.Fatal("device gained admin access")
	}
	if w := call(s, "POST", "/api/v1/report", e.Token, sample); w.Code != 204 {
		t.Fatal(w.Code, w.Body.String())
	}
	if !s.mesh().Machines[0].Online {
		t.Fatal("not online")
	}
	now = now.Add(20 * time.Second)
	if w := call(s, "POST", "/api/v1/report", e.Token, sample); w.Code != 204 {
		t.Fatal(w.Code)
	}
	if s.mesh().Machines[0].Online {
		t.Fatal("replay refreshed heartbeat")
	}
	sample.BootID = "boot-two"
	sample.Sequence = 1
	sample.ObservedAt = float64(now.Unix())
	if w := call(s, "POST", "/api/v1/report", e.Token, sample); w.Code != 204 {
		t.Fatal(w.Code)
	}
	sample.BootID = "boot-one"
	sample.Sequence = 99
	if w := call(s, "POST", "/api/v1/report", e.Token, sample); w.Code != 409 {
		t.Fatal("retired boot accepted", w.Code)
	}
	s2, err := NewRelay(path)
	if err != nil {
		t.Fatal(err)
	}
	if s2.mesh().Machines[0].Snapshot.BootID != "boot-two" {
		t.Fatal("restart lost snapshot")
	}
	w := call(s2, "POST", "/api/v1/instances/"+e.ID+"/rotate", s2.AdminToken(), nil)
	if w.Code != 200 {
		t.Fatal(w.Code)
	}
	var rotated protocol.Enrollment
	json.Unmarshal(w.Body.Bytes(), &rotated)
	if w := call(s2, "POST", "/api/v1/report", e.Token, sample); w.Code != 401 {
		t.Fatal("old token accepted")
	}
	if w := call(s2, "DELETE", "/api/v1/instances/"+e.ID, s2.AdminToken(), nil); w.Code != 204 {
		t.Fatal(w.Code)
	}
	if w := call(s2, "POST", "/api/v1/report", rotated.Token, sample); w.Code != 401 {
		t.Fatal("removed machine accepted")
	}
}
func TestWrongIdentityInvalidAndOversizedReports(t *testing.T) {
	s, _ := NewRelay(filepath.Join(t.TempDir(), "relay.json"))
	e := enrollment(t, s)
	sample := snapshot("another-machine", time.Now())
	if w := call(s, "POST", "/api/v1/report", e.Token, sample); w.Code != 403 {
		t.Fatal(w.Code)
	}
	sample.ID = e.ID
	p := sample.Providers["claude"]
	p.Totals.Input = -1
	sample.Providers["claude"] = p
	if w := call(s, "POST", "/api/v1/report", e.Token, sample); w.Code != 400 {
		t.Fatal(w.Code)
	}
	r := httptest.NewRequest("POST", "/api/v1/report", bytes.NewBufferString(`{"padding":"`+string(bytes.Repeat([]byte("x"), 70000))+`"}`))
	r.Header.Set("Authorization", "Bearer "+e.Token)
	w := httptest.NewRecorder()
	s.Handler().ServeHTTP(w, r)
	if w.Code != 400 {
		t.Fatal(w.Code)
	}
}
func TestDirectReadOnly(t *testing.T) {
	sample := snapshot("direct-machine", time.Now())
	s := NewDirect(protocol.Secret(), func() protocol.Snapshot { return sample })
	if w := call(s, "GET", "/api/v1/mesh", s.AdminToken(), nil); w.Code != 200 {
		t.Fatal(w.Code)
	}
	if w := call(s, "POST", "/api/v1/instances", s.AdminToken(), map[string]string{"name": "x"}); w.Code != 404 {
		t.Fatal("direct enroll allowed")
	}
}

func TestTailnetAPIReadOnlyWithoutToken(t *testing.T) {
	sample := snapshot("tailnet-machine", time.Now())
	s := NewTailnet(func() protocol.Snapshot { return sample })
	for _, path := range []string{"/api/v1/info", "/api/v1/mesh", "/api/v1/snapshot"} {
		if w := call(s, "GET", path, "", nil); w.Code != 200 {
			t.Fatal(path, w.Code)
		}
	}
	for _, path := range []string{"/api/v1/instances", "/api/v1/report"} {
		if w := call(s, "POST", path, "", nil); w.Code != 401 {
			t.Fatal("tailnet allowed writes", path, w.Code)
		}
	}
	// Neither the legacy listener nor the relay silently loses authentication.
	legacy := NewDirect(protocol.Secret(), func() protocol.Snapshot { return sample })
	if w := call(legacy, "GET", "/api/v1/mesh", "", nil); w.Code != 401 {
		t.Fatal("legacy listener became public")
	}
}
