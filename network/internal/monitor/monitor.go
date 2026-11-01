package monitor

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"github.com/MrMohebi/token-current/network/internal/persist"
	"github.com/MrMohebi/token-current/network/internal/protocol"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"sort"
	"time"
)

type checkpoint struct {
	Offset       int64
	Prefix       string
	PrefixLength int
	Context      Context
	Discard      bool
	Recognized   bool
	Unsupported  bool
	Backfill     bool
}
type state struct {
	Day     string
	Totals  map[string]protocol.Counts
	Records map[string]protocol.Counts
	Files   map[string]*checkpoint
}
type receipt struct {
	Time     time.Time
	Provider string
	Tokens   int64
}
type Monitor struct {
	path          string
	roots         map[string][]string
	state         state
	files         map[string]string
	nextDiscovery time.Time
	lastTick      time.Time
	initial       bool
	receipts      []receipt
}

func New(path, claudeHome, codexHome string) (*Monitor, error) {
	m := &Monitor{path: path, roots: map[string][]string{
		"claude": {filepath.Join(claudeHome, "projects")},
		"codex":  {filepath.Join(codexHome, "sessions"), filepath.Join(codexHome, "archived_sessions")},
	}, initial: true}
	if err := persist.Load(path, &m.state); err != nil && !errors.Is(err, os.ErrNotExist) {
		return nil, err
	}
	if m.state.Totals == nil {
		m.state.Totals = map[string]protocol.Counts{}
	}
	if m.state.Records == nil {
		m.state.Records = map[string]protocol.Counts{}
	}
	if m.state.Files == nil {
		m.state.Files = map[string]*checkpoint{}
	}
	return m, nil
}

func (m *Monitor) Tick(now time.Time) (map[string]protocol.Provider, error) {
	day := now.UTC().Format("2006-01-02")
	start, _ := time.Parse("2006-01-02", day)
	dirty := false
	if m.state.Day != day {
		m.state.Day = day
		m.state.Totals = map[string]protocol.Counts{}
		m.nextDiscovery = time.Time{}
		dirty = true
	}
	suppress := m.initial || (!m.lastTick.IsZero() && (now.Sub(m.lastTick) > 5*time.Second || now.Before(m.lastTick)))
	if suppress {
		m.receipts = nil
	}
	m.lastTick = now
	health := map[string]string{}
	for provider, roots := range m.roots {
		health[provider] = "missing"
		for _, root := range roots {
			if f, e := os.Open(root); e == nil {
				health[provider] = "waiting"
				f.Close()
			} else if errors.Is(e, os.ErrPermission) {
				health[provider] = "permissionDenied"
			}
		}
	}
	if !now.Before(m.nextDiscovery) {
		m.files = map[string]string{}
		for provider, roots := range m.roots {
			for _, root := range roots {
				_ = filepath.WalkDir(root, func(path string, d fs.DirEntry, err error) error {
					if err != nil {
						if errors.Is(err, os.ErrPermission) {
							health[provider] = "permissionDenied"
						}
						return nil
					}
					if d.Type()&os.ModeSymlink != 0 {
						if d.IsDir() {
							return filepath.SkipDir
						}
						return nil
					}
					if !d.IsDir() && filepath.Ext(path) == ".jsonl" {
						if info, e := d.Info(); e == nil && !info.ModTime().Before(start) {
							m.files[path] = provider
						}
					}
					return nil
				})
			}
		}
		m.nextDiscovery = now.Add(5 * time.Second)
	}
	paths := make([]string, 0, len(m.files))
	for path := range m.files {
		paths = append(paths, path)
	}
	sort.Strings(paths)
	importing := false
	for _, path := range paths {
		provider := m.files[path]
		cp := m.state.Files[path]
		if cp == nil {
			cp = &checkpoint{Backfill: m.initial}
			m.state.Files[path] = cp
			dirty = true
		}
		if suppress {
			cp.Backfill = true
		}
		changed, err := m.consume(path, provider, cp, start, now)
		if err != nil {
			if errors.Is(err, os.ErrPermission) {
				health[provider] = "permissionDenied"
			} else {
				health[provider] = "unsupported"
			}
			continue
		}
		dirty = dirty || changed
		if cp.Recognized {
			health[provider] = "ready"
		} else if cp.Unsupported && health[provider] != "ready" {
			health[provider] = "unsupported"
		}
		importing = importing || cp.Backfill
	}
	m.initial = false
	kept := m.receipts[:0]
	for _, r := range m.receipts {
		if now.Sub(r.Time) < 10*time.Second && !now.Before(r.Time) {
			kept = append(kept, r)
		}
	}
	m.receipts = kept
	result := map[string]protocol.Provider{}
	for _, name := range []string{"claude", "codex"} {
		var rate float64
		for _, r := range m.receipts {
			if r.Provider == name {
				rate += float64(r.Tokens) / 10
			}
		}
		status := health[name]
		if importing {
			status = "importing"
			rate = 0
		}
		if status != "ready" {
			rate = 0
		}
		result[name] = protocol.Provider{Health: status, Rate: rate, Totals: m.state.Totals[name]}
	}
	if dirty {
		if err := persist.Save(m.path, m.state); err != nil {
			return nil, err
		}
	}
	return result, nil
}

