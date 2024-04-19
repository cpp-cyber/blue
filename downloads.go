package main

import (
    "strings"
    "os"
    "fmt"
    "path/filepath"
    "net/http"
    "html/template"
)

type File struct {
    Name string
    Path string
    IsDir bool
}

func FilePathWalkDir(root string) ([]File, error) {
    var files []File
    rootDepth := strings.Count(root, string(os.PathSeparator))
    err := filepath.WalkDir(root, func(path string, d os.DirEntry, err error) error {
        if err != nil {
            return err
        }

        if d.IsDir() && path != root {
            if strings.Count(path, string(os.PathSeparator)) > rootDepth + 1 {
                return filepath.SkipDir
            }
        }

        if strings.Count(path, string(os.PathSeparator)) == rootDepth + 1 {
            files = append(files, File{Name: d.Name(), Path: path, IsDir: d.IsDir()})
        }
        return nil
    })
    return files, err
}

func serveFiles(w http.ResponseWriter, r *http.Request) {
    newDir := filepath.Clean(r.URL.Path)

    files, err := FilePathWalkDir(filepath.Join(dir, newDir))
    if err != nil {
        http.Error(w, err.Error(), http.StatusInternalServerError)
    }

    data := struct {
        Files []File
        Path string
    }{
        Files: files,
        Path: newDir,
    }

    data.Files = func () []File {
        for i, file := range data.Files {
            data.Files[i].Path = strings.Replace(file.Path, "\\", "/", -1)
            data.Files[i].Path = strings.TrimPrefix(data.Files[i].Path, "uploads/")
        }
        return data.Files
    }()

    data.Path = func () string {
        return strings.Replace(data.Path, "\\", "/", -1)
    }()

    tmpl, err := template.ParseFiles(filepath.Join("templates", "index.html"))
    if err != nil {
        http.Error(w, err.Error(), http.StatusInternalServerError)
    }
    err = tmpl.ExecuteTemplate(w, "index.html", data)
    if err != nil {
        http.Error(w, err.Error(), http.StatusInternalServerError)
    }
}

func downloadFile(w http.ResponseWriter, r *http.Request) {
    newDir := strings.TrimPrefix(r.URL.Path, "/download/")
    newDir = filepath.Clean(newDir)

    filePath := filepath.Join(dir, newDir)

    fmt.Println("===================================== DOWNLOAD =====================================")
    fmt.Println("Client IP: ", r.RemoteAddr)
    fmt.Println("Downloaded File: ", filePath)
    fmt.Println("====================================================================================")

    if _, err := os.Stat(filePath); os.IsNotExist(err) {
        http.Error(w, "File not found", http.StatusNotFound)
        return
    }

    w.Header().Set("Content-Disposition", "attachment; filename=" + filepath.Base(r.URL.Path))
    http.ServeFile(w, r, filePath)
}
