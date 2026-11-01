package main

import "syscall"

// Used only by the scheduled task. Foreground CLI commands keep their console.
func hideConsole() {
	console, _, _ := syscall.NewLazyDLL("kernel32.dll").NewProc("GetConsoleWindow").Call()
	if console != 0 {
		syscall.NewLazyDLL("user32.dll").NewProc("ShowWindow").Call(console, 0)
	}
}
