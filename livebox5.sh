#!/bin/bash

# An upgraded CLI interface for communicating with a Livebox 5
# Author: Eylexander
# License: CC-BY-NC-SA
# Requires : jq, curl
# Inspired by Maël Valais' livebox4.sh script

# set -x
set -o pipefail

# Configuration
# -------------
# Livebox 5 IP address
LIVEBOX_IP=${LIVEBOX_IP:-192.168.1.1}
# Livebox 5 username
LIVEBOX_USERNAME=${LIVEBOX_USERNAME:-admin}
# Livebox 5 password
LIVEBOX_PASSWORD=${LIVEBOX_PASSWORD:-admin}
# Debug mode
DEBUG=${DEBUG:-false}
# Script version
SCRIPT_VERSION="0.1.0"
# -------------

if [ -t 1 ] || [ "$COLOR" = always ] && [ "$COLOR" != never ]; then
    # Colors
    COLOR_RESET='\e[0m'
    COLOR_RED='\e[31m'
    COLOR_GREEN='\e[32m'
    COLOR_YELLOW='\e[33m'
    COLOR_BLUE='\e[34m'
    COLOR_MAGENTA='\e[35m'
    COLOR_CYAN='\e[36m'
    COLOR_WHITE='\e[37m'
    COLOR_GREY='\e[90m'
    COLOR_BOLD='\e[1m'
    COLOR_DIM='\e[2m'
    COLOR_UNDERLINED='\e[4m'
    COLOR_BLINK='\e[5m'
    COLOR_INVERTED='\e[7m'
    COLOR_HIDDEN='\e[8m'

    # Status signs
    STATUS_SUCCESS="${COLOR_GREEN}✔ ${COLOR_RESET}"
    STATUS_ERROR="${COLOR_RED}✘ ${COLOR_RESET}"
    STATUS_WARNING="${COLOR_YELLOW}⚠ ${COLOR_RESET}"
    STATUS_INFO="${COLOR_BLUE}[ℹ] ${COLOR_RESET}"
fi

help() {
    cat <<EOF

   __ _           _               ____    __           _       _   
  / /(_)_   _____| |__   _____  _| ___|  / _\ ___ _ __(_)_ __ | |_ 
 / / | \ \ / / _ \ '_ \ / _ \ \/ /___ \  \ \ / __| '__| | '_ \| __|
/ /__| |\ V /  __/ |_) | (_) >  < ___) | _\ \ (__| |  | | |_) | |_ 
\____/_| \_/ \___|_.__/ \___/_/\_\____/  \__/\___|_|  |_| .__/ \__|
                                                        |_|        

Usage: $0 [options] <command> [arguments]

Options:
    -h, --help      Show this help message and exit
    --version   Show version number and exit
    -u, --username  Livebox 5 username
    -p, --password  Livebox 5 password
    --ip            Livebox 5 IP address
    --debug         Enable debug mode
    -v, --verbose   Enable verbose mode

Commands:
    reboot          Reboot the Livebox 5
    phone           Get phone information and phone call history
    speedtest       Run a speedtest
    firewall        Interact with the firewall
        add         Add a firewall rule
        remove      Remove a firewall rule
        list        List firewall rules
    clearcache      Clear the cache
    custom          Run a custom POST request
    
Eylexander - 2023
EOF
    exit
}

COMMAND_INPUT=

if [ $# -eq 0 ]; then
    help
    exit
fi

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            help
            ;;
        --version)
            echo -e "${STATUS_INFO}livebox5.sh by Eylexander v${SCRIPT_VERSION}"
            exit
            ;;
        -u|--username)
            shift
            if test -z "$1"; then
                echo -e "${STATUS_ERROR}Error: missing username"
                exit 1
            fi
            LIVEBOX_USERNAME="$1"
            ;;
        -p|--password)
            shift
            if test -z "$1"; then
                echo -e "${STATUS_ERROR}Error: missing password"
                exit 1
            fi
            LIVEBOX_PASSWORD="$1"
            ;;
        --ip)
            shift
            if test -z "$1"; then
                echo -e "${STATUS_ERROR}Error: missing IP address"
                exit 1
            fi
            LIVEBOX_IP="$1"
            ;;
        --debug)
            DEBUG=true
            ;;
        *)
            COMMAND_INPUT="$1"
            ;;
    esac
    shift
