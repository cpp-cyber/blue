package models

type Inject struct {
    ID         int `gorm:"primaryKey" sql:"AUTO_INCREMENT"`
    Name       string
    Category   string
    Pad        string
    Status     string
    DueDate    string
}
