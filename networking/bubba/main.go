package main

import (
    "networkinator/models"
    "log"
    "os"

    "github.com/gin-gonic/gin"
    "github.com/gorilla/websocket"
)

var HostCount int

var agentClients = make(map[*websocket.Conn]bool)
var webClients = make(map[*websocket.Conn]bool)
var db = ConnectToSQLite()


func main() {
    f, err := os.OpenFile("server.txt", os.O_RDWR|os.O_CREATE|os.O_APPEND, 0666)
    if err != nil {
        log.Fatalf("error opening file: %v", err)
    }
    defer f.Close()
    log.SetOutput(f)

    router := gin.Default()
    router.LoadHTMLGlob("templates/**/*")
    router.MaxMultipartMemory = 8 << 20 // 8 MiB
    router.Static("/assets", "./assets/")

    public := router.Group("/")
    addPublicRoutes(public)

    err = db.AutoMigrate(&models.Connection{}, &models.Agent{})
    if err != nil {
        log.Fatalln(err)
    }

    log.Fatalln(router.Run(":80"))
}
