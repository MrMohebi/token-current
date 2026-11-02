package main

import (
	"context"
	"github.com/MrMohebi/token-current/network/internal/protocol"
	"github.com/MrMohebi/token-current/network/internal/server"
	"github.com/MrMohebi/token-current/network/internal/tailnet"
	"log"
	"net"
	"net/http"
	"time"
)

// Tailnet access is a separate, read-only listener bound to this node's own
// Tailscale IPs. The authenticated loopback API and public relay are unchanged.
func serveTailnet(ctx context.Context, get func() protocol.Snapshot) {
	active := map[string]*http.Server{}
	defer func() {
		for _, s := range active {
			_ = s.Close()
		}
	}()
	type stopped struct {
		address string
		server  *http.Server
	}
	failures := make(chan stopped, 4)
	ticker := time.NewTicker(5 * time.Second)
	defer ticker.Stop()
	lastError := time.Time{}
	for {
		statusCtx, cancel := context.WithTimeout(ctx, 3*time.Second)
		status, err := tailnet.Read(statusCtx)
		cancel()
		wanted := map[string]bool{}
		if err == nil && status.Self != nil {
			for _, raw := range status.Self.TailscaleIPs {
				ip := net.ParseIP(raw)
				if ip == nil || !protocol.IsTailscaleIP(ip) {
					continue
				}
				address := net.JoinHostPort(ip.String(), "8791")
				wanted[address] = true
				if active[address] != nil {
					continue
				}
				listener, e := net.Listen("tcp", address)
				if e != nil {
					if time.Since(lastError) > 30*time.Second {
						log.Printf("Tailscale listener unavailable on %s; retrying: %v", address, e)
						lastError = time.Now()
					}
					continue
				}
				s := &http.Server{Handler: server.NewTailnet(get).Handler(), ReadHeaderTimeout: 5 * time.Second, ReadTimeout: 10 * time.Second, WriteTimeout: 10 * time.Second, IdleTimeout: 60 * time.Second, MaxHeaderBytes: 32 << 10}
				active[address] = s
				log.Printf("Tailscale usage available at http://%s (no pairing token)", address)
				go func() {
					_ = s.Serve(listener)
					select {
					case failures <- stopped{address, s}:
					case <-ctx.Done():
					}
				}()
			}
		}
		// Do not keep serving on old IPs after sign-out or an address change.
		for address, s := range active {
			if !wanted[address] {
				_ = s.Close()
				delete(active, address)
			}
		}
		select {
		case <-ctx.Done():
			return
		case ended := <-failures:
			if s := active[ended.address]; s == ended.server {
				_ = s.Close()
				delete(active, ended.address)
			}
		case <-ticker.C:
		}
	}
}
