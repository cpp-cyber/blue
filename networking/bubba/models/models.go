package models

type Connection struct {
	ID    string `gorm:"primaryKey"`
	Src   string
	Dst   string
	Port  int
    Count int
}

type Agent struct {
    ID       string `gorm:"primaryKey"`
    Hostname string
    HostOS   string
    IP       string
    Status   string
}
