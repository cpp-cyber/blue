package main

import (
	"WebService/models"
	"fmt"
	"log"
	"net"
	"os"

	"github.com/gin-gonic/gin"
)

var HostCount int

var privateIPBlocks []*net.IPNet

func main() {

	for _, cidr := range []string{
		"10.0.0.0/8",     // RFC1918
		"172.16.0.0/12",  // RFC1918
		"192.168.0.0/16", // RFC1918
	} {
		_, block, err := net.ParseCIDR(cidr)
        if err != nil {
			panic(fmt.Errorf("parse error on %q: %v", cidr, err))
		}
		privateIPBlocks = append(privateIPBlocks, block)
	}

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
