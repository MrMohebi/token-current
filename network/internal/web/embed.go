package web

import (
	"embed"
	"net/http"
)

//go:embed index.html app.js style.css icon.svg
var files embed.FS

func Handler() http.Handler { return http.FileServer(http.FS(files)) }
