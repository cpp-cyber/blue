package main

import (
	"encoding/json"
	"fmt"
	"net/http"
	"networkinator/models"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/gorilla/websocket"
)

func GetConnections(c *gin.Context) {
    connections, err := GetAllConnections(db)
    if err != nil {
        c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
        return
    }

    connectionMap := make(map[string][]string)
    for _, connection := range connections {
        connectionMap[connection.ID] = []string{connection.Src, connection.Dst, strconv.Itoa(connection.Port), strconv.Itoa(connection.Count)}
    }

    c.JSON(http.StatusOK, connectionMap)
}

func AddConnection(input []byte) {
    jsonData := make(map[string]interface{})
    err := json.Unmarshal(input, &jsonData)
    if err != nil {
        fmt.Println(err)
        return
    }

	src := jsonData["Src"].(string)
	dst := jsonData["Dst"].(string)
	port := jsonData["Port"].(string)

	portInt, err := strconv.Atoi(port)
	if err != nil || portInt < 0 || portInt > 65535 {
        fmt.Println(err)
		return
	}

    connection := models.Connection{}
    tx := db.First(&connection, "Src = ? AND Dst = ? AND Port = ?", src, dst, portInt)
	if tx.Error == nil {
        IncrementConnectionCount(connection.ID)
		return
	}

	err = AddConnectionToDB(src, dst, portInt, 1)
	if err != nil {
        fmt.Println(err)
		return
	}

    for client := range clients {
        err := client.WriteJSON(jsonData)
        if err != nil {
            fmt.Println(err)
            client.Close()
            delete(clients, client)
        }
    }
}

func GetAgents(c *gin.Context) {
    agents, err := GetAllAgents()
    if err != nil {
        c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
        return
    }

    agentArr := make([][]string, len(agents))
    for i := 0; i < len(agents); i++ {
        agentArr[i] = []string{agents[i].Hostname, agents[i].HostOS, agents[i].IP, agents[i].ID}
    }

    fmt.Println(agentArr)

    c.JSON(http.StatusOK, agentArr)
}

func AddAgent(c *gin.Context) {
    jsonData := make(map[string]interface{})
    err := c.ShouldBindJSON(&jsonData)
    if err != nil {
        c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
        return
    }

    hostname := jsonData["Hostname"].(string)
    hostOS := jsonData["HostOS"].(string)
    id := jsonData["ID"].(string)
    ip := strings.Split(c.ClientIP(), ":")[0]

    agent := models.Agent{}
    tx := db.First(&agent, "Hostname = ?", hostname)
    if tx.Error == nil {
        c.JSON(http.StatusOK, gin.H{"message": "Agent already exists"})
        return
    }

    err = AddAgentToDB(id, hostname, hostOS, ip)
    if err != nil {
        c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
        return
    }

    c.JSON(http.StatusOK, gin.H{"message": "Agent added"})
}

func AgentStatus(input []byte) {
    for client := range webStatusClients {
        err := client.WriteMessage(websocket.TextMessage, input)
        if err != nil {
            fmt.Println(err)
            client.Close()
            delete(clients, client)
        }
    }
}
