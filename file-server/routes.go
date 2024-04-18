package main

import (
    "net/http"
    "flag"
)

var dir string

func init() {
    flag.StringVar(&dir, "dir", "./uploads", "the directory to serve files from. Defaults to the current dir")
    flag.Parse()
}

func setupRoutes() {
    assets := http.FileServer(http.Dir("./assets/"))
    http.Handle("GET /assets/", http.StripPrefix("/assets/", assets))

    http.HandleFunc("GET /", serveTemplate)
    http.HandleFunc("GET /api/v1/echo", echo)
    http.HandleFunc("GET /api/v1/injects", getInjects)
    //http.HandleFunc("GET /files/", serveFiles)
    //http.HandleFunc("GET /download/{path}", downloadFile)

    http.HandleFunc("POST /api/v1/upload", uploadFile)
    http.HandleFunc("POST /api/v1/injects", createInject)
    http.HandleFunc("POST /api/v1/dir", createDirectory)

    http.HandleFunc("PUT /api/v1/injects", editInject)

    http.HandleFunc("DELETE /api/v1/injects", deleteInject)
}