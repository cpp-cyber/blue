package main

import (
    "file-server/models"

    "encoding/json"
    "strings"
    "html/template"
    "log"
    "path/filepath"
    "fmt"
    "net/http"
    "os"
    "io"
)

func echo(w http.ResponseWriter, r *http.Request) {
    fmt.Fprintf(w, "Hello, World!")
}

func serveTemplate(w http.ResponseWriter, r *http.Request) {
    log.Println("===================================== REQUEST =====================================")
    log.Println("Client IP: ", r.RemoteAddr)
    log.Println("Page Requested: ", r.URL.Path)
    log.Println("===================================================================================")

    if strings.Contains(r.URL.Path, "/download/") {
        downloadFile(w, r)
        return
    }

    lp := filepath.Join("templates", "layout.html")
    fp := filepath.Join("templates", filepath.Clean(r.URL.Path) + ".html")

    if fp == "templates" || fp == "templates\\.html" || fp != "templates\\injects.html" {
        serveFiles(w, r)
        return
    }

    info, err := os.Stat(fp)
    if err != nil {
        if os.IsNotExist(err) {
            http.Error(w, "404 page not found", http.StatusNotFound)
            return
        }
    }

    if info.IsDir() {
        http.Error(w, "404 page not found", http.StatusNotFound)
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

func uploadFile(w http.ResponseWriter, r *http.Request) {
    r.ParseMultipartForm(10 << 20)
    file, handler, err := r.FormFile("file")
    if err != nil {
        fmt.Println("Error retrieving the file")
        fmt.Println(err)
        return
    }
    defer file.Close()

    if handler.Size > 10 << 20 {
        http.Error(w, "File too large", http.StatusInternalServerError)
        return
    }

    uploadPath := r.FormValue("path")
    uploadPath = filepath.Join(dir, uploadPath)
    filePath := filepath.Join(uploadPath, handler.Filename)

    if _, err := os.Stat(filePath); err == nil {
        http.Error(w, "File already exists", http.StatusInternalServerError)
        return
    }

    dst, err := os.Create(filePath)
    defer dst.Close()
    if err != nil {
        http.Error(w, err.Error(), http.StatusInternalServerError)
        return
    }

    if _, err := io.Copy(dst, file); err != nil {
        http.Error(w, err.Error(), http.StatusInternalServerError)
        return
    }

    fmt.Println("===================================== FILE UPLOAD =====================================")
    fmt.Printf("Client IP: %s\n", r.RemoteAddr)
    fmt.Printf("Upload Path: %s\n", uploadPath)
    fmt.Printf("Uploaded File: %+v\n", handler.Filename)
    fmt.Println("=======================================================================================")

    http.Redirect(w, r, "/", http.StatusSeeOther)
}

func getInjects(w http.ResponseWriter, r *http.Request) {
    injects, err := GetAllInjects()
    if err != nil {
        http.Error(w, err.Error(), http.StatusInternalServerError)
        return
    }

    injectJSON, err := json.Marshal(injects)

    w.Header().Set("Content-Type", "application/json")
    w.Write(injectJSON)
}

func createInject(w http.ResponseWriter, r *http.Request) {
    decoder := json.NewDecoder(r.Body)
    var inject models.Inject
    err := decoder.Decode(&inject)
    if err != nil {
        http.Error(w, err.Error(), http.StatusInternalServerError)
        return
    }

    name := inject.Name
    pad := inject.Pad
    dueDate := inject.DueDate

    err = AddInject(name, pad, dueDate)
    if err != nil {
        http.Error(w, err.Error(), http.StatusInternalServerError)
        return
    }

    fmt.Fprintf(w, "Successfully created inject\n")
}

func editInject(w http.ResponseWriter, r *http.Request) {
    decoder := json.NewDecoder(r.Body)
    var inject models.Inject
    err := decoder.Decode(&inject)
    if err != nil {
        http.Error(w, err.Error(), http.StatusInternalServerError)
        return
    }

    id := inject.ID
    status := inject.Status

    err = EditInjectInDB(id, status)
    if err != nil {
        http.Error(w, err.Error(), http.StatusInternalServerError)
        return
    }

    fmt.Fprintf(w, "Successfully completed inject\n")
}

func deleteInject(w http.ResponseWriter, r *http.Request) {
    decoder := json.NewDecoder(r.Body)
    var inject models.Inject
    err := decoder.Decode(&inject)
    if err != nil {
        http.Error(w, err.Error(), http.StatusInternalServerError)
        return
    }

    id := inject.ID

    err = DeleteInjectFromDB(id)
    if err != nil {
        http.Error(w, err.Error(), http.StatusInternalServerError)
        return
    }

    fmt.Fprintf(w, "Successfully deleted inject\n")
}

func createDirectory(w http.ResponseWriter, r *http.Request) {
    decoder := json.NewDecoder(r.Body)
    var path models.Path
    err := decoder.Decode(&path)
    if err != nil {
        http.Error(w, err.Error(), http.StatusInternalServerError)
        return
    }

    name := path.Path
    dirPath := filepath.Join(dir, name)
    dirPath = filepath.Clean(dirPath)
    dirPath = filepath.ToSlash(dirPath)
    err = os.Mkdir(dirPath, os.ModePerm)
    if err != nil {
        http.Error(w, err.Error(), http.StatusInternalServerError)
        return
    }

    fmt.Fprintf(w, "Successfully created directory\n")
}