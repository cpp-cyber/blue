package main

import (
    "fmt"
    "net/http"
    "strings"

    "github.com/gin-gonic/gin"
    "github.com/gorilla/websocket"
)

func ws(c *gin.Context) {
    conn, err := upgrader.Upgrade(c.Writer, c.Request, nil)
    if err != nil {
        c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
        return
    }

    clients[conn] = true

    go handleAgentConnectionSocket(conn)
}

func wsAgentStatus(c *gin.Context) {
    conn, err := upgrader.Upgrade(c.Writer, c.Request, nil)
    if err != nil {
        c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
        return
    }

    agentStatusClients[conn] = true

    go handleAgentStatusSocket(conn)
}

func GetAgentStatus(c *gin.Context) {
    conn, err := upgrader.Upgrade(c.Writer, c.Request, nil)
    if err != nil {
        c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
        return
    }

    webStatusClients[conn] = true

    go handleWebStatusSocket(conn)
}

func handleWebStatusSocket(conn *websocket.Conn) {
    for {
        _, _, err := conn.ReadMessage()
        if err != nil {
            fmt.Println(err)
            conn.Close()
            delete(webStatusClients, conn)
            break
        }
    }
}

func handleAgentConnectionSocket(conn *websocket.Conn) {
  for {
    _, msg, err := conn.ReadMessage()
    if err != nil {
      fmt.Println(err)
      conn.Close()
      delete(clients, conn)
      break
    }
    AddConnection(msg)
  }
}

func handleAgentStatusSocket(conn *websocket.Conn) {
    for {
        _, msg, err := conn.ReadMessage()
        if err != nil {
            fmt.Println(err)

            deadClient := strings.Split(conn.NetConn().RemoteAddr().String(), ":")[0]

            deadAgent, err := GetAgentByIP(deadClient)
            if err != nil {
                fmt.Println(err)
                return
            }

            jsonData := []byte(fmt.Sprintf(`{"ID": "%s", "Status": "Dead"}`, deadAgent.ID))
            for client := range webStatusClients {
                client.WriteMessage(websocket.TextMessage, jsonData)
                UpdateAgentStatus(deadClient, "Dead")
            }

            conn.Close()
            delete(agentStatusClients, conn)
            break
        }
        AgentStatus(msg)
    }
}
