package main

import (
    "net/http"
    "flag"
)

var dir string

func init() {
    flag.StringVar(&dir, "dir", ".", "the directory to serve files from. Defaults to the current dir")
    flag.Parse()
}

func setupRoutes() {
    fs := http.FileServer(http.Dir(dir))
    http.Handle("GET /files/", http.StripPrefix("/files/", fs))

    assets := http.FileServer(http.Dir("./assets/"))
    http.Handle("GET /assets/", http.StripPrefix("/assets/", assets))

    http.HandleFunc("GET /", serveTemplate)
    http.HandleFunc("GET /api/v1/echo", echo)
    http.HandleFunc("GET /api/v1/injects", getInjects)

    http.HandleFunc("POST /api/v1/upload", uploadFile)
    http.HandleFunc("POST /api/v1/injects", createInject)
}