done


# Constants
# ---------
# Livebox 5 API URL
LIVEBOX_API_URL="http://${LIVEBOX_IP}/ws"
# JSON folder
JSON_FOLDER="json"
# -------------


if [ "$DEBUG" = true ]; then
    echo -e "${STATUS_INFO}Debug mode enabled"
    set -x
fi

case "$COMMAND_INPUT" in
        info|reboot|phone|speedtest|firewall|clearcache|custom)
            mkdir -p "$JSON_FOLDER"
        ;;
    *)
        echo -e "${STATUS_ERROR}Error: Invalid command"
        exit 1
        ;;
esac
shift

tracker() {
    if [ "$DEBUG" = true ]; then
        set -x
        printf "%s ${COLOR_GREY}" "$1" >&2
        LANG=C perl -e 'print join (" ", map { $_ =~ / / ? "\"".$_."\"" : $_} @ARGV)' -- "${@:2}" >&2
        printf "${COLOR_RESET}\n" >&2
    fi
    command "$@" | tee >(
        if [ "$DEBUG" = true ]; then
            printf "${COLOR_GREY}" >&2
            cat >&2
            printf "${COLOR_RESET}" >&2
        else
            cat >/dev/null
        fi
    )
}

# Create the headers to send to the Livebox 5
RESPONSE=$(
    tracker curl --fail -i -S -s $LIVEBOX_API_URL -H 'Authorization: X-Sah-Login' -H 'Content-Type: application/x-sah-ws-4-call+json' \
        -d '{"service":"sah.Device.Information","method":"createContext","parameters":{"applicationName":"webui","username":"'"$LIVEBOX_USERNAME"'","password":"'"$LIVEBOX_PASSWORD"'"}}'
)
HEADERS=$(
    echo -e "$RESPONSE" | grep ^Set-Cookie | sed 's/^Set-//' | xargs -0 printf "%s"
    echo -e "$RESPONSE" | tail -n1 | jq -r .data.contextID | xargs -0 printf "Authorization: X-Sah %s"
)

# Phone functions
# ---------------
# Get phone information
getPhoneInfo() {
    tracker curl -s -S -X POST -H "$HEADERS" -H 'Content-Type: application/x-sah-ws-4-call+json' \
        -d '{"service":"VoiceService.VoiceApplication","method":"listTrunks","parameters":{}}' \
        "$LIVEBOX_API_URL" | jq '[.status[].trunk_lines[] | {name, enable, status, directoryNumber}]'
}
# Get phone call history
getPhoneCallHistory() {
    tracker curl -s -S -X POST -H "$HEADERS" -H 'Content-Type: application/x-sah-ws-4-call+json' \
        -d '{"service":"VoiceService.VoiceApplication","method":"getCallList","parameters":[{"line": "1"}]}' \
        "$LIVEBOX_API_URL" | jq -r '[.status[] | {remoteNumber, startTime, duration, callId}]'
}
# ---------------

