package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"github.com/MrMohebi/token-current/network/internal/server"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"
)

func main() {
	if err := run(); err != nil {
		log.Print(err)
		os.Exit(1)
	}
}
func run() error {
	command := "serve"
	args := os.Args[1:]
	if len(args) > 0 && args[0] != "" && args[0][0] != '-' {
		command = args[0]
		args = args[1:]
	}
	flags := flag.NewFlagSet("token-current-relay", flag.ContinueOnError)
	path := flags.String("state", "relay-state.json", "private persistent state file")
	listen := flags.String("listen", "127.0.0.1:8787", "HTTP listen address")
	if err := flags.Parse(args); err != nil {
		return err
	}
	relay, err := server.NewRelay(*path)
	if err != nil {
		return err
	}
	if command == "token" {
		fmt.Println(relay.AdminToken())
		return nil
	}
	if command == "init" {
		fmt.Println("Relay state initialized:", *path)
		return nil
	}
	if command != "serve" {
		return errors.New("use serve, init, or token")
	}
	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer cancel()
	httpServer := &http.Server{Addr: *listen, Handler: relay.Handler(), ReadHeaderTimeout: 5 * time.Second, ReadTimeout: 10 * time.Second, WriteTimeout: 10 * time.Second, IdleTimeout: 60 * time.Second, MaxHeaderBytes: 32 << 10}
	done := make(chan error, 1)
	go func() { done <- httpServer.ListenAndServe() }()
	log.Printf("Token Current relay listening on %s; management token stored in %s", *listen, *path)
	select {
	case <-ctx.Done():
		err = nil
	case err = <-done:
		if errors.Is(err, http.ErrServerClosed) {
			err = nil
		}
	}
	shutdown, stop := context.WithTimeout(context.Background(), 5*time.Second)
	defer stop()
	_ = httpServer.Shutdown(shutdown)
	return err
}
