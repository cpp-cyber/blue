package main

import (
	"networkinator/models"
	"log"

	"github.com/gin-gonic/gin"
    "github.com/gorilla/websocket"
)

var (
    HostCount int
    agentClients = make(map[*websocket.Conn]bool)
    webClients = make(map[*websocket.Conn]bool)
    db = ConnectToSQLite()

    tomlConf = &models.Config{}
    configPath = "config.conf"
)

func main() {
    models.ReadConfig(tomlConf, configPath)

	router := gin.Default()
	router.LoadHTMLGlob("templates/**/*")
	router.MaxMultipartMemory = 8 << 20 // 8 MiB
	router.Static("/assets", "./assets/")

    initCookies(router)

	public := router.Group("/")
	addPublicRoutes(public)

    private := router.Group("/")
    private.Use(authRequired)
	addPrivateRoutes(private)

    err := db.AutoMigrate(&models.Connection{}, &models.Agent{})
	if err != nil {
		log.Fatalln(err)
	}

    log.Fatalln(router.Run(":80"))
}