# Run the command
case "$COMMAND_INPUT" in
    info)
        if DISPLAY_FORM=$(whiptail --backtitle "Eylexander's Livebox5.sh" --title "How to print the output?" --radiolist "Choose an option" 10 80 3 \
            "1" "Print the output in the terminal (reduced)" OFF\
            "2" "Print the output in a file (detailed)" OFF \
            "3" "Print the output in the terminal (reduced) and in a file" ON \
            3>&1 1>&2 2>&3); then
            case "$DISPLAY_FORM" in
                1)
                    echo -e "${STATUS_INFO}Printing the output in the terminal..."
                    echo -e "${STATUS_INFO}Getting Livebox 5 information..."
                    tracker curl -s -S -X POST -H "$HEADERS" -H 'Content-Type: application/x-sah-ws-4-call+json' \
                        -d '{"service":"DeviceInfo","method":"get","parameters":{}}' \
                        "$LIVEBOX_API_URL" | jq \
                    ;;
                2)
                    echo -e "${STATUS_INFO}Printing the output in a file..."


                    echo "[" > $JSON_FOLDER/livebox5-info-time.json
                    echo -e "${STATUS_INFO}Getting Livebox 5 time information..."
                    tracker curl -s -S -X POST -H "$HEADERS" -H 'Content-Type: application/x-sah-ws-4-call+json' \
                        -d '{"service":"Time","method":"getTime","parameters":{}}' \
                        "$LIVEBOX_API_URL" | jq >> $JSON_FOLDER/livebox5-info-time.json
                    echo "," >> $JSON_FOLDER/livebox5-info-time.json

                    tracker curl -s -S -X POST -H "$HEADERS" -H 'Content-Type: application/x-sah-ws-4-call+json' \
                        -d '{"service":"Time","method":"getLocalTimeZoneName","parameters":{}}' \
                        "$LIVEBOX_API_URL" | jq >> $JSON_FOLDER/livebox5-info-time.json
                    echo "," >> $JSON_FOLDER/livebox5-info-time.json
                    echo "]" >> $JSON_FOLDER/livebox5-info-time.json



                    echo "[" > $JSON_FOLDER/livebox5-info-wifi.json
                    echo -e "${STATUS_INFO}Getting Livebox 5 wifi information..."
                    tracker curl -s -S -X POST -H "$HEADERS" -H 'Content-Type: application/x-sah-ws-4-call+json' \
                        -d '{"service":"NMC","method":"getWANStatus","parameters":{}}' \
                        "$LIVEBOX_API_URL" | jq >> $JSON_FOLDER/livebox5-info-wifi.json
                    echo "," >> $JSON_FOLDER/livebox5-info-wifi.json

                    tracker curl -s -S -X POST -H "$HEADERS" -H 'Content-Type: application/x-sah-ws-4-call+json' \
                        -d '{"service":"NMC","method":"get","parameters":{}}' \
                        "$LIVEBOX_API_URL" | jq >> $JSON_FOLDER/livebox5-info-wifi.json
                    echo "," >> $JSON_FOLDER/livebox5-info-wifi.json

                    tracker curl -s -S -X POST -H "$HEADERS" -H 'Content-Type: application/x-sah-ws-4-call+json' \
                        -d '{"service":"NetMaster","method":"getInterfaceConfig","parameters":{"name":"GPON_DHCP"}}' \
                        "$LIVEBOX_API_URL" | jq >> $JSON_FOLDER/livebox5-info-wifi.json
                    echo "," >> $JSON_FOLDER/livebox5-info-wifi.json

                    tracker curl -s -S -X POST -H "$HEADERS" -H 'Content-Type: application/x-sah-ws-4-call+json' \
                        -d '{"service":"NeMo.Intf.data","method":"getMIBs","parameters":{"mibs":"dhcp"}}' \
                        "$LIVEBOX_API_URL" | jq >> $JSON_FOLDER/livebox5-info-wifi.json
                    echo "," >> $JSON_FOLDER/livebox5-info-wifi.json

                    tracker curl -s -S -X POST -H "$HEADERS" -H 'Content-Type: application/x-sah-ws-4-call+json' \
                        -d '{"service":"NeMo.Intf.lan","method":"getMIBs","parameters":{"mibs":"wlanvap","flag":"wlanvap !secondary"}}' \
                        "$LIVEBOX_API_URL" | jq >> $JSON_FOLDER/livebox5-info-wifi.json
                    echo "," >> $JSON_FOLDER/livebox5-info-wifi.json

                    tracker curl -s -S -X POST -H "$HEADERS" -H 'Content-Type: application/x-sah-ws-4-call+json' \
                        -d '{"service":"NeMo.Intf.guest","method":"getMIBs","parameters":{"mibs":"wlanvap"}}' \
                        "$LIVEBOX_API_URL" | jq >> $JSON_FOLDER/livebox5-info-wifi.json
                    echo "]" >> $JSON_FOLDER/livebox5-info-wifi.json



                    echo "[" > $JSON_FOLDER/livebox5-info-network.json
                    echo -e "${STATUS_INFO}Getting Livebox 5 network information..."
                    tracker curl -s -S -X POST -H "$HEADERS" -H 'Content-Type: application/x-sah-ws-4-call+json' \
                        -d '{"service":"TopologyDiagnostics","method":"buildTopology","parameters":{"SendXmlFile":false}}' \
                        "$LIVEBOX_API_URL" | jq '.status[].Children[0]' >> $JSON_FOLDER/livebox5-info-network.json 
                    echo "," >> $JSON_FOLDER/livebox5-info-network.json
                    tracker curl -s -S -X POST -H "$HEADERS" -H 'Content-Type: application/x-sah-ws-4-call+json' \
                        -d '{"service":"DHCPv4.Server.Pool.default","method":"getStaticLeases","parameters":"default"}' \
                        "$LIVEBOX_API_URL" | jq '[.status[]]' >> $JSON_FOLDER/livebox5-info-network.json
                    echo "]" >> $JSON_FOLDER/livebox5-info-network.json



                    echo -e "${STATUS_INFO}Response saved in $(echo $(pwd)/$JSON_FOLDER/livebox5-info.json)"
                    ls -1 $JSON_FOLDER | grep info
                    ;;
                3)
                    echo -e "${STATUS_INFO}Printing the output in the terminal and in a file..."
                    echo -e "${STATUS_INFO}Getting Livebox 5 information..."
                    tracker curl -s -S -X POST -H "$HEADERS" -H 'Content-Type: application/x-sah-ws-4-call+json' \
                        -d '{"service":"DeviceInfo","method":"get","parameters":{}}' \
                        "$LIVEBOX_API_URL" | tee $JSON_FOLDER/livebox5-info.json | jq \
                    ;;
            esac
        else
            echo -e "${STATUS_ERROR}Error: No option selected"
            exit 1
        fi
        ;;
    reboot)
        echo -e "${STATUS_INFO}Rebooting Livebox 5..."
        tracker curl --fail -s -S -X POST -H "$HEADERS" -H 'Content-Type: application/x-sah-ws-4-call+json' \
            -d '{"service":"NMC","method":"reboot","parameters":{"reason":"GUI_Reboot"}}' \
            "$LIVEBOX_API_URL" | jq -r .status
        ;;

    phone)
        if DISPLAY_FORM=$(whiptail --backtitle "Eylexander's Livebox5.sh" --title "How to print the output?" --radiolist "Choose an option" 10 80 3 \
            "1" "Print the output in the terminal" OFF\
            "2" "Print the output in a file" OFF \
            "3" "Print the output in the terminal (reduced) and in a file" ON \
            3>&1 1>&2 2>&3); then
            case "$DISPLAY_FORM" in
                1)
                    echo -e "${STATUS_INFO}Printing the output in the terminal..."
                    echo -e "${STATUS_INFO}Getting phone informations..."
                    getPhoneInfo
                    echo -e "${STATUS_INFO}Getting phone call history..."
                    getPhoneCallHistory
                    ;;
                2)
                    echo -e "${STATUS_INFO}Printing the output in a file..."
                    getPhoneInfo > $JSON_FOLDER/livebox5-phoneInfo.json
                    getPhoneCallHistory > $JSON_FOLDER/livebox5-phoneCallHistory.json
                    echo -e "${STATUS_INFO}$(echo $(pwd)/$JSON_FOLDER/)\n$(ls -1 $JSON_FOLDER | grep phone)"
                    ;;
                3)
                    echo -e "${STATUS_INFO}Printing the output in the terminal and in a file..."
                    echo -e "${STATUS_INFO}Getting phone informations..."
                    getPhoneInfo | tee $JSON_FOLDER/livebox5-phoneInfo.json | jq
                    echo -e "${STATUS_INFO}Getting last phone call from history..."
                    getPhoneCallHistory | tail -n 7 | head -n 6 | tee $JSON_FOLDER/livebox5-phoneCallHistory.json | jq
                    ;;
            esac
        else
            echo -e "${STATUS_ERROR}Error: No option selected"
            exit 1
        fi
        ;;
    speedtest)
        echo -e "${STATUS_INFO}Running speedtest..."
        tracker curl -s -S -X POST -H "$HEADERS" -H 'Content-Type: application/x-sah-ws-4-call+json' \
            -d '{"service":"NMC","method":"startSpeedTest","parameters":{}}' \
            "$LIVEBOX_API_URL" | jq -r .status

        # Disclaimer
        echo -e "${STATUS_INFO}Disclaimer: The speedtest might not be functional."
        ;;
    firewall)
        if ACTION=$(whiptail --backtitle "Eylexander's Livebox5.sh" --title "What to do?" --radiolist "Choose an option" 10 80 3 \
            "1" "Add a firewall rule" OFF\
            "2" "Remove a firewall rule" OFF \
            "3" "List firewall rules" ON \
            3>&1 1>&2 2>&3); then
            case "$ACTION" in
                1)
                    echo -e "${STATUS_INFO}Adding a firewall rule..."
                    TMP_EDIT=$(mktemp)
                    TMP_DOC=$(mktemp)
                    cat > $TMP_EDIT <<EOF
{
    "service": "Firewall",
    "method": "setPortForwarding",
    "parameters": {
        "id": "NAME",
        "internalPort": "PORT",
        "externalPort": "PORT",
        "destinationIPAddress": "192.168.X.X",
        "enable": true,
        "persistent": true,
        "protocol": "17",
        "description": "NAME",
        "sourceInterface": "data",
        "origin": "webui",
        "destinationMACAddress": ""
    }
}
EOF
                    cat > $TMP_DOC <<EOF
