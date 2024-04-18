package main

import (
	"file-server/models"

	"gorm.io/driver/sqlite"
	"gorm.io/gorm"
)

func ConnectToSQLite() *gorm.DB {
	db, err := gorm.Open(sqlite.Open("injects.db"), &gorm.Config{})
	if err != nil {
        panic(err)
	}
    return db
}

func AddInject(name, pad, dueDate string) error {
    inject := models.Inject{Name: name, Pad: pad, Status: "incomplete", DueDate: dueDate}
    result := db.Create(&inject)
    if result.Error != nil {
        return result.Error
    }
    return nil
}

func GetAllInjects() ([]models.Inject, error) {
    var injects []models.Inject
    result := db.Find(&injects)
    if result.Error != nil {
        return nil, result.Error
    }
    return injects, nil
}

func GetInjectByID(pad string) (models.Inject, error) {
    var inject models.Inject
    result := db.Where("IP = ?", pad).First(&inject)
    if result.Error != nil {
        return inject, result.Error
    }
    return inject, nil
}

func EditInjectInDB(id int, status string) error {
    result := db.Model(&models.Inject{}).Where("id = ?", id).Update("status", status)
    if result.Error != nil {
        return result.Error
    }
    return nil
}

func DeleteInjectFromDB(id int) error {
    result := db.Where("id = ?", id).Delete(&models.Inject{})
    if result.Error != nil {
        return result.Error
    }
    return nil
}
