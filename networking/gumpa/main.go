package main

import (
    "bytes"
    "encoding/json"
    "flag"
    "fmt"
    "hash/fnv"
    "log"
    "net"
    "net/http"
    "net/url"
    "os"
    "runtime"
    "strconv"
    "strings"
    "sync"
    "time"
    "bufio"

    "github.com/google/gopacket"
    "github.com/google/gopacket/layers"
    "github.com/google/gopacket/pcap"
    "github.com/gorilla/websocket"
)

var (
    ignore []*net.IPNet

    SERVER_IP *string
    hostname, _ = os.Hostname()

    serverChan = make(chan []byte)

    connMap = make(map[string]int)
    minConnCount = 5

    rwLock sync.RWMutex
    mu sync.Mutex
)

func main() {
    r := bufio.NewReader(os.Stdin)
    buf := make([]byte, 0, 1024)
    n, err := r.Read(buf[:cap(buf)])
    buf = buf[:n]
    key := string(buf)

    if runtime.GOOS == "windows" {
        key = strings.TrimRight(key, "\r\n")
    } else {
        key = strings.TrimRight(key, "\n")
    }

    SERVER_IP = flag.String("server", "", "Server IP")
    flag.Parse()

    f, err := os.OpenFile("network-agent.txt", os.O_RDWR|os.O_CREATE|os.O_APPEND, 0666)
    if err != nil {
        log.Fatalf("error opening file: %v", err)
    }
    defer f.Close()
    log.SetOutput(f)


    log.Println("Starting up...")

    ifaces, err := pcap.FindAllDevs()
    if err != nil {
        log.Println(err)
    }

    appendFilter("224.0.0.0/3")

    hostHash := fmt.Sprint(hash(hostname))
    RegisterAgent(hostHash, key)

    conn := initializeWebSocket(*SERVER_IP, "/ws/agent")
    defer conn.Close()

    go checkin(hostHash)
    go readFilter(conn)

    for _, device := range ifaces {
        log.Printf("Interface Name: %s", device.Name)
        go capturePackets(device.Name)
    }

    for {
        select {
        case t := <-serverChan:
            err = conn.WriteMessage(websocket.TextMessage, t)
            if err != nil {
                log.Println(err)
                return
            }
        }
    }
}

func capturePackets(iface string) {
    if !isInterfaceUp(iface) {
        log.Printf("Interface is down: %s", iface)
        return
    }

    log.Println("Capturing packets on interface: ", iface)
    handle, err := pcap.OpenLive(iface, 1600, true, pcap.BlockForever)
    if err != nil {
        log.Println(err)
    }
    defer handle.Close()

    packetSource := gopacket.NewPacketSource(handle, handle.LinkType())
    for packet := range packetSource.Packets() {
        var srcIP, dstIP string

        ethLayer := packet.Layer(layers.LayerTypeEthernet)
        if ethLayer != nil {
            eth, _ := ethLayer.(*layers.Ethernet)
            if net.HardwareAddr(eth.DstMAC).String() == "ff:ff:ff:ff:ff:ff" {
                continue
            }
        }

        packetNetworkInfo := packet.NetworkLayer()
        if packetNetworkInfo != nil {
            srcIP = packetNetworkInfo.NetworkFlow().Src().String()
            dstIP = packetNetworkInfo.NetworkFlow().Dst().String()

            if strings.Contains(srcIP, ":") || strings.Contains(dstIP, ":") || ipIsInBlock(srcIP, ignore) ||
            ipIsInBlock(dstIP, ignore) || srcIP == *SERVER_IP || dstIP == *SERVER_IP {
                continue
            }

        }

        packetTransportInfo := packet.TransportLayer()
        if packetTransportInfo != nil {
            tcpLayer := packet.Layer(layers.LayerTypeTCP)
            if tcpLayer != nil {
                tcp, _ := tcpLayer.(*layers.TCP)
                if !tcp.SYN && tcp.ACK {
                    continue
                }
            }

            dpt := packetTransportInfo.TransportFlow().Dst().String()
            dstPort, err := strconv.Atoi(dpt)
            if err != nil {
                log.Println(err)
            }

            if dstPort > 30000 {
                continue
            }

            connHash := fmt.Sprint(hash(srcIP+dstIP+dpt))
            if _, ok := connMap[connHash]; ok {
                if connMap[connHash] < minConnCount {
                    incrementConnCount(connHash)
                    continue
                } else if connMap[connHash] == minConnCount {
                    connData := interface{}(map[string]interface{}{
                        "OpCode": 5,
                        "ID": connHash,
                        "Src":  srcIP,
                        "Dst":  dstIP,
                        "Port": dpt,
                        "Count": connMap[connHash],
                    })
                    jsonData, err := json.Marshal(connData)
                    if err != nil {
                        log.Println(err)
                    }
                    incrementConnCount(connHash)
                    serverChan <- jsonData
                } else {
                    connData := interface{}(map[string]interface{}{
                        "OpCode": 6,
                        "ID": connHash,
                        "Src":  "",
                        "Dst":  "",
                        "Port": "",
                        "Count": connMap[connHash],
                    })
                    jsonData, err := json.Marshal(connData)
                    if err != nil {
                        log.Println(err)
                    }
                    incrementConnCount(connHash)
                    serverChan <- jsonData
                }
            } else {
                incrementConnCount(connHash)
            }
        }
    }
}