func (m *Monitor) consume(path, provider string, cp *checkpoint, dayStart, now time.Time) (bool, error) {
	f, err := os.Open(path)
	if err != nil {
		return false, err
	}
	defer f.Close()
	info, err := f.Stat()
	if err != nil {
		return false, err
	}
	length := cp.PrefixLength
	if length == 0 {
		length = int(min(256, info.Size()))
	}
	prefix := make([]byte, length)
	n, _ := io.ReadFull(f, prefix)
	prefix = prefix[:n]
	hash := sha256.Sum256(prefix)
	fingerprint := hex.EncodeToString(hash[:])
	if info.Size() < cp.Offset || (cp.PrefixLength > 0 && cp.Prefix != fingerprint) {
		backfill := cp.Backfill
		*cp = checkpoint{Backfill: backfill}
	}
	dirty := cp.Prefix != fingerprint || cp.PrefixLength != len(prefix)
	cp.Prefix = fingerprint
	cp.PrefixLength = len(prefix)
	if _, err = f.Seek(cp.Offset, 0); err != nil {
		return false, err
	}
	data, err := io.ReadAll(io.LimitReader(f, 2<<20))
	if err != nil {
		return false, err
	}
	begin := 0
	live := !cp.Backfill
	for i, b := range data {
		if b == '\n' {
			if cp.Discard {
				cp.Discard = false
			} else if i > begin {
				observation, bad := Parse(bytes.TrimSpace(data[begin:i]), provider, path, &cp.Context)
				if bad {
					cp.Unsupported = true
				}
				if observation != nil {
					cp.Recognized = true
					cp.Unsupported = false
					old := m.state.Records[observation.Key]
					base := old
					if old == (protocol.Counts{}) && observation.Initial != nil {
						base = *observation.Initial
					}
					high := observation.Counts.High(base)
					delta := high.Delta(base)
					m.state.Records[observation.Key] = high
					if !observation.Baseline && !observation.Time.Before(dayStart) && observation.Time.Before(dayStart.Add(24*time.Hour)) {
						m.state.Totals[provider] = m.state.Totals[provider].Add(delta)
						if live && delta.Total() > 0 {
							m.receipts = append(m.receipts, receipt{now, provider, delta.Total()})
						}
					}
				}
			}
			begin = i + 1
		}
	}
	if begin == 0 && len(data) == 2<<20 {
		begin = len(data)
		cp.Discard = true
	}
	if begin > 0 {
		cp.Offset += int64(begin)
		dirty = true
	}
	if cp.Offset >= info.Size() || len(data) < 2<<20 {
		cp.Backfill = false
	}
	return dirty, nil
}
