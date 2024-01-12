package main

import (
	"bytes"
	"encoding/json"
	"log"
	"net"
	"net/http"
	"os"
	"runtime"
	"strconv"
    "flag"

	"github.com/google/gopacket"
	"github.com/google/gopacket/layers"
	"github.com/google/gopacket/pcap"
)

var ignore []*net.IPNet
var privateIPBlocks []*net.IPNet
var SERVER_IP *string

func main() {
    SERVER_IP = flag.String("server", "", "Server IP")
    flag.Parse()

	f, err := os.OpenFile("network-agent.txt", os.O_RDWR|os.O_CREATE|os.O_APPEND, 0666)
	if err != nil {
		log.Fatalf("error opening file: %v", err)
	}
	defer f.Close()

	log.SetOutput(f)

	for _, cidr := range []string{
		"224.0.0.0/3",
	} {
		_, block, err := net.ParseCIDR(cidr)
		if err != nil {
			log.Printf("parse error on %q: %v", cidr, err)
		}
		ignore = append(ignore, block)
	}

	for _, cidr := range []string{
		"10.0.0.0/8",
        "172.12.0.0/12",
        "192.168.0.0/16",
	} {
		_, block, err := net.ParseCIDR(cidr)
		if err != nil {
			log.Printf("parse error on %q: %v", cidr, err)
		}
		privateIPBlocks = append(privateIPBlocks, block)
	}

	log.Println("Starting up...")

	ifaces, err := pcap.FindAllDevs()
	if err != nil {
		log.Println(err)
	}

	for _, device := range ifaces {
		log.Printf("Interface Name: %s", device.Name)
		go capturePackets(device.Name)
	}

	select {}
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
		var dstPort int

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

			if !ipIsInBlock(dstIP, privateIPBlocks) || ipIsInBlock(srcIP, ignore) || ipIsInBlock(dstIP, ignore) || dstIP == *SERVER_IP || srcIP == *SERVER_IP {
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

			dstPort, err = strconv.Atoi(dpt)
			if err != nil {
				log.Println(err)
			}

			if dstPort > 30000 {
				continue
			}

			host := interface{}(map[string]interface{}{
				"Src":  srcIP,
				"Dst":  dstIP,
				"Port": dpt,
			})

			jsonData, err := json.Marshal(host)
			if err != nil {
				log.Println(err)
			}

			postData := bytes.NewBuffer(jsonData)
            postUrl := "http://"+*SERVER_IP+"/api/connections"
			http.Post(postUrl, "application/json", postData)

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
