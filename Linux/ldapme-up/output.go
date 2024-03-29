package main

import (
	"fmt"
	"log"
	"os"
	"time"

	//"bufio"
	. "github.com/logrusorgru/aurora"
)

var (
	logger *log.Logger
	tabs   string
)

func InitLogger() {
	logger = log.New(os.Stdout, "", 0)
}

func Tabber(tabnum int) {
	tabs = ""
	for i := 0; i < tabnum; i++ {
		tabs += "\t"
	}
}

func Time() string {
	return time.Now().Format("03:04:05PM")
}

func Err(a ...interface{}) {
	logger.Printf("%s%s %s", tabs, BrightRed("[ERROR]"), fmt.Sprintln(a...))
}

func Fatal(a ...interface{}) {
	logger.Printf("%s%s %s", tabs, BrightRed("[FATAL]"), fmt.Sprintln(a...))
	os.Exit(1)
}

func Warning(a ...interface{}) {
	logger.Printf("%s%s %s", tabs, Yellow("[WARN]"), fmt.Sprintln(a...))
}

func Info(a ...interface{}) {
	logger.Printf("%s%s %s", tabs, BrightCyan("[INFO]"), fmt.Sprintln(a...))
}
