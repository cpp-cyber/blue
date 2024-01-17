package main

import (
    "fmt"
    "net/http"
    "strings"
    "encoding/json"
    "strconv"

    "github.com/gin-gonic/gin"
    "github.com/gorilla/websocket"
)

func wsAgent(c *gin.Context) {
    conn, err := upgrader.Upgrade(c.Writer, c.Request, nil)
    if err != nil {
        c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
        return
    }
    agentClients[conn] = true
    go handleAgentSocket(conn)
}

func wsWeb(c *gin.Context) {
    conn, err := upgrader.Upgrade(c.Writer, c.Request, nil)
    if err != nil {
        c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
        return
    }
    webClients[conn] = true
    go handleWebSocket(conn)
}

func handleWebSocket(conn *websocket.Conn) {
    for {
        _, msg, err := conn.ReadMessage()
        if err != nil {
            fmt.Println(err)
            conn.Close()
            delete(webClients, conn)
            break
        }

        jsonData := make(map[string]interface{})
        err = json.Unmarshal(msg, &jsonData)
        if err != nil {
            fmt.Println(err)
            return
        }

        opCode := jsonData["OpCode"].(float64)

        switch opCode {
            case 1:
            default:
                fmt.Println("Unknown OpCode")
        }
    }
}

func handleAgentSocket(conn *websocket.Conn) {
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
            for client := range webClients {
                client.WriteMessage(websocket.TextMessage, jsonData)
            }

            conn.Close()
            delete(agentClients, conn)
            break
        }

        jsonData := make(map[string]interface{})
        err = json.Unmarshal(msg, &jsonData)
        if err != nil {
            fmt.Println(err)
            return
        }

        opCode := jsonData["OpCode"].(float64)

        switch opCode {
            case 0:
                jsonData := []byte(fmt.Sprintf(`{"ID": "%s", "Status": "Alive"}`, strconv.FormatFloat(jsonData["ID"].(float64), 'f', -1, 64)))
                AgentStatus(jsonData)
            case 5:
                AddConnection(jsonData)
            case 6:
                id := jsonData["ID"].(string)
                count := jsonData["Count"].(float64)
                UpdateConnectionCount(id, count)
            default:
                fmt.Println("Unknown OpCode")
        }
    }
}
