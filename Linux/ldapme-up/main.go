package main

import (
	"crypto/rand"
	"crypto/tls"
	"encoding/csv"
	"math/big"
	"os"
	"strings"

	"github.com/go-ldap/ldap/v3"
	flag "github.com/spf13/pflag"
)

type Cred struct {
	username string
	password string
}

var (
	user         = flag.StringP("user", "u", "admin", "The ldap admin user to bind with")
	password     = flag.StringP("password", "p", "", "The ldap admin user password")
	host         = flag.StringP("host", "h", "", "The ldap server to bind to")
	domain       = flag.StringP("domain", "d", "robbys.pastaplace", "The domain to bind to")
	object_class = flag.StringP("object-class", "o", "inetOrgPerson", "Object class identifying users")

	dc_string = ""
	creds     []Cred
)

func GenerateRandomString(length int) (string, error) {
	const charset = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
	charsetLength := big.NewInt(int64(len(charset)))
	result := make([]byte, length)
	for i := range result {
		randomIndex, err := rand.Int(rand.Reader, charsetLength)
		if err != nil {
			return "", err
		}
		result[i] = charset[randomIndex.Int64()]
	}
	return string(result), nil
}

func main() {
	InitLogger()
	flag.Parse()

	if len(*password) == 0 {
		Fatal("Need a password!")
	}

	if len(*host) == 0 {
		Fatal("Need an ldap server!")
	}

	for _, dc := range strings.Split(*domain, ".") {
		dc_string += "dc=" + dc + ","
	}
	dc_string = dc_string[:len(dc_string)-1]

	conn, err := ldap.DialURL("ldap://" + *host)
	if err != nil {
		Fatal("Could not connect to ", *host, " ", err.Error())
	}
	defer conn.Close()

	conn.StartTLS(&tls.Config{InsecureSkipVerify: true})
	if err != nil {
		Fatal("Failed to convert session to TLS: ", err.Error())
	}

	_, err = conn.SimpleBind(&ldap.SimpleBindRequest{
		Username: "uid=" + *user + ",cn=users,cn=accounts," + dc_string,
		Password: *password,
	})
	if err != nil {
		Fatal("Failed to bind: ", err.Error())
	}

	searchRequest := ldap.NewSearchRequest(
		"cn=users,cn=accounts,"+dc_string,
		ldap.ScopeWholeSubtree, ldap.NeverDerefAliases, 0, 0, false,
		"(objectClass="+*object_class+")",
		[]string{"uid"},
		nil,
	)

	searchResult, err := conn.Search(searchRequest)
	if err != nil {
		Fatal("Failed to get a user listing: ", err.Error())
	}

	for _, entry := range searchResult.Entries {
		rand_pw, _ := GenerateRandomString(16)
		_, err = conn.PasswordModify(&ldap.PasswordModifyRequest{
			UserIdentity: "uid=" + entry.GetAttributeValue("uid") + ",cn=users,cn=accounts," + dc_string,
			NewPassword:  rand_pw,
		})
		if err != nil {
			Err("Failed to reset password for "+entry.GetAttributeValue("uid")+" : ", err.Error())
		}

		creds = append(creds, Cred{
			username: entry.GetAttributeValue("uid"),
			password: rand_pw,
		})

		modifyRequest := ldap.NewModifyRequest(
			"uid="+entry.GetAttributeValue("uid")+",cn=users,cn=accounts,"+dc_string,
			[]ldap.Control{},
		)

		modifyRequest.Replace("krbPasswordExpiration", []string{"20300102150405Z"})
		err = conn.Modify(modifyRequest)
		if err != nil {
			Err("Error modifying password expiration date: ", err.Error())
		}
	}

	file, err := os.Create("creds.csv")
	if err != nil {
		Err("Failed creating csv file: ", err.Error())
	}
	defer file.Close()
	csvwriter := csv.NewWriter(file)
	defer csvwriter.Flush()
	_ = csvwriter.Write([]string{"username", "password"})
	for _, record := range creds {
		err = csvwriter.Write([]string{record.username, record.password})
		if err != nil {
			Err("Failed writing entry : ", err.Error())
		}
	}
}
