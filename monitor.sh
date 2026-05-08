#!/usr/bin/env bash
#monitor.sh - Real time monitoring dashboard
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.cfg"

# ANSI color constants

RST="\033[0m"
BOLD="\033[1m"
RED="\033[1;31m"
YELLOW="\033[1;33m"
GREEN="\033[1;32m"
BLUE="\033[1;34m"
CYAN="\033[1;36m"
WHITE="\033[1;37m"

BG_RED="\033[41m"
BG_YELLOW="\033[43m"
BG_GREEN="\033[42m"

#Helper function to pick a color

color_by_threshold() {
	local value=$1
	local warn=$2
	local crit=$3

	if (($(echo "$value >= $crit" | bc -l)));then
		echo "$RED"
	elif (($(echo "$value >= $warn" | bc -l)));then
		echo "$YELLOW"
	else
		echo "$GREEN"
	fi
}

status_label() {
	local value=$1
	local warn=$2
	local crit=$3

	if (($(echo "$value >= $crit" | bc -l)));then
		echo -e "${BG_RED}${WHITE} CRITICAL ${RST}"
	elif (($(echo "$value >= $warn" | bc -l)));then
		echo -e "${BG_YELLOW}${WHITE} WARNING ${RST}"
	else
		echo -e "${BG_GREEN}${WHITE} NORMAL ${RST}"
	fi
}

draw_bar() {
	local percent=$1
	local width=30
	local filled

	filled=$(echo "$percent * $width/100" | bc)
	local empty=$((width - filled))
	local bar=""

	for ((i=0; i<filled; i++)); do bar+="█"; done
	for ((i=0; i<empty; i++)); do bar+="░"; done

	echo -e "$bar"
}


#Main Logic

get_cpu_usage(){
	local cpu_line1
	cpu_line1=$(grep '^cpu ' /proc/stat)
        local user1=$(echo "$cpu_line1" | awk '{print $2}')
   	local nice1=$(echo "$cpu_line1" | awk '{print $3}')
   	local system1=$(echo "$cpu_line1" | awk '{print $4}')
   	local idle1=$(echo "$cpu_line1" | awk '{print $5}')
   	local iowait1=$(echo "$cpu_line1" | awk '{print $6}')
   	local total1=$((user1 + nice1 + system1 + idle1 + iowait1))

	sleep 1

	local cpu_line2
	cpu_line2=$(grep '^cpu ' /proc/stat)
        local user2=$(echo "$cpu_line2" | awk '{print $2}')
        local nice2=$(echo "$cpu_line2" | awk '{print $3}')
        local system2=$(echo "$cpu_line2" | awk '{print $4}')
        local idle2=$(echo "$cpu_line2" | awk '{print $5}')
        local iowait2=$(echo "$cpu_line2" | awk '{print $6}')
        local total2=$((user2 + nice2 + system2 + idle2 + iowait2))

	local total_delta=$((total2 - total1))
	local idle_delta=$((idle2 - idle1))

	local cpu_pct
	cpu_pct=$(echo "scale=1; (1-$idle_delta / $total_delta)*100 "| bc -l)

	echo "$cpu_pct"
}

get_mem_usage(){
	local mem_line
	mem_line=$(free -m | grep '^Mem:')
	local total=$(echo "$mem_line" | awk '{print $2}')
	local used=$(echo "$mem_line" | awk '{print $3}')

	local pct
	pct=$(echo "scale=1; $used*100 / $total" | bc -l)

	echo "${pct}|${used}|${total}"
}

get_disk_usage(){
	local disk_line
	disk_line=$(df -h / | tail -n 1)

	local total=$(echo "$disk_line" | awk '{print $2}')
	local used=$(echo "$disk_line" | awk '{print $3}')
	local avail=$(echo "$disk_line" | awk '{print $4}')
	local pct=$(echo "$disk_line" | awk '{print $5}' | tr -d '%')

	echo "${pct}|${used}|${total}|${avail}"
}

get_load_averageg(){
	local load_line
	load_line=$(cat /proc/loadavg)

	local load1=$(echo "$load_line" | awk '${print $1}')
	local load5=$(echo "$load_line" | awk '${print $2}')
	local load15=$(echo "$load_line" | awk '${print $3}')

	echo "${load1}|${load5}|${load15}"
}

get_network_connections(){
	local established=0
	local listening=0
	local total=0

	if command -v ss &>/dev/null; then
		established=$(ss -tun state established 2>/dev/null | tail -n +2 | wc -l)
		listening=$(ss -tuln state listening 2>/dev/null | tail -n +2 | wc -l)
		total=$(ss -tun 2>/dev/null | tail -n +2 | wc -l)
	fi

	echo "${established}|${listening}|${total}"
}

get_network_speed(){
	local iface
	iface=$(ip -o link show up 2>/dev/null \ | awk -F': ' '$2 != "lo" {print $2; exit}')

	if [[ -z "$iface" ]]; then
		echo "none|0|0"
		return
	fi

	local rx_path="/sys/class/net/${iface}/statistics/rx_bytes"
	local tx_path="/sys/class/net/${iface}/statistics/tx_bytes"

	local rx1=$(cat "$rx_path" 2>/dev/null || echo 0)
        local tx1=$(cat "$tx_path" 2>/dev/null || echo 0)

	sleep 1

	local rx2=$(cat "$rx_path" 2>/dev/null || echo 0)
	local tx2=$(cat "$tx_path" 2>/dev/null || echo 0)

	local rx_kbps=$(( (rx2 - rx1) / 1024 ))
	local tx_kbps=$(( (tx2 - tx1) / 1024 ))

	echo "${iface}|${rx_kbps}|${tx_kbps}"
}

get_top_processes(){
	ps -eo pid,user,%cpu,%mem,comm --sort=%cpu --no-headers \
	       	| head -n 5 \ 
		| awk '{printf "%s|%s|%s|%s|%s\n", $1, $2, $3, $4, $5}'
}

get_error_rate(){
	local count=0
	if command -v journalctl &>/dev/null; then
		count=$(journalctl --since "5 minutes ago" -p err --no-pager 2>/dev/null \
			| wc -l)
		(( count > 0 )) && count=$((count - 1))
	fi

	echo "$count"
}

