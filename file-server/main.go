package main

import (
    "file-server/models"

	"fmt"
	"net/http"
)

var db = ConnectToSQLite()

func main() {
    db.AutoMigrate(models.Inject{})
    setupRoutes()
    fmt.Println("Web server started: http://localhost/")
    http.ListenAndServe(":80", nil)
}