func ipIsInBlock(ip string, block []*net.IPNet) bool {
    ipAddr := net.ParseIP(ip)
    if ipAddr == nil {
        log.Println("Invalid IP address")
        return false
    }
    for _, block := range block {
        if block.Contains(ipAddr) {
            return true
        }
    }
    return false
}

func appendFilter(cidr string) {
    _, block, err := net.ParseCIDR(cidr)
    if err != nil {
        log.Printf("parse error on %q: %v", cidr, err)
    }
    rwLock.Lock()
    ignore = append(ignore, block)
    rwLock.Unlock()
}

func removeFilter(cidr string) {
    _, block, err := net.ParseCIDR(cidr)
    if err != nil {
        log.Printf("parse error on %q: %v", cidr, err)
    }
    for i, b := range ignore {
        if b.String() == block.String() {
            rwLock.Lock()
            ignore = append(ignore[:i], ignore[i+1:]...)
            rwLock.Unlock()
        }
    }
}

func isInterfaceUp(interfaceName string) bool {
    if runtime.GOOS == "windows" {
        return true
    }

    iface, err := net.InterfaceByName(interfaceName)
    if err != nil {
        log.Printf("Error getting interface %s: %s", interfaceName, err)
        return false
    }
    return iface.Flags&net.FlagUp != 0
}

func initializeWebSocket(server, path string) *websocket.Conn {
    log.Println("Initializing WebSocket...")
    url := url.URL{Scheme: "ws", Host: server, Path: path}
    conn, _, err := websocket.DefaultDialer.Dial(url.String(), nil)
    if err != nil {
        log.Println(err)
    }
    return conn
}

func RegisterAgent(hash, key string) {
    log.Println("Registering agent...")

    hostOS := runtime.GOOS

    host := interface{}(map[string]interface{}{
        "ID": fmt.Sprint(hash),
        "Hostname": hostname,
        "HostOS": hostOS,
        "Key": key,
    })

    jsonData, err := json.Marshal(host)
    if err != nil {
        log.Println(err)
    }

    _, err = http.Post("http://"+*SERVER_IP+"/api/agents/add", "application/json", bytes.NewBuffer(jsonData))
    if err != nil {
        log.Println(err)
    }
}

func checkin(hostHash string) {
    ping := []byte(fmt.Sprintf(`{"OpCode": 0, "ID": %s, "Status": "Alive"}`, hostHash))
    for {
        serverChan <- ping
        time.Sleep(2 * time.Second)
    }
}

func readFilter(conn *websocket.Conn) {
    for {
        _, msg, err := conn.ReadMessage()
        if err != nil {
            fmt.Println(err)
        } else {
            filter := make(map[string]interface{})
            err := json.Unmarshal(msg, &filter)
            if err != nil {
                fmt.Println(err)
            }

            opCode := filter["OpCode"].(float64)

            fmt.Println(filter)

            switch opCode {
            case 1:
                appendFilter(filter["CIDR"].(string))
                fmt.Println(ignore)
            case 2:
                removeFilter(filter["CIDR"].(string))
            default:
                log.Println("Invalid OpCode")
            }

        }
    }
}

func hash(s string) uint32 {
    h := fnv.New32a()
    h.Write([]byte(s))
    return h.Sum32()
}

func incrementConnCount(connHash string) {
    rwLock.Lock()
    connMap[connHash]++
    rwLock.Unlock()
}

func readConnCount(connHash string) int {
    rwLock.RLock()
    defer rwLock.RUnlock()
    return connMap[connHash]
}
