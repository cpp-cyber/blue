package main

import (
	"WebService/models"
	"net/http"
	"strconv"
    "fmt"

	"github.com/gin-gonic/gin"
)

func GetHosts(c *gin.Context) {
    filter := c.Request.URL.Query().Get("hostname")
    if filter == "" {
        filter = "%"
    }

	db, err := connectToSQLite()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	hosts, err := getHostsEntries(db, filter)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
    
	hostMap := make(map[int]string)
	for _, host := range hosts {
        hostMap[host.ID] = host.IP + "," + host.Hostname
	}

	c.JSON(http.StatusOK, hostMap)
}

func GetConnections(c *gin.Context) {
	db, err := connectToSQLite()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	connections, err := getConnections(db)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	connectionMap := make(map[string][]int)
	for _, connection := range connections {
		connectionMap[connection.ID] = []int{connection.Src, connection.Dst, connection.Port}
	}

	c.JSON(http.StatusOK, connectionMap)
}

func AddHost(c *gin.Context) {
	var jsonData models.Host
	if err := c.ShouldBindJSON(&jsonData); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	ip := jsonData.IP
    hostname := jsonData.Hostname

	db, err := connectToSQLite()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	err = createHost(db, ip, hostname)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"status": "ok"})
}

func AddConnection(c *gin.Context) {
	var jsonData map[string]interface{}
	if err := c.ShouldBindJSON(&jsonData); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid JSON"})
		return
	}

	src := jsonData["Src"].(string)
	dst := jsonData["Dst"].(string)
	port := jsonData["Port"].(string)
    hostname := jsonData["Hostname"].(string)

	portInt, err := strconv.Atoi(port)
	if err != nil || portInt < 0 || portInt > 65535 {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Could not convert port to int"})
		return
	}

	db, err := connectToSQLite()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	srcHost := models.Host{}
	dstHost := models.Host{}

	tx := db.First(&srcHost, "IP = ?", src)
	if tx.Error != nil {
		createHost(db, src, hostname)
		db.First(&srcHost, "IP = ?", src)
	} else if srcHost.Hostname == "" {
        fmt.Println("Updating hostname" + hostname)
        updateHost(db, src, hostname)
    }

	tx = db.First(&dstHost, "IP = ?", dst)
	if tx.Error != nil {
		createHost(db, dst, "")
		db.First(&dstHost, "IP = ?", dst)
	}

	tx = db.First(&models.Connection{}, "Src = ? AND Dst = ? AND Port = ?", srcHost.ID, dstHost.ID, portInt)
	if tx.Error == nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Connection already exists"})
		return
	}

	err = createConnection(db, srcHost.ID, dstHost.ID, portInt)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"status": "ok"})
}

