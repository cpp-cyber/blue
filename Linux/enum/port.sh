#!/bin/sh
while getopts s: opt; do
  case ${opt} in
    s )
       subnet=${OPTARG}
      ;;
 
  esac
done
#subnet="172.16.216.0/24"  # Change this to your desired subnet
echo $subnet
nmap_output=$(nmap -p 3306,1433,5432 -oG - $subnet)

open_ips=$(echo "$nmap_output" | awk '{for (i=1; i<=NF; ++i) {if ($i ~ "3306/open|1433/open|5432/open") print $2 ": " $i}}')

filtered_ips=$(echo "$nmap_output" | awk '{for (i=1; i<=NF; ++i) {if ($i ~ "3306/filtered|1433/filtered|5432/filtered") print $2 ": " $i}}')

closed_ips=$(echo "$nmap_output" | awk '{for (i=1; i<=NF; ++i) {if ($i ~ "3306/closed|1433/closed|5432/closed") print $2 ": " $i}}')

echo "Open IPs:"
echo "$open_ips" | sort
echo
echo "Filtered IPs:"
echo "$filtered_ips" | sort
echo
echo "Closed IPs:"
echo "$closed_ips" | sort

