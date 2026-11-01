package monitor

import (
	"fmt"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func claude(id string, input, output int, at time.Time) string {
	return fmt.Sprintf(`{"type":"assistant","timestamp":%q,"requestId":"req","message":{"id":%q,"usage":{"input_tokens":%d,"output_tokens":%d,"cache_read_input_tokens":30,"cache_creation_input_tokens":20}}}`, at.Format(time.RFC3339Nano), id, input, output)
}
func appendFile(t *testing.T, path, data string) {
	t.Helper()
	f, e := os.OpenFile(path, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0600)
	if e != nil {
		t.Fatal(e)
	}
	defer f.Close()
	if _, e = f.WriteString(data); e != nil {
		t.Fatal(e)
	}
}
func TestBackfillPartialDedupRestartRotationAndWake(t *testing.T) {
	root := t.TempDir()
	c := filepath.Join(root, "claude")
	x := filepath.Join(root, "codex")
	os.MkdirAll(filepath.Join(c, "projects", "nested"), 0700)
	path := filepath.Join(c, "projects", "nested", "log.jsonl")
	state := filepath.Join(root, "state.json")
	now := time.Now().UTC().Truncate(time.Second)
	appendFile(t, path, claude("one", 100, 10, now)+"\n{\"type\":")
	m, e := New(state, c, x)
	if e != nil {
		t.Fatal(e)
	}
	p, e := m.Tick(now)
	if e != nil {
		t.Fatal(e)
	}
	if p["claude"].Totals.Total() != 160 || p["claude"].Rate != 0 || p["claude"].Health != "ready" {
		t.Fatal(p)
	}
	appendFile(t, path, "\"user\"}\n"+claude("one", 100, 20, now)+"\n"+claude("two", 50, 10, now)+"\n")
	p, e = m.Tick(now.Add(time.Second))
	if e != nil {
		t.Fatal(e)
	}
	if p["claude"].Totals.Total() != 280 || p["claude"].Rate != 12 {
		t.Fatal(p)
	}
	m, e = New(state, c, x)
	if e != nil {
		t.Fatal(e)
	}
	p, e = m.Tick(now.Add(2 * time.Second))
	if e != nil {
		t.Fatal(e)
	}
	if p["claude"].Rate != 0 || p["claude"].Totals.Total() != 280 {
		t.Fatal(p)
	}
	os.WriteFile(path, []byte(claude("one", 100, 20, now)+"\n"+claude("three", 10, 0, now)+"\n"), 0600)
	p, e = m.Tick(now.Add(3 * time.Second))
	if e != nil {
		t.Fatal(e)
	}
	if p["claude"].Totals.Total() != 340 || p["claude"].Rate != 6 {
		t.Fatal(p)
	}
	appendFile(t, path, claude("four", 10, 0, now)+"\n")
	p, e = m.Tick(now.Add(9 * time.Second))
	if e != nil {
		t.Fatal(e)
	}
	if p["claude"].Rate != 0 || p["claude"].Totals.Total() != 400 {
		t.Fatal(p)
	}
	p, e = m.Tick(now.Add(24 * time.Hour))
	if e != nil {
		t.Fatal(e)
	}
	if p["claude"].Totals.Total() != 0 {
		t.Fatal("day rollover", p)
	}
}
func TestCodexCumulativeCacheAndFork(t *testing.T) {
	ctx := Context{}
	meta := `{"type":"session_meta","timestamp":"2026-11-01T10:00:00Z","payload":{"id":"child","forked_from_id":"parent"}}`
	Parse([]byte(meta), "codex", "file", &ctx)
	line := `{"type":"event_msg","timestamp":"2026-11-01T10:01:00Z","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":150,"cached_input_tokens":40,"output_tokens":30,"reasoning_output_tokens":20},"last_token_usage":{"input_tokens":50,"cached_input_tokens":10,"output_tokens":10}}}}`
	o, bad := Parse([]byte(line), "codex", "file", &ctx)
	if bad || o == nil || o.Baseline || o.Counts.Total() != 180 || o.Initial.Input != 100 || o.Initial.Output != 20 {
		t.Fatal(o, bad)
	}
	negative := claude("bad", -1, 10, time.Now())
	if o, bad := Parse([]byte(negative), "claude", "file", &Context{}); o != nil || !bad {
		t.Fatal("negative raw count accepted")
	}
	modern := `{"type":"token_usage_record","timestamp":"2026-11-01T11:00:00Z","payload":{"thread_id":"child","thread_token_usage":{"input_tokens":200,"cached_input_tokens":50,"output_tokens":40}}}`
	o, bad = Parse([]byte(modern), "codex", "file", &ctx)
	if bad || o.Key != "codex:child" || o.Counts.Total() != 240 {
		t.Fatal(o, bad)
	}
}
