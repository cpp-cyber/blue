#!/bin/sh

echo "" > /root/ipa_users

# Get a list of all users
USERS=$(ipa user-find --sizelimit=0 --raw | grep uid: | cut -d: -f2 | tr -d ' ' )

# Output first
for USER in $USERS; do  
        NEW_PASSWORD=$(cat /dev/urandom | tr -dc '[:alpha:][:digit:]' | fold -w ${1:-20} | head -n 1)
        echo $USER,$NEW_PASSWORD >> /root/.ipa_users
done

cat /root/.ipa_users

# Change password for each user
for USER in $USERS; do
        ipa -n user-mod $USER --password $(cat /root/.ipa_users | grep $USER | awk -F ',' '{print $2}') > /dev/null
        ipa -n user-mod $USER --password-expiration 20250730115110Z > /dev/null
done

rm /root/.ipa_users
