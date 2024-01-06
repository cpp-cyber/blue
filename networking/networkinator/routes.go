package main

import (
	"github.com/gin-gonic/gin"
)

func addPublicRoutes(g *gin.RouterGroup) {
	g.GET("/", func(c *gin.Context) {
		c.HTML(200, "index.html", gin.H{})
	})
	g.GET("/status", status)
    g.GET("/api/hosts", GetHosts)
    g.GET("/api/hosts/:filter", GetHosts)
	g.GET("/api/connections", GetConnections)
	g.POST("/api/hosts", AddHost)
	g.POST("/api/connections", AddConnection)
}

func status(c *gin.Context) {
	c.JSON(200, gin.H{"status": "ok"})
}
