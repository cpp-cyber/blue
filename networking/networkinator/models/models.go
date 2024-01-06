package models

type Host struct {
	IP string `gorm:"primaryKey"`
	ID int
}

type Connection struct {
	ID   string `gorm:"primaryKey"`
	Src  int
	Dst  int
	Port int
}
