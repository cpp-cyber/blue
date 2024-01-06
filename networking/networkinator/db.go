package main

import (
	"WebService/models"
    "fmt"

	"github.com/google/uuid"
	"gorm.io/driver/sqlite"
	"gorm.io/gorm"
)

func connectToSQLite() (*gorm.DB, error) {
	db, err := gorm.Open(sqlite.Open("network.db"), &gorm.Config{})
	if err != nil {
		return nil, err
	}
	return db, nil
}

func createHost(db *gorm.DB, ip, hostname string) error {
	host := models.Host{IP: ip, ID: HostCount, Hostname: hostname}
    result := db.Create(&host)
	if result.Error != nil {
		return result.Error
	}
	HostCount++
	return nil
}

func createConnection(db *gorm.DB, src, dst, port int) error {

	id := uuid.New().String()

	connection := models.Connection{ID: id, Src: src, Dst: dst, Port: port}
	result := db.Create(&connection)
	if result.Error != nil {
		return result.Error
	}
	return nil
}

func updateHost(db *gorm.DB, ip, hostname string) error {
    host := models.Host{IP: ip, Hostname: hostname}
    result := db.Model(&host).Update("hostname", hostname)
    if result.Error != nil {
        return result.Error
    }
    return nil
}

func getHostsEntries(db *gorm.DB, filter string) ([]models.Host, error) {
	var hosts []models.Host
	result := db.Where("hostname LIKE ?", filter).Find(&hosts)
    fmt.Println(filter)
	if result.Error != nil {
		return nil, result.Error
	}
	return hosts, nil
}

func getConnections(db *gorm.DB) ([]models.Connection, error) {
	var connections []models.Connection
	result := db.Find(&connections)
	if result.Error != nil {
		return nil, result.Error
	}
	return connections, nil
}
