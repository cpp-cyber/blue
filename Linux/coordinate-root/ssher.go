package main

import (
	"bufio"
	"context"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"fmt"
	"io/ioutil"
	"math/rand"
	"net"
	"os"
	"regexp"
	"strings"
	"sync"
	"time"

	"github.com/bramvdbogaerde/go-scp"
	"github.com/melbahja/goph"
)

var ExitString string

func isValidPort(host string, port int) bool {
	address := fmt.Sprintf("%s:%d", host, port)

	conn, err := net.DialTimeout("tcp", address, 5000*time.Millisecond)
	if err != nil {
		return false
	}
	defer conn.Close()
	banner, err := bufio.NewReader(conn).ReadString('\n')
	regex := regexp.MustCompile(`(?i)windows|winssh`)
	if regex.MatchString(banner) {
		return false
	}

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
			}
			wg.Add(1)
			go ssher(i, client, Script, &wg)
			i.ID++
		}
	}

	wg.Wait()
}

func runner_bf(ip string, outfile string, w *sync.WaitGroup) {
	defer w.Done()
	var err error
	var client *goph.Client
	found := false
	i := instance{
		IP:      ip,
		Outfile: outfile,
	}
	if isValidPort(i.IP, *port) {
		for _, u := range usernameList {
			i.Username = u
			if found {
				break
			}
			if len(passwordList) > 0 {
				for _, p := range passwordList {
					i.Password = p
					if p == "" {
						continue
					}
					DebugExtra(i, "Trying password '"+i.Password+"'")
					client, err = goph.NewUnknown(i.Username, i.IP, goph.Password(i.Password))
					if err != nil {
						AnnoyingErrs = append(AnnoyingErrs, fmt.Sprintf("Error while connecting to %s: %s", i.IP, err))
					} else {
						InfoExtra(i, "Valid credentials for", i.Username)
						found = true
						i.Username = u
						i.Password = p
						defer client.Close()
						ssherWrapper(i, client)
						break
					}
				}
			} else {
				DebugExtra(i, "Using key auth")
				privKey, err := goph.Key(*key, "")
				if err != nil {
					ErrExtra(i, err)
				}
				client, err = goph.NewUnknown(i.Username, i.IP, privKey)
				if err != nil {
					ErrExtra(i, err)
				} else {
					InfoExtra(i, "Valid key for", i.Username)
					found = true
					defer client.Close()
					ssherWrapper(i, client)
				}

			}
		}
	}
}

// Second runner, utilize user/pass combo
func runner_cred(ip string, outfile string, w *sync.WaitGroup, username string, password string) {
	defer w.Done()
	found := false
	deadHost := false
	i := instance{
		IP:       ip,
		Outfile:  outfile,
		Username: username,
		Password: password,
	}
	if isValidPort(i.IP, *port) {
		client, err := goph.NewUnknown(i.Username, i.IP, goph.Password(i.Password))
		if err != nil {
			AnnoyingErrs = append(AnnoyingErrs, fmt.Sprintf("Error while connecting to %s: %s", i.IP, err))
		}
		if err == nil {
			defer client.Close()
			InfoExtra(i, "Valid credentials for", i.Username)
			found = true
			ssherWrapper(i, client)
		}
	}

	if !found && !deadHost {
		AnnoyingErrs = append(AnnoyingErrs, fmt.Sprintf("Login attempt failed to: %s", i.IP))
	}
}

func Upload(client *goph.Client, remotePath string, localPath string) error {
	scp_client, err := scp.NewClientBySSH(client.Client)
	if err != nil {
		return err
	}

	f, _ := os.Open(localPath)
	defer f.Close()

	err = scp_client.CopyFromFile(context.Background(), *f, remotePath, "0777")
	if err != nil {
		return err
	}

	output, err := client.Run("ls " + remotePath)
	if err != nil {
		return err
	}
	if strings.Contains(string(output), "No such file or directory") {
		script, _ := os.ReadFile(localPath)
		uploadScriptCmd := "echo \"" + base64.StdEncoding.EncodeToString(script) + "\" | base64 -d > " + remotePath
		output, err = client.Run(uploadScriptCmd)
		if err != nil {
			return err
		}
	}
	return nil
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

	// Write a temporary file, upload it
	os.WriteFile(filename, []byte(script), 0644)
	err = Upload(client, filename, filename)
	if err != nil {
		ErrExtra(i, err)
		os.Remove(filename)
		return
	}
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()

	output, err = client.RunContext(ctx, fmt.Sprintf("%s ; rm %s", filename, filename))
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
		Stdout(i, fmt.Sprintf("%s", stroutput))
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
