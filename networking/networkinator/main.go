package main

import (
	"WebService/models"
	"log"
	"os"

	"github.com/gin-gonic/gin"
)

var HostCount int

func main() {

	router := gin.Default()
	router.LoadHTMLGlob("templates/*")
	router.MaxMultipartMemory = 8 << 20 // 8 MiB
	router.Static("/assets", "./assets/")

	public := router.Group("/")
	addPublicRoutes(public)

	db, err := connectToSQLite()
	if err != nil {
		log.Fatalln(err)
	}

	err = db.AutoMigrate(&models.Host{}, &models.Connection{})
	if err != nil {
		log.Fatalln(err)
	}

	if os.Getenv("USE_HTTPS") == "true" {
		log.Fatalln(router.RunTLS(":443", os.Getenv("CERT_PATH"), os.Getenv("KEY_PATH")))
	} else {
		log.Fatalln(router.Run(":80"))
	}
}