# Informations

This file only represents documentation, you can close it easily
Feel free to copy/paste the following template in a better editor
Protocol: 6 = TCP, 17 = UDP, TCP/UDP = 6,17

# Example
{
    "service": "Firewall",
    "method": "setPortForwarding",
    "parameters": {
        "id": "HTTPS",
        "internalPort": "443",
        "externalPort": "443",
        "destinationIPAddress": "192.168.1.24",
        "enable": true,
        "persistent": true,
        "protocol": "6",
        "description": "HTTPS",
        "sourceInterface": "data",
        "origin": "webui",
        "destinationMACAddress": ""
    }
}
EOF
                    nano $TMP_DOC; nano $TMP_EDIT

                    echo -e "${STATUS_INFO}Sending command..."
                    tracker curl -s -S -X POST -H "$HEADERS" -H 'Content-Type: application/x-sah-ws-4-call+json' \
                        -d "$(< $TMP_EDIT)" \
                        "$LIVEBOX_API_URL" | jq

                    tracker curl -s -S -X POST -H "$HEADERS" -H 'Content-Type: application/x-sah-ws-4-call+json' \
                        -d '{"service":"Firewall","method":"commit","parameters":{}}' \
                        "$LIVEBOX_API_URL" | jq

                    echo -e "${STATUS_INFO}Done."
                    ;;
                2)
                    echo -e "${STATUS_INFO}Removing a firewall rule..."
                    TMP_EDIT=$(mktemp)
                    TMP_DOC=$(mktemp)
                    cat > $TMP_EDIT <<EOF
{
    "service": "Firewall",
    "method": "deletePortForwarding",
    "parameters": {
        "id": "NAME",
        "destinationIPAddress": "192.168.X.X",
        "origin": "webui"
    }
}
EOF
                    cat > $TMP_DOC <<EOF
