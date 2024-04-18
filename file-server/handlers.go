package main

import (
    "html/template"
    "log"
    "path/filepath"
    "fmt"
    "net/http"
    "os"
    "io"
)

func serveTemplate(w http.ResponseWriter, r *http.Request) {
    lp := filepath.Join("templates", "layout.html")
    fp := filepath.Join("templates", filepath.Clean(r.URL.Path) + ".html")
    fmt.Println(fp)

    if fp == "templates" || fp == "templates\\.html" {
        fp = "templates/index.html"
    }

    info, err := os.Stat(fp)
    if err != nil {
        if os.IsNotExist(err) {
            http.NotFound(w, r)
            return
        }
    }

    if info.IsDir() {
        http.NotFound(w, r)
        return
    }

    tmpl, _ := template.ParseFiles(lp, fp)
    if err != nil {
        log.Println(err.Error())
        http.Error(w, err.Error(), http.StatusInternalServerError)
        return
    }

    err = tmpl.ExecuteTemplate(w, "layout", nil)
    if err != nil {
        log.Println(err.Error())
        http.Error(w, err.Error(), http.StatusInternalServerError)
    }
}

func echo(w http.ResponseWriter, r *http.Request) {
    fmt.Fprintf(w, "Hello, World!")
}

func uploadFile(w http.ResponseWriter, r *http.Request) {
    fmt.Println("File uploaded")

    r.ParseMultipartForm(10 << 20)
    file, handler, err := r.FormFile("myFile")
    if err != nil {
        fmt.Println("Error retrieving the file")
        fmt.Println(err)
        return
    }
    defer file.Close()
    fmt.Printf("Uploaded File: %+v\n", handler.Filename)
    fmt.Printf("File Size: %+v\n", handler.Size)
    fmt.Printf("MIME Header: %+v\n", handler.Header)

    if _, err := os.Stat("uploads/" + handler.Filename); os.IsNotExist(err) {
        http.Error(w, "File already exists", http.StatusInternalServerError)
        return
    }

    dst, err := os.Create("uploads/" + handler.Filename)
    defer dst.Close()
    if err != nil {
        http.Error(w, err.Error(), http.StatusInternalServerError)
        return
    }

    if _, err := io.Copy(dst, file); err != nil {
        http.Error(w, err.Error(), http.StatusInternalServerError)
        return
    }

    fmt.Fprintf(w, "Successfully uploaded file\n")
}

func getInjects(w http.ResponseWriter, r *http.Request) {
    injects, err := GetAllInjects()
    if err != nil {
        http.Error(w, err.Error(), http.StatusInternalServerError)
        return
    }

    fmt.Fprintf(w, "%v\n", injects)
}

func createInject(w http.ResponseWriter, r *http.Request) {
    err := r.ParseForm()
    if err != nil {
        http.Error(w, err.Error(), http.StatusInternalServerError)
        return
    }

    fmt.Println(r.Body)
    fmt.Println(r.PostForm)
    name := r.Form.Get("name")
    category := r.Form.Get("category")
    pad := r.Form.Get("pad")
    dueDate := r.Form.Get("dueDate")

    err = AddInject(name, category, pad, dueDate)
    if err != nil {
        http.Error(w, err.Error(), http.StatusInternalServerError)
        return
    }

    fmt.Fprintf(w, "Successfully created inject\n")
}
