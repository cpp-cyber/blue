package main

import (
	"networkinator/models"
	"log"

	"github.com/gin-gonic/gin"
    "github.com/gorilla/websocket"
)

var HostCount int

var agentClients = make(map[*websocket.Conn]bool)
var webClients = make(map[*websocket.Conn]bool)
var db = ConnectToSQLite()


func main() {

	router := gin.Default()
	router.LoadHTMLGlob("templates/**/*")
	router.MaxMultipartMemory = 8 << 20 // 8 MiB
	router.Static("/assets", "./assets/")

	public := router.Group("/")
	addPublicRoutes(public)

    err := db.AutoMigrate(&models.Connection{}, &models.Agent{})
	if err != nil {
		log.Fatalln(err)
	}

    log.Fatalln(router.Run(":80"))
}
