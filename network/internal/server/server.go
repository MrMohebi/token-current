package server

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"github.com/MrMohebi/token-current/network/internal/persist"
	"github.com/MrMohebi/token-current/network/internal/protocol"
	"github.com/MrMohebi/token-current/network/internal/web"
	"io"
	"net/http"
	"os"
	"sort"
	"strings"
	"sync"
	"time"
)

type Device struct {
	ID           string             `json:"id"`
	Name         string             `json:"name"`
	Platform     string             `json:"platform"`
	TokenHash    string             `json:"tokenHash"`
	ReceivedAt   float64            `json:"receivedAt"`
	Snapshot     *protocol.Snapshot `json:"snapshot"`
	RetiredBoots []string           `json:"retiredBoots,omitempty"`
}
type state struct {
	AdminToken string             `json:"adminToken"`
	Devices    map[string]*Device `json:"devices"`
}
type Server struct {
	mu     sync.Mutex
	state  state
	path   string
	now    func() time.Time
	direct func() protocol.Snapshot
}

func NewRelay(path string) (*Server, error) {
	s := &Server{path: path, now: time.Now}
	if e := persist.Load(path, &s.state); e != nil {
		if !errors.Is(e, os.ErrNotExist) {
			return nil, e
		}
		s.state = state{AdminToken: protocol.Secret(), Devices: map[string]*Device{}}
		if e = persist.Save(path, s.state); e != nil {
			return nil, e
		}
	}
	if len(s.state.AdminToken) < 32 || s.state.Devices == nil {
		return nil, errors.New("invalid relay state")
	}
	return s, nil
}
func NewDirect(token string, get func() protocol.Snapshot) *Server {
	return &Server{state: state{AdminToken: token, Devices: map[string]*Device{}}, now: time.Now, direct: get}
}
func (s *Server) AdminToken() string { return s.state.AdminToken }
func tokenHash(token string) string {
	sum := sha256.Sum256([]byte(token))
	return hex.EncodeToString(sum[:])
}

func (s *Server) Handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, r *http.Request) { write(w, 200, map[string]bool{"ok": true}) })
	mux.Handle("/", web.Handler())
	mux.HandleFunc("/api/", s.api)
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("X-Content-Type-Options", "nosniff")
		w.Header().Set("Referrer-Policy", "no-referrer")
		w.Header().Set("Content-Security-Policy", "default-src 'self'; script-src 'self'; style-src 'self'; connect-src 'self'; img-src 'self' data:; object-src 'none'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'")
		w.Header().Set("Cache-Control", "no-store")
		mux.ServeHTTP(w, r)
	})
}

func (s *Server) api(w http.ResponseWriter, r *http.Request) {
	token := strings.TrimPrefix(r.Header.Get("Authorization"), "Bearer ")
	if token == "" || token == r.Header.Get("Authorization") {
		writeError(w, 401, "a bearer token is required")
		return
	}
	if r.Method == "POST" && r.URL.Path == "/api/v1/report" && s.direct == nil {
		s.report(w, r, token)
		return
	}
	if !protocol.EqualSecret(token, s.state.AdminToken) {
		writeError(w, 401, "invalid management token")
		return
	}
	switch {
	case r.Method == "GET" && r.URL.Path == "/api/v1/info":
		mode := "relay"
		if s.direct != nil {
			mode = "direct"
		}
		write(w, 200, map[string]string{"mode": mode, "version": "1"})
	case r.Method == "GET" && r.URL.Path == "/api/v1/mesh":
		write(w, 200, s.mesh())
	case r.Method == "GET" && r.URL.Path == "/api/v1/snapshot" && s.direct != nil:
		write(w, 200, s.direct())
	case r.Method == "POST" && r.URL.Path == "/api/v1/instances" && s.direct == nil:
		s.enroll(w, r)
	case r.Method == "DELETE" && strings.HasPrefix(r.URL.Path, "/api/v1/instances/") && s.direct == nil:
		s.remove(w, r)
	case r.Method == "POST" && strings.HasPrefix(r.URL.Path, "/api/v1/instances/") && strings.HasSuffix(r.URL.Path, "/rotate") && s.direct == nil:
		s.rotate(w, r)
	default:
		writeError(w, 404, "endpoint not found")
	}
}

