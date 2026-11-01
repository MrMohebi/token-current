package main

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"github.com/MrMohebi/token-current/network/internal/monitor"
	"github.com/MrMohebi/token-current/network/internal/persist"
	"github.com/MrMohebi/token-current/network/internal/protocol"
	"github.com/MrMohebi/token-current/network/internal/server"
	"github.com/MrMohebi/token-current/network/internal/tailnet"
	"io"
	"log"
	"net/http"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"syscall"
	"time"
)

type config struct {
	ID           string `json:"id"`
	Name         string `json:"name"`
	Listen       string `json:"listen"`
	ReadToken    string `json:"readToken"`
	ClaudeHome   string `json:"claudeHome"`
	CodexHome    string `json:"codexHome"`
	RelayURL     string `json:"relayURL,omitempty"`
	PublishToken string `json:"publishToken,omitempty"`
}

func main() {
	if err := run(); err != nil {
		log.Print(err)
		os.Exit(1)
	}
}
func run() error {
	command := "run"
	args := os.Args[1:]
	if len(args) > 0 && !strings.HasPrefix(args[0], "-") {
		command = args[0]
		args = args[1:]
	}
	base, err := os.UserConfigDir()
	if err != nil {
		return err
	}
	flags := flag.NewFlagSet("token-current-agent "+command, flag.ContinueOnError)
	path := flags.String("config", filepath.Join(base, "Token Current", "agent.json"), "configuration file")
	background := flags.Bool("background", false, "hide the Windows console for a background task")
	name := flags.String("name", "", "machine display name")
	listen := flags.String("listen", "127.0.0.1:8790", "HTTP address; use Tailscale Serve to expose it privately")
	claude := flags.String("claude-home", "", "Claude data home")
	codex := flags.String("codex-home", "", "Codex data home")
	relayURL := flags.String("relay", "", "relay origin for configure")
	if err = flags.Parse(args); err != nil {
		return err
	}
	var cfg config
	if command == "init" {
		if _, err = os.Stat(*path); err == nil {
			return errors.New("configuration exists; it has not been overwritten")
		}
		home, _ := os.UserHomeDir()
		host, _ := os.Hostname()
		if *name == "" {
			*name = host
		}
		if *claude == "" {
			*claude = os.Getenv("CLAUDE_CONFIG_DIR")
			if *claude == "" {
				*claude = filepath.Join(home, ".claude")
				xdg := os.Getenv("XDG_CONFIG_HOME")
				if xdg == "" {
					xdg = filepath.Join(home, ".config")
				}
				if _, e := os.Stat(filepath.Join(*claude, "projects")); e != nil {
					if _, e = os.Stat(filepath.Join(xdg, "claude", "projects")); e == nil {
						*claude = filepath.Join(xdg, "claude")
					}
				}
			}
		}
		if *codex == "" {
			*codex = os.Getenv("CODEX_HOME")
			if *codex == "" {
				*codex = filepath.Join(home, ".codex")
			}
		}
		cfg = config{ID: protocol.ID(), Name: *name, Listen: *listen, ReadToken: protocol.Secret(), ClaudeHome: *claude, CodexHome: *codex}
		if err = persist.Save(*path, cfg); err != nil {
			return err
		}
		fmt.Println("Configured", *path)
		fmt.Println("Run token-current-agent run. For a direct connection, token-current-agent token prints your pairing token.")
		return nil
	}
	if err = persist.Load(*path, &cfg); err != nil {
		return fmt.Errorf("read configuration: %w; run token-current-agent init first", err)
	}
	if len(cfg.ReadToken) < 32 || cfg.ID == "" {
		return errors.New("invalid agent configuration")
	}
	switch command {
	case "token":
		fmt.Println(cfg.ReadToken)
		return nil
	case "configure":
		reader := bufio.NewReader(os.Stdin)
		if *relayURL == "" {
			fmt.Fprint(os.Stderr, "Relay URL: ")
			*relayURL, _ = reader.ReadString('\n')
		}
		u, e := protocol.Endpoint(*relayURL)
		if e != nil {
			return e
		}
		fmt.Fprint(os.Stderr, "Device token (paste from the relay or Mac app): ")
		key, e := reader.ReadString('\n')
		if e != nil && e != io.EOF {
			return e
		}
		key = strings.TrimSpace(key)
		parts := strings.Split(key, ":")
		if len(parts) != 3 || parts[0] != "tc1" || len(parts[1]) != 32 || len(parts[2]) != 64 {
			return errors.New("invalid device token")
		}
		cfg.ID = parts[1]
		cfg.RelayURL = u.String()
		cfg.PublishToken = key
		if err = persist.Save(*path, cfg); err != nil {
			return err
		}
		fmt.Println("Relay configured. Restart the daemon to apply it.")
		return nil
	case "tailscale":
		if cfg.Listen != "127.0.0.1:8790" {
			return errors.New("Tailscale Serve setup expects listen 127.0.0.1:8790")
		}
		ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
		defer cancel()
		status, e := tailnet.Read(ctx)
		if e != nil {
			return e
		}
		current, e := exec.CommandContext(ctx, tailnet.Binary(), "serve", "status", "--json").Output()
		if e != nil {
			return errors.New("could not inspect existing Tailscale Serve configuration")
		}
		var serveConfig struct {
			TCP map[string]struct {
				HTTPS      bool
				TCPForward string
			}
			Web map[string]struct {
				Handlers map[string]struct{ Proxy string }
			}
		}
		if json.Unmarshal(current, &serveConfig) != nil {
			return errors.New("unsupported Tailscale Serve configuration; existing configuration was preserved")
		}
		if tcp, ok := serveConfig.TCP["8790"]; ok && (!tcp.HTTPS || tcp.TCPForward != "") {
			return errors.New("Tailscale Serve port 8790 is already in use; existing configuration was preserved")
		}
		for host, site := range serveConfig.Web {
			if strings.HasSuffix(host, ":8790") && (len(site.Handlers) != 1 || site.Handlers["/"].Proxy != "http://127.0.0.1:8790") {
				return errors.New("Tailscale Serve port 8790 is already in use; existing configuration was preserved")
			}
		}
		command := exec.CommandContext(ctx, tailnet.Binary(), "serve", "--bg", "--https=8790", "http://127.0.0.1:8790")
		command.Stdout = os.Stdout
		command.Stderr = os.Stderr
		command.Stdin = os.Stdin
		if e = command.Run(); e != nil {
			return errors.New("Tailscale Serve could not be enabled; check your tailnet HTTPS/Serve permissions")
		}
		if status.Self != nil {
			fmt.Println("Direct URL:", status.Self.URL())
		}
		fmt.Println("Use token-current-agent token to read the pairing token.")
		return nil
	case "peers":
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		status, e := tailnet.Read(ctx)
		if e != nil {
			return e
		}
		return json.NewEncoder(os.Stdout).Encode(status.Peer)
	case "run":
		if *background {
			hideConsole()
		}
		return serve(cfg, *path)
	default:
		return errors.New("use init, run, token, configure, tailscale, or peers")
	}
}

