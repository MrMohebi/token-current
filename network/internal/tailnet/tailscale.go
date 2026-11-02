package tailnet

import (
	"context"
	"encoding/json"
	"errors"
	"github.com/MrMohebi/token-current/network/internal/protocol"
	"net"
	"os/exec"
	"runtime"
)

type Peer struct {
	ID           string   `json:"ID"`
	HostName     string   `json:"HostName"`
	DNSName      string   `json:"DNSName"`
	TailscaleIPs []string `json:"TailscaleIPs"`
	Online       bool     `json:"Online"`
	OS           string   `json:"OS"`
}
type Status struct {
	BackendState string          `json:"BackendState"`
	Self         *Peer           `json:"Self"`
	Peer         map[string]Peer `json:"Peer"`
}

func Binary() string {
	if path, e := exec.LookPath("tailscale"); e == nil {
		return path
	}
	if runtime.GOOS == "windows" {
		return `C:\Program Files\Tailscale\tailscale.exe`
	}
	if runtime.GOOS == "darwin" {
		return "/Applications/Tailscale.app/Contents/MacOS/Tailscale"
	}
	return "tailscale"
}
func Read(ctx context.Context) (Status, error) {
	var s Status
	b, e := exec.CommandContext(ctx, Binary(), "status", "--json").Output()
	if e != nil {
		return s, errors.New("Tailscale is not installed, running, or signed in")
	}
	if e = json.Unmarshal(b, &s); e != nil {
		return s, e
	}
	if s.BackendState != "Running" {
		return s, errors.New("sign in to Tailscale first")
	}
	return s, nil
}
func (p Peer) URL() string {
	for _, raw := range p.TailscaleIPs {
		if ip := net.ParseIP(raw); ip != nil && protocol.IsTailscaleIP(ip) {
			return "http://" + net.JoinHostPort(ip.String(), "8791")
		}
	}
	return ""
}