# Informations

This file only represents documentation, you can close it easily
Feel free to copy/paste the following template in a better editor

# Example

{
    "service": "Firewall",
    "method": "deletePortForwarding",
    "parameters": {
        "id": "HTTPS",
        "destinationIPAddress": "192.168.1.24",
        "origin": "webui"
    }
}
EOF

                    nano $TMP_DOC; nano $TMP_EDIT

                    echo -e "${STATUS_INFO}Sending command..."
                    tracker curl -s -S -X POST -H "$HEADERS" -H 'Content-Type: application/x-sah-ws-4-call+json' \
                        -d "$(< $TMP_EDIT)" \
                        "$LIVEBOX_API_URL" | jq

                    tracker curl -s -S -X POST -H "$HEADERS" -H 'Content-Type: application/x-sah-ws-4-call+json' \
                        -d '{"service":"Firewall","method":"commit","parameters":{}}' \
                        "$LIVEBOX_API_URL" | jq
                    echo -e "${STATUS_INFO}Done."
                    ;;
                3)
                    echo -e "${STATUS_INFO}Listing WebUI rules..."
                    tracker curl -s -S -X POST -H "$HEADERS" -H 'Content-Type: application/x-sah-ws-4-call+json' \
                        -d '{"service":"Firewall","method":"getPortForwarding","parameters":{"origin":"webui"}}' \
                        "$LIVEBOX_API_URL" | jq '.status' | tee $JSON_FOLDER/livebox5-firewall-webui.json | jq

                    echo -e "${STATUS_INFO}Listing UPnP rules..."
                    tracker curl -s -S -X POST -H "$HEADERS" -H 'Content-Type: application/x-sah-ws-4-call+json' \
                        -d '{"service":"Firewall","method":"getPortForwarding","parameters":{"origin":"upnp"}}' \
                        "$LIVEBOX_API_URL" | jq '.status' | tee $JSON_FOLDER/livebox5-firewall-upnp.json | jq

                    echo -e "${STATUS_INFO}Listing Protocol Forwarding rules..."
                    tracker curl -s -S -X POST -H "$HEADERS" -H 'Content-Type: application/x-sah-ws-4-call+json' \
                        -d '{"service":"Firewall","method":"getProtocolForwarding","parameters":{}}' \
                        "$LIVEBOX_API_URL" | jq '.status' | tee $JSON_FOLDER/livebox5-firewall-protocoles.json | jq
                    ;;
            esac
        else
            echo -e "${STATUS_ERROR}Error: No option selected"
            exit 1
        fi
        ;;
    clearcache)
        echo -e "${STATUS_INFO}Clearing cache..."
        rm -rf $JSON_FOLDER
        echo -e "${STATUS_INFO}Cache cleared"
        ;;
    custom)
        echo -e "${STATUS_INFO}Running custom POST request..."
        if INPUT=$(whiptail --backtitle "Eylexander's Livebox5.sh" --title "Custom POST request" --inputbox "Enter the POST request to send to the Livebox 5:" 10 60 3>&1 1>&2 2>&3); then
            if [ -z "$INPUT" ]; then
                echo -e "${STATUS_ERROR}Error: No POST request entered"
                exit 1
            fi
            echo -e "${STATUS_INFO}Sending :"
            echo -e "${COLOR_INVERTED}$INPUT${COLOR_RESET}"
        else
            echo -e "${STATUS_ERROR}Error: No POST request entered"
            exit 1
        fi
        OUTPUT=$(tracker curl -s -S -X POST -H "$HEADERS" -H 'Content-Type: application/x-sah-ws-4-call+json' \
            -d "$INPUT" \
            "$LIVEBOX_API_URL")
        echo "$OUTPUT" | jq | tee -a $JSON_FOLDER/livebox5-custom.json | jq;
        echo "[$INPUT, $OUTPUT]" > $JSON_FOLDER/livebox5-custom.json
        echo -e "${STATUS_INFO}Response saved in $(echo $(pwd)/$JSON_FOLDER/livebox5-custom.json)"
        echo "$OUTPUT" > $JSON_FOLDER/livebox5-customrep.json
        ;;
esac
