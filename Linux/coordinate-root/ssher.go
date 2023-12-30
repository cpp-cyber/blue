package main

import (
	"context"
	"encoding/hex"
	"errors"
	"fmt"
	"io/ioutil"
	"math/rand"
	"net"
	"os"
	"strings"
	"sync"
	"time"

	"github.com/melbahja/goph"
)

const (
	// Running states
	RUN_WAIT = iota
	RUN_ACTIVE
	RUN_ERROR
	RUN_END
)

const (
	RANDSTRLEN = 12
)

const (
	// Parsing states
	NONE = iota
	IF
	IF_FALSE
	ELSE
	ROULETTE_WAITING
	ROULETTE_TRUE
	ROULETTE_RAN
	OUTPUT_ACTIVE
)

var (
	rouletteRoll    int
	rouletteCounter int
)

type scriptState struct {
	Output      bool
	Conditional uint
	Roulette    uint
}

var ExitString string

func isPortOpen(host string, port int) bool {
	address := fmt.Sprintf("%s:%d", host, port)

	conn, err := net.DialTimeout("tcp", address, 500*time.Millisecond)
	if err != nil {
		return false
	}
	defer conn.Close()

	return true
}

func ssherWrapper(i instance, client *goph.Client) {
	var wg sync.WaitGroup

	// Distribute files over X threads
	first := true
	for _, path := range scripts {
		var Script string
		i.Script = path
		if *CreateConfig {
			Script += CreateConfigScript
		} else {
			ScriptContents, err := ioutil.ReadFile(path)
			if err != nil {
				Crit(i, errors.New("Error reading "+i.Script+": "+err.Error()))
				continue
			}
			for _, cmd := range environCmds {
				Script += fmt.Sprintf("%s ", cmd)
			}

			Script += string(ScriptContents)
		}

		for t := 0; t < *threads && t < len(scripts); t++ {
			if first {
				first = false
			} else {
			}
			wg.Add(1)
			go ssher(i, client, Script, &wg)
			i.ID++
		}
	}

	wg.Wait()
}

func runner(ip string, outfile string, w *sync.WaitGroup) {
	defer w.Done()
	var err error
	var client *goph.Client
	found := false
	deadHost := false
	i := instance{
		IP:      ip,
		Outfile: outfile,
	}

	for _, u := range usernameList {
		if found || deadHost {
			break
		}
		for _, p := range passwordList {
			i.Username = u
			i.Password = p
			if *debug && *passwords != "" {
				InfoExtra(i, "Trying password '"+i.Password+"'")
			}
			if isPortOpen(i.IP, *port) {
				client, err = goph.NewUnknown(i.Username, i.IP, goph.Password(i.Password))
				if err != nil && strings.Contains(err.Error(), "Could not connect") {
					deadHost = true
					break
				} else if err != nil {
					AnnoyingErrs = append(AnnoyingErrs, fmt.Sprintf("Error while connecting to %s: %s", i.IP, err))
				}
				if err == nil {
					defer client.Close()
					InfoExtra(i, "Valid credentials for", i.Username)
					found = true
					i.Username = u
					i.Password = p
					ssherWrapper(i, client)
					break
				}
			} else {
				deadHost = true
			}
		}
	}

	if !found {
		if err != nil && strings.Contains(err.Error(), "Could not connect") {
			return
		}
		if !deadHost {
			AnnoyingErrs = append(AnnoyingErrs, fmt.Sprintf("Login attempt failed to: %s", i.IP))
		}
		return
	}
}

// Second runner, utilize user/pass combo
// Nothing like more janky by redefining the runner for individual cred sets
func GeraldRunner(ip string, outfile string, w *sync.WaitGroup, username string, password string) {
	defer w.Done()

	var err error

	found := false
	deadHost := false
	i := instance{
		IP:       ip,
		Outfile:  outfile,
		Username: username,
		Password: password,
	}

	if isPortOpen(i.IP, *port) {
		client, err := goph.NewUnknown(i.Username, i.IP, goph.Password(i.Password))
		if err != nil && strings.Contains(err.Error(), "Could not connect") {
			deadHost = true
		} else if err != nil {
			AnnoyingErrs = append(AnnoyingErrs, fmt.Sprintf("Error while connecting to %s: %s", i.IP, err))
		}
		if err == nil {
			defer client.Close()
			InfoExtra(i, "Valid credentials for", i.Username)
			found = true
			ssherWrapper(i, client)
		}
	}

	if !found {
		if err != nil && strings.Contains(err.Error(), "Could not connect") {
			return
		}
		if !deadHost {
			AnnoyingErrs = append(AnnoyingErrs, fmt.Sprintf("Login attempt failed to: %s", i.IP))
		}
		return
	}
}
func ssher(i instance, client *goph.Client, script string, wg *sync.WaitGroup) {

	defer wg.Done()
	var stroutput string

	filename := fmt.Sprintf("/tmp/%s", generateRandomFileName(16))

	// invalid command to see if we got a working shell
	output, err := client.Run("echo a ; asdfhasdf")
	if len(output) == 0 {
		Err(fmt.Sprintf("%s: Couldn't read stdout. Coordinate does not work with this host's shell probably\n", i.IP))
		BrokenHosts = append(BrokenHosts, i.IP)
		return
	}

	// prepend some commands for fingerprinting
	name := "hostname"
	output, err = client.Run(name)
	if err != nil { // not hostname? fuck it, try cat /etc/hostname
		name = "cat /etc/hostname"
		output, err = client.Run(name)
	}
	stroutput = string(output)
	if !strings.Contains(stroutput, "No such file or directory") {
		stroutput = string(output)
		stroutput = strings.Replace(stroutput, "\n", "", -1)
		i.Hostname = stroutput
		i.Outfile = i.Hostname + "." + i.Outfile
	} else {
		i.Outfile = i.IP + "." + i.Outfile
	}

	// Write a temporary file, upload it, execute it, and clean
	os.WriteFile(filename, []byte(script), 0644)
	client.Upload(filename, filename)

	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()

	output, err = client.RunContext(ctx, fmt.Sprintf("chmod 777 %s ; %s ; rm %s", filename, filename, filename))
	stroutput = string(output)

	if err != nil {
		if strings.Contains(err.Error(), "context deadline exceeded") {
			if len(i.Hostname) > 0 {
				AnnoyingErrs = append(AnnoyingErrs, fmt.Sprintf("%s timed out on %s", i.Script, i.Hostname))
			} else {
				AnnoyingErrs = append(AnnoyingErrs, fmt.Sprintf("%s timed out on %s", i.Script, i.IP))
			}
		} else {
			Err(fmt.Sprintf("%s: Error running script: %s\n", i.IP, err))
		}
	}
	if len(stroutput) > 0 {
		Stdout(i, fmt.Sprintf("%s\n", stroutput))
		if *CreateConfig {
			for _, line := range strings.Split(stroutput, "\n") {
				if strings.Split(line, ",")[0] == i.Username {
					Password := strings.Split(line, ",")[1]
					Entry := ConfigEntry{i.IP, i.Username, Password}
					ConfigEntries = append(ConfigEntries, Entry)
				}
			}
		}
	}
	os.Remove(filename)

	TotalRuns++

}

func generateRandomFileName(length int) string {
	randomBytes := make([]byte, length)
	rand.Read(randomBytes)

	randomFileName := hex.EncodeToString(randomBytes)

	return randomFileName
}