func (s *Server) mesh() protocol.Mesh {
	now := s.now()
	m := protocol.Mesh{ServerTime: float64(now.UnixNano()) / 1e9, Machines: []protocol.Machine{}}
	if s.direct != nil {
		sample := s.direct()
		m.Machines = append(m.Machines, protocol.Machine{ID: sample.ID, Name: sample.Name, Platform: sample.Platform, ReceivedAt: sample.ObservedAt, Online: float64(now.Unix())-sample.ObservedAt < 15, Snapshot: &sample})
		return m
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	for _, device := range s.state.Devices {
		online := device.Snapshot != nil && float64(now.Unix())-device.ReceivedAt < 15 && float64(now.Unix())-device.Snapshot.ObservedAt < 15
		m.Machines = append(m.Machines, protocol.Machine{ID: device.ID, Name: device.Name, Platform: device.Platform, ReceivedAt: device.ReceivedAt, Online: online, Snapshot: device.Snapshot})
	}
	sort.Slice(m.Machines, func(i, j int) bool { return m.Machines[i].Name < m.Machines[j].Name })
	return m
}

func (s *Server) enroll(w http.ResponseWriter, r *http.Request) {
	var input struct {
		Name     string `json:"name"`
		Platform string `json:"platform"`
	}
	if !decode(w, r, &input) {
		return
	}
	input.Name = strings.TrimSpace(input.Name)
	if len(input.Name) == 0 || len(input.Name) > 80 || len(input.Platform) > 32 {
		writeError(w, 400, "provide a machine name up to 80 characters")
		return
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	if len(s.state.Devices) >= 128 {
		writeError(w, 409, "the relay supports up to 128 machines")
		return
	}
	id := protocol.ID()
	token := "tc1:" + id + ":" + protocol.Secret()
	s.state.Devices[id] = &Device{ID: id, Name: input.Name, Platform: input.Platform, TokenHash: tokenHash(token)}
	if err := persist.Save(s.path, s.state); err != nil {
		delete(s.state.Devices, id)
		writeError(w, 500, "could not save enrollment")
		return
	}
	write(w, 201, protocol.Enrollment{ID: id, Token: token})
}
func (s *Server) remove(w http.ResponseWriter, r *http.Request) {
	id := strings.TrimPrefix(r.URL.Path, "/api/v1/instances/")
	s.mu.Lock()
	defer s.mu.Unlock()
	old, ok := s.state.Devices[id]
	if !ok {
		writeError(w, 404, "unknown machine")
		return
	}
	delete(s.state.Devices, id)
	if err := persist.Save(s.path, s.state); err != nil {
		s.state.Devices[id] = old
		writeError(w, 500, "could not remove machine")
		return
	}
	w.WriteHeader(204)
}
func (s *Server) rotate(w http.ResponseWriter, r *http.Request) {
	id := strings.TrimSuffix(strings.TrimPrefix(r.URL.Path, "/api/v1/instances/"), "/rotate")
	s.mu.Lock()
	defer s.mu.Unlock()
	old, ok := s.state.Devices[id]
	if !ok {
		writeError(w, 404, "unknown machine")
		return
	}
	copy := *old
	token := "tc1:" + id + ":" + protocol.Secret()
	copy.TokenHash = tokenHash(token)
	copy.ReceivedAt = 0
	s.state.Devices[id] = &copy
	if err := persist.Save(s.path, s.state); err != nil {
		s.state.Devices[id] = old
		writeError(w, 500, "could not rotate token")
		return
	}
	write(w, 200, protocol.Enrollment{ID: id, Token: token})
}
func (s *Server) report(w http.ResponseWriter, r *http.Request, token string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	var device *Device
	hash := tokenHash(token)
	for _, candidate := range s.state.Devices {
		if protocol.EqualSecret(candidate.TokenHash, hash) {
			device = candidate
			break
		}
	}
	if device == nil {
		writeError(w, 401, "invalid or revoked device token")
		return
	}
	var sample protocol.Snapshot
	if !decode(w, r, &sample) {
		return
	}
	if sample.ID != device.ID {
		writeError(w, 403, "this token belongs to another machine")
		return
	}
	if err := sample.Validate(s.now()); err != nil {
		writeError(w, 400, err.Error())
		return
	}
	copy := *device
	copy.RetiredBoots = append([]string{}, device.RetiredBoots...)
	if device.Snapshot != nil {
		if sample.BootID == device.Snapshot.BootID && sample.Sequence <= device.Snapshot.Sequence {
			w.WriteHeader(204)
			return
		}
		for _, boot := range device.RetiredBoots {
			if sample.BootID == boot {
				writeError(w, 409, "retired agent session")
				return
			}
		}
		if sample.BootID != device.Snapshot.BootID {
			copy.RetiredBoots = append(copy.RetiredBoots, device.Snapshot.BootID)
			if len(copy.RetiredBoots) > 32 {
				copy.RetiredBoots = copy.RetiredBoots[len(copy.RetiredBoots)-32:]
			}
		}
	}
	copy.Snapshot = &sample
	copy.Platform = sample.Platform
	copy.ReceivedAt = float64(s.now().UnixNano()) / 1e9
	s.state.Devices[device.ID] = &copy
	if err := persist.Save(s.path, s.state); err != nil {
		s.state.Devices[device.ID] = device
		writeError(w, 500, "could not save report")
		return
	}
	w.WriteHeader(204)
}

func decode(w http.ResponseWriter, r *http.Request, target any) bool {
	r.Body = http.MaxBytesReader(w, r.Body, 65536)
	decoder := json.NewDecoder(r.Body)
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(target); err != nil {
		writeError(w, 400, "invalid JSON body")
		return false
	}
	if decoder.Decode(&struct{}{}) != io.EOF {
		writeError(w, 400, "expected one JSON object")
		return false
	}
	return true
}
func write(w http.ResponseWriter, status int, value any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(value)
}
func writeError(w http.ResponseWriter, status int, message string) {
	write(w, status, map[string]string{"error": message})
}
