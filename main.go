package main

import (
    "file-server/models"

    "log"
	"fmt"
    "os"   
	"net/http"
)

var db = ConnectToSQLite()

func main() {
    os.Mkdir("logs", os.ModePerm)
    logFile, err := os.OpenFile("logs/app.log", os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0666)
    if err != nil {
        panic(err)
    }
    defer logFile.Close()

    log.SetOutput(logFile)

    db.AutoMigrate(models.Inject{})
    setupRoutes()
    fmt.Println("Web server started: http://localhost/")
    http.ListenAndServe(":80", nil)
}

