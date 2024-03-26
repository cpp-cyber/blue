package main

import (
    "fmt"
    "log"
    "net/http"
    "strings"
    "encoding/json"
    "strconv"

    "github.com/gin-gonic/gin"
    "github.com/gorilla/websocket"
)

func wsAgent(c *gin.Context) {
    _, err := GetAgentByIP(strings.Split(c.Request.RemoteAddr, ":")[0])
    if err != nil {
        c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
        return
    }

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
            log.Println(err)
            conn.Close()
            delete(webClients, conn)
            break
        }

        jsonData := make(map[string]interface{})
        err = json.Unmarshal(msg, &jsonData)
        if err != nil {
            log.Println(err)
            return
        }

        switch jsonData["OpCode"].(float64) {
        case 3:
            id := jsonData["ID"].(string)
            DeleteConnectionFromDB(id)
        }

        agentChan <- jsonData
    }
}

func handleAgentSocket(conn *websocket.Conn) {
    for {
        _, msg, err := conn.ReadMessage()
        if err != nil {
            log.Println(err)

            deadClient := strings.Split(conn.NetConn().RemoteAddr().String(), ":")[0]
            deadAgent, err := GetAgentByIP(deadClient)
            if err != nil {
                log.Println(err)
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
            log.Println(err)
            return
        }

        switch jsonData["OpCode"].(float64) {
        case 0:
            statusChan <- jsonData
        case 5:
            connChan <- jsonData
        case 6:
            connChan <- jsonData
        default:
            log.Println("Unknown OpCode")
        }
    }
}

func handleMsg() {
    for {
        select {
        case msg := <-statusChan:
            jsonData := []byte(fmt.Sprintf(`{"ID": "%s", "Status": "Alive"}`, strconv.FormatFloat(msg["ID"].(float64), 'f', -1, 64)))
            for client := range webClients {
                client.WriteMessage(websocket.TextMessage, jsonData)
            }
        case msg := <-agentChan:
            jsonData, err := json.Marshal(msg)
            if err != nil {
                log.Println(err)
                return
            }
            sendToAgents(jsonData)
        case msg := <-connChan:
            if msg["OpCode"].(float64) == 5 {
                AddConnection(msg)
            } else if msg["OpCode"].(float64) == 6 {
                id := msg["ID"].(string)
                count := msg["Count"].(float64)
                UpdateConnectionCount(id, count)
            }
        }
    }
}   
