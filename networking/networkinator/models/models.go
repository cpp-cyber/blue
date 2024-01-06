package models

type Host struct {
    IP       string `gorm:"primaryKey"`
	ID       int
    Hostname string
}

type Connection struct {
	ID   string `gorm:"primaryKey"`
	Src  int
	Dst  int
	Port int
}
