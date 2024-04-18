package main

import (
    "file-server/models"

    "encoding/json"
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
