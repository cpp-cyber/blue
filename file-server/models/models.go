package models

type Inject struct {
    ID         string `gorm:"primaryKey"`
    Name       string
    Category   string
    Pad        string
    Status     string
}
