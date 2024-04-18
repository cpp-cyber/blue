package models

type Inject struct {
    ID         uint64 `gorm:"primaryKey;autoIncrement"` 
    Name       string
    Category   string
    Pad        string
    Status     string
}