func serve(cfg config, path string) error {
	collector, err := monitor.New(filepath.Join(filepath.Dir(path), "usage-state.json"), cfg.ClaudeHome, cfg.CodexHome)
	if err != nil {
		return err
	}
	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer cancel()
	var mu sync.RWMutex
	sample := protocol.Snapshot{ID: cfg.ID, Name: cfg.Name, Platform: runtime.GOOS, BootID: protocol.ID(), Day: time.Now().UTC().Format("2006-01-02"), Providers: map[string]protocol.Provider{"claude": {Health: "importing"}, "codex": {Health: "importing"}}}
	get := func() protocol.Snapshot { mu.RLock(); defer mu.RUnlock(); return sample }
	api := server.NewDirect(cfg.ReadToken, get)
	httpServer := &http.Server{Addr: cfg.Listen, Handler: api.Handler(), ReadHeaderTimeout: 5 * time.Second, ReadTimeout: 10 * time.Second, WriteTimeout: 10 * time.Second, IdleTimeout: 60 * time.Second, MaxHeaderBytes: 32 << 10}
	errorsChannel := make(chan error, 2)
	updates := make(chan protocol.Snapshot, 1)
	if cfg.RelayURL != "" {
		if _, err = protocol.Endpoint(cfg.RelayURL); err != nil {
			return err
		}
		go publish(ctx, cfg, updates)
	}
	go func() { errorsChannel <- httpServer.ListenAndServe() }()
	go func() {
		ticker := time.NewTicker(time.Second)
		defer ticker.Stop()
		for {
			now := time.Now()
			providers, e := collector.Tick(now)
			if e != nil {
				errorsChannel <- fmt.Errorf("could not persist usage: %w", e)
				return
			}
			mu.Lock()
			sample.Sequence++
			sample.Day = now.UTC().Format("2006-01-02")
			sample.ObservedAt = float64(now.UnixNano()) / 1e9
			sample.Providers = providers
			next := sample
			mu.Unlock()
			if cfg.RelayURL != "" {
				select {
				case updates <- next:
				default:
					select {
					case <-updates:
					default:
					}
					select {
					case updates <- next:
					default:
					}
				}
			}
			select {
			case <-ctx.Done():
				return
			case <-ticker.C:
			}
		}
	}()
	log.Printf("Token Current agent listening on %s; usage only, no conversation content", cfg.Listen)
	select {
	case <-ctx.Done():
		err = nil
	case err = <-errorsChannel:
		if errors.Is(err, http.ErrServerClosed) {
			err = nil
		}
	}
	cancel()
	shutdown, done := context.WithTimeout(context.Background(), 5*time.Second)
	defer done()
	_ = httpServer.Shutdown(shutdown)
	return err
}

func publish(ctx context.Context, cfg config, updates <-chan protocol.Snapshot) {
	client := &http.Client{Timeout: 3 * time.Second, CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }}
	lastError := time.Time{}
	for {
		select {
		case <-ctx.Done():
			return
		case sample := <-updates:
			data, _ := json.Marshal(sample)
			request, err := http.NewRequestWithContext(ctx, "POST", cfg.RelayURL+"/api/v1/report", bytes.NewReader(data))
			if err != nil {
				return
			}
			request.Header.Set("Authorization", "Bearer "+cfg.PublishToken)
			request.Header.Set("Content-Type", "application/json")
			response, e := client.Do(request)
			if e == nil {
				io.Copy(io.Discard, io.LimitReader(response.Body, 4096))
				response.Body.Close()
				if response.StatusCode != 204 {
					e = errors.New("relay rejected the report; verify enrollment and token")
				}
			}
			if e != nil && time.Since(lastError) > 30*time.Second {
				log.Print("Relay unavailable or rejected the token; continuing local collection and retrying.")
				lastError = time.Now()
			}
		}
	}
}
