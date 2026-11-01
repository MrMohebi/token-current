package protocol

import (
	"crypto/rand"
	"crypto/subtle"
	"encoding/hex"
	"errors"
	"math"
	"net"
	"net/url"
	"strings"
	"time"
)

type Counts struct {
	Input      int64 `json:"input"`
	Output     int64 `json:"output"`
	CacheRead  int64 `json:"cacheRead"`
	CacheWrite int64 `json:"cacheWrite"`
}

func (c Counts) Total() int64 { return c.Input + c.Output }
func (c Counts) Add(b Counts) Counts {
	return Counts{c.Input + b.Input, c.Output + b.Output, c.CacheRead + b.CacheRead, c.CacheWrite + b.CacheWrite}
}
func (c Counts) High(b Counts) Counts {
	return Counts{max(c.Input, b.Input), max(c.Output, b.Output), max(c.CacheRead, b.CacheRead), max(c.CacheWrite, b.CacheWrite)}
}
func (c Counts) Delta(b Counts) Counts {
	return Counts{max(0, c.Input-b.Input), max(0, c.Output-b.Output), max(0, c.CacheRead-b.CacheRead), max(0, c.CacheWrite-b.CacheWrite)}
}
func (c Counts) Valid() bool {
	return c.Input >= 0 && c.Output >= 0 && c.CacheRead >= 0 && c.CacheWrite >= 0 && c.CacheRead <= 1e15 && c.CacheWrite <= 1e15 && c.Input <= 1e15 && c.Output <= 1e15 && c.CacheRead+c.CacheWrite <= c.Input
}

type Provider struct {
	Health string  `json:"health"`
	Rate   float64 `json:"rate"`
	Totals Counts  `json:"totals"`
}

type Snapshot struct {
	ID         string              `json:"id"`
	Name       string              `json:"name"`
	Platform   string              `json:"platform"`
	BootID     string              `json:"bootID"`
	Sequence   uint64              `json:"sequence"`
	Day        string              `json:"day"`
	ObservedAt float64             `json:"observedAt"`
	Providers  map[string]Provider `json:"providers"`
}

func (s Snapshot) Validate(now time.Time) error {
	if len(s.ID) < 8 || len(s.ID) > 80 || len(s.Name) == 0 || len(s.Name) > 80 || len(s.Platform) > 32 || len(s.BootID) < 8 || len(s.BootID) > 80 || s.Sequence == 0 {
		return errors.New("invalid machine identity")
	}
	day, err := time.Parse("2006-01-02", s.Day)
	if err != nil || math.IsNaN(s.ObservedAt) || math.IsInf(s.ObservedAt, 0) || s.ObservedAt < 1 || s.ObservedAt > float64(now.Unix()+300) || time.Unix(int64(s.ObservedAt), 0).UTC().Format("2006-01-02") != day.Format("2006-01-02") {
		return errors.New("invalid sample time; check the machine clock")
	}
	if len(s.Providers) != 2 {
		return errors.New("expected Claude and Codex usage")
	}
	for _, name := range []string{"claude", "codex"} {
		p, ok := s.Providers[name]
		if !ok || !p.Totals.Valid() || math.IsNaN(p.Rate) || math.IsInf(p.Rate, 0) || p.Rate < 0 || p.Rate > 1e12 {
			return errors.New("invalid usage counters")
		}
		switch p.Health {
		case "ready", "waiting", "missing", "unsupported", "permissionDenied", "paused", "importing":
		default:
			return errors.New("invalid source status")
		}
	}
	return nil
}

type Machine struct {
	ID         string    `json:"id"`
	Name       string    `json:"name"`
	Platform   string    `json:"platform"`
	ReceivedAt float64   `json:"receivedAt"`
	Online     bool      `json:"online"`
	Snapshot   *Snapshot `json:"snapshot"`
}
type Mesh struct {
	ServerTime float64   `json:"serverTime"`
	Machines   []Machine `json:"machines"`
}
type Enrollment struct {
	ID    string `json:"id"`
	Token string `json:"token"`
}

func ID() string {
	b := make([]byte, 16)
	if _, err := rand.Read(b); err != nil {
		panic(err)
	}
	return hex.EncodeToString(b)
}
func Secret() string { return ID() + ID() }
func EqualSecret(a, b string) bool {
	return len(a) == len(b) && subtle.ConstantTimeCompare([]byte(a), []byte(b)) == 1
}

// HTTP is acceptable only on loopback or encrypted Tailscale IPs. Everything else requires HTTPS.
func Endpoint(raw string) (*url.URL, error) {
	u, err := url.Parse(strings.TrimRight(strings.TrimSpace(raw), "/"))
	if err != nil || u.Host == "" || u.User != nil || u.RawQuery != "" || u.Fragment != "" || (u.Path != "" && u.Path != "/") {
		return nil, errors.New("use a server origin such as https://machine.tailnet.ts.net:8790")
	}
	if u.Scheme == "https" {
		return u, nil
	}
	host := u.Hostname()
	ip := net.ParseIP(host)
	if u.Scheme == "http" && (host == "localhost" || (ip != nil && (ip.IsLoopback() || IsTailscaleIP(ip)))) {
		return u, nil
	}
	return nil, errors.New("HTTPS is required except on loopback and Tailscale IP addresses")
}
func IsTailscaleIP(ip net.IP) bool {
	_, v4, _ := net.ParseCIDR("100.64.0.0/10")
	_, v6, _ := net.ParseCIDR("fd7a:115c:a1e0::/48")
	return v4.Contains(ip) || v6.Contains(ip)
}
